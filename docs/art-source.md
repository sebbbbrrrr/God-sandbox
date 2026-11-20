# Art source and authoring record

Authoring used the built-in image-generation tool, followed by a deterministic Pillow packing pipeline. Two supplied landscape references informed the pines, roof/wall proportions, slate/moss cliffs and palette. They were not copied into the game as backgrounds.

The generation requested a strict 8×8 atlas: five pines plus bushes/stump; rocks/log/grass/flowers; four buildings and four bridge orientations; fences, well, barrels, woodpile, sign, two citizens; meadow/forest/dirt/earth textures; water/ash/rock/mountain/beach textures; eight cliff variations; and fire/blessing/ripple/reeds/fern/ledge/corner details. Constraints were original top-down pixel art, consistent top-left lighting, transparent isolated sprites, no black outlines, no labels or grid lines.

A second image-generation pass removed the pale background outside the isolated sprites while keeping terrain opaque. The selected source is `tools/source/source_sheet.png`. The exact packing, sample sizes, texture tinting, pixel alpha threshold, shoreline shapes and masks are executable in `tools/build_pixel_assets.py`.

Rebuild with Python 3 and Pillow:

```sh
python tools/build_pixel_assets.py tools/source/source_sheet.png
```

The tool output is source artwork, not evidence of gameplay. `docs/captures` contains actual Godot OpenGL renders of a procedural simulation with seed 424242 at tick 1050. `tests/capture_world.gd` recreates that state without overwriting player saves. Bridges are supplied assets awaiting a simulation feature.
