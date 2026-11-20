extends RefCounted
const PhysicalSprites = preload("res://scripts/visuals/physical_sprite_atlas.gd")
# D4: original high-density pixel motifs drawn as tiny atlas-like shapes.
# No external textures or font assets, no nodes per item and no GPU particles.
const P := {
    "k": Color("#253836"), # darkest outline
    "d": Color("#52605a"), # deep stone
    "s": Color("#858c81"), # stone base
    "l": Color("#cbd0b8"), # sunlit stone
    "w": Color("#9b714b"), # timber
    "h": Color("#dbb17c"), # lit timber
    "f": Color("#6e9b65"), # foliage/fibre
    "g": Color("#a8c583"), # lit grass
    "c": Color("#d3c49a"), # cordage
    "m": Color("#b7c0ae"), # metal
    "t": Color("#8d675b"), # roof tiles
    "r": Color("#c78865"), # roof highlights
    "a": Color("#ecc979"), # hearth glow
    "q": Color("#dccfba")  # pale textiles
}
# Each sprite has nine rows of nine square pixel positions.
const ICONS := {
    "wood": [
        ".........", "...hh....", "..hwww...", "..hwww...", "..wwww...",
        "...www...", "...www...", "....kk...", "........."
    ],
    "stone": [
        ".........", ".........", "...ll....", "..lsss...", ".lssssd..",
        "..ssddd..", "...dddd..", ".........", "........."
    ],
    "flint": [
        ".........", "....l....", "...ls....", "..lssd...", ".lssddd..",
        "..ssddd..", "...dd....", ".........", "........."
    ],
    "knapped_flint": [
        ".........", "....l....", "...ls....", "..lssd...", ".lssddd..",
        "...ssdd..", "...dd....", ".........", "........."
    ],
    "plant_fibre": [
        ".........", "...g.....", "..ggf....", ".fggff...", "..fgff...",
        "...ff....", "..cfc....", "...c.....", "........."
    ],
    "cordage": [
        ".........", "..cccc...", ".c....c..", ".c.cc.c..", ".c.c..c..",
        ".c....c..", "..cccc...", "...kk....", "........."
    ],
    "hammerstone": [
        ".........", ".llll....", ".lsssdd..", ".ssdddd..", "..kk.....",
        ".........", ".........", ".........", "........."
    ],
    "stone_axe": [
        "...lll...", "..lssdd..", ".llssddd.", "...skk...", "....ww...",
        "....ww...", "....ww...", "....wk...", "........."
    ],
    "stone_pick": [
        ".........", "..lllll..", ".lssssddd", "....w....", "....w....",
        "....w....", "....w....", "....k....", "........."
    ],
    "flint_knife": [
        ".....l...", "....ls...", "...lsd...", "..lsdd...", "..kww....",
        "...ww....", "...ww....", "...kk....", "........."
    ],
    "fallback": [
        ".........", "..kkk....", ".kllllk..", ".klsdsl..", ".klssdl..",
        ".kldddl..", "..kkkk...", ".........", "........."
    ]
}
const WORKSHOP := [
    "..............",
    ".....rrrr.....",
    "...rrttttrr...",
    "..rrttttttrr..",
    ".rrttttttttrr.",
    ".krrhhhhhhrrek.",
    ".kwwwwwwwwwwk.",
    ".khwmmkkmmwhk.",
    ".kwwmmkkmmwwk.",
    ".kwwwwccwwwwk.",
    ".kkwwaaawwwkk.",
    "..kkkkkkkkkk..",
    "...dddddddd...",
    ".............."
]

static func sprite(item_id: String) -> Array:
    return ICONS.get(item_id, ICONS["fallback"])

static func pixel_count(item_id: String) -> int:
    var count := 0
    for row in sprite(item_id):
        for letter in row:
            if str(letter) != ".":
                count += 1
    return count

static func draw_item(canvas: CanvasItem, item_id: String, center: Vector2, pixel: float) -> void:
    if pixel < 0.6:
        return
    if PhysicalSprites.draw_item(canvas, item_id, center, pixel * 10.0):
        return
    var rows: Array = sprite(item_id)
    var x0 := floorf(center.x - 4.5 * pixel)
    var y0 := floorf(center.y - 4.5 * pixel)
    for y in range(rows.size()):
        var row := str(rows[y])
        for x in range(row.length()):
            var letter := row.substr(x, 1)
            if letter == ".":
                continue
            canvas.draw_rect(Rect2(Vector2(x0 + float(x) * pixel, y0 + float(y) * pixel),
                Vector2(ceilf(pixel), ceilf(pixel))), P.get(letter, P["k"]))

static func draw_workshop(canvas: CanvasItem, tile_rect: Rect2, tick: int) -> void:
    var pixel := tile_rect.size.x / 15.0
    if pixel < 0.6:
        canvas.draw_rect(Rect2(tile_rect.position + tile_rect.size * 0.25,
            tile_rect.size * 0.5), P["t"])
        return
    var start := tile_rect.position + Vector2(pixel * 0.5, pixel * 0.5)
    for y in range(WORKSHOP.size()):
        var row := str(WORKSHOP[y])
        for x in range(row.length()):
            var letter := row.substr(x, 1)
            if letter == ".":
                continue
            var color: Color = P.get(letter, P["k"])
            if letter == "a" and posmod(tick / 6 + x, 3) == 0:
                color = P["h"]
            canvas.draw_rect(Rect2(start + Vector2(x, y) * pixel,
                Vector2(ceilf(pixel), ceilf(pixel))), color)

static func draw_ground(canvas: CanvasItem, tile_rect: Rect2, item_id: String,
        count: int, selected: bool = false) -> void:
    var scale := tile_rect.size.x / 12.0
    if scale < 0.6:
        return
    var center := tile_rect.position + tile_rect.size * Vector2(0.5, 0.55)
    canvas.draw_rect(Rect2(center + Vector2(-4, 3) * scale,
        Vector2(8, 2) * scale), Color(0.12, 0.16, 0.14, 0.64))
    var stack_key := "resource.%s.stack_large" % item_id if count >= 16 else (
        "resource.%s.stack_small" % item_id if count >= 4 else "")
    if stack_key == "" or not PhysicalSprites.draw(canvas, stack_key, center, scale * 10.0):
        draw_item(canvas, item_id, center, scale)
    if selected:
        canvas.draw_rect(Rect2(tile_rect.position + Vector2.ONE,
            tile_rect.size - Vector2.ONE * 2.0), Color("#e9d1a3"), false,
            maxf(1.0, tile_rect.size.x * 0.07))
    if count > 1 and tile_rect.size.x >= 23.0:
        canvas.draw_circle(tile_rect.position + tile_rect.size * Vector2(0.8, 0.2),
            maxf(2.0, scale * 2.0), Color("#2a3c38"))

static func condition_color(pct: int) -> Color:
    if pct < 25:
        return Color("#d87967")
    if pct < 55:
        return Color("#d2ae67")
    return Color("#8eb89b")
