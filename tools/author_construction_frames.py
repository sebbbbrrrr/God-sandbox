#!/usr/bin/env python3
"""Regenerate the 37 original-pixel construction-frame sheets.

No new/low-res building art is synthesized: the approved atlas pixels are
selected by the per-building, manually authored geometry in
data/architecture/hand_authored_piece_layouts.json.

Each sheet packs 32 cumulative frames in an 8x4 grid. Files are stored as
PNG bytes encoded in UTF-8 Base64 so Godot's Android export includes them
without texture import side effects. The final frame is losslessly equal
to the corresponding source atlas rectangle.
"""
import argparse
import base64
import io
import json
import math
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ATLAS = ROOT / "assets" / "pixel"
DEST = ATLAS / "construction_frames"
COLUMNS, ROWS = 8, 4


def reveal_step(x: int, y: int, w: int, h: int, spec: dict) -> int:
    nx, ny = x / max(1, w), y / max(1, h)
    base = spec["foundation_start"]
    roof = spec["roof_end"]
    if ny >= base:
        row = max(0, (h - 1 - y) // max(2, spec["brick_height"]))
        offset = spec["brick_width"] // 2 if row % 2 else 0
        col = (x + offset) // spec["brick_width"]
        rows = math.ceil((1 - base) * h / spec["brick_height"])
        cols = math.ceil(w / spec["brick_width"]) + 1
        progress = (row * cols + col) / max(1, rows * cols)
        return min(6, 1 + math.floor(progress * 6))
    if ny >= roof:
        near_post = any(abs(nx - p) < max(0.014, 2 / w) for p in spec["posts"])
        if near_post:
            return 7 + math.floor((base - ny) / (base - roof) * 3)
        row = max(0, math.floor((base * h - y) / spec["brick_height"]))
        offset = spec["brick_width"] // 2 if row % 2 else 0
        col = (x + offset) // spec["brick_width"]
        rows = max(1, math.ceil((base - roof) * h / spec["brick_height"]))
        cols = max(1, math.ceil(w / spec["brick_width"]) + 1)
        progress = max(0, min(.999, (row * cols + col) / (rows * cols)))
        return 9 + math.floor(progress * 13)
    row = max(0, math.floor((roof * h - y) / spec["tile_height"]))
    offset = spec["tile_width"] // 2 if row % 2 else 0
    col = (x + offset) // spec["tile_width"]
    rows = max(1, math.ceil(roof * h / spec["tile_height"]))
    cols = max(1, math.ceil(w / spec["tile_width"]) + 1)
    progress = max(0, min(.999, (row * cols + col) / (rows * cols)))
    return 22 + math.floor(progress * 9)


def generate(source: Image.Image, spec: dict) -> Image.Image:
    original = source.convert("RGBA")
    w, h = original.size
    sheet = Image.new("RGBA", (w * COLUMNS, h * ROWS))
    pixels = original.load()
    construction = [
        (x, y, pixels[x, y], reveal_step(x, y, w, h, spec))
        for y in range(h) for x in range(w) if pixels[x, y][3]
    ]
    result = sheet.load()
    for frame in range(1, COLUMNS * ROWS):
        dx = (frame % COLUMNS) * w
        dy = (frame // COLUMNS) * h
        for x, y, rgba, step in construction:
            if step <= frame:
                result[dx + x, dy + y] = rgba
    sheet.paste(original, (w * (COLUMNS - 1), h * (ROWS - 1)))
    return sheet


def run(verify_only: bool = False) -> None:
    manifest = json.loads((ROOT / "data/architecture/hand_authored_piece_layouts.json").read_text())
    buildings = json.loads((ROOT / "data/buildings/catalogue.json").read_text())["buildings"]
    atlas = json.loads((ATLAS / "atlas.json").read_text())
    pages = json.loads((ATLAS / "pages.json").read_text())
    images = [Image.open(ATLAS / filename).convert("RGBA") for filename in pages]
    assert len(buildings) == len(manifest["layouts"]), "Missing individual authored layout"
    if not verify_only:
        DEST.mkdir(parents=True, exist_ok=True)
    count = 0
    for building in buildings:
        name = building["id"]
        layout = manifest["layouts"][name]
        sprite = building["visual"]["sprite"]
        entry = atlas[sprite]
        x, y, w, h = entry["packed_rect"]
        original = images[entry.get("page", 0)].crop((x, y, x + w, y + h))
        output = DEST / (name + ".png.b64")
        if verify_only:
            assert output.is_file(), f"Missing frame sheet: {name}"
            sheet = Image.open(io.BytesIO(base64.b64decode(output.read_text()))).convert("RGBA")
        else:
            sheet = generate(original, layout)
            buffer = io.BytesIO()
            sheet.save(buffer, "PNG", optimize=True)
            output.write_text(base64.b64encode(buffer.getvalue()).decode("ascii"))
        assert sheet.size == (w * COLUMNS, h * ROWS), f"Incorrect size: {name}"
        assert sheet.crop(((COLUMNS - 1)*w, (ROWS - 1)*h,
                          COLUMNS*w, ROWS*h)).tobytes() == original.tobytes(), name
        count += 1
    print(f"PASS: {count} custom construction sheets, {count*COLUMNS*ROWS} cumulative frames")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--verify", action="store_true", help="verify committed frames against originals")
    options = parser.parse_args()
    run(options.verify)
