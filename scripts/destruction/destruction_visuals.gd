extends RefCounted
## Camera-culled pixel effects for authoritative structure fires and debris.
## Never changes simulation state. No permanent nodes or particle allocations.
const EMBER := Color("#f8bd58")
const HOT := Color("#ee7540")
const CHAR := Color("#4a3d36")
const STONE := Color("#85817a")
const ASH := Color("#665650")
const MAX_VISIBLE := 64

static func draw(canvas: Node2D, game: Node2D, clock: float) -> void:
    var destruction = game.world.construction.destruction
    var cell_px: float = game.tile_size()
    if cell_px < 6.0:
        return
    var origin: Vector2 = game.world_origin()
    var bounds := Rect2(Vector2.ZERO, game.ui_size()).grow(cell_px * 2.0)
    var scale: float = cell_px / 32.0
    var visible := 0
    for row in destruction.rubble:
        if visible >= MAX_VISIBLE:
            break
        var cells: Array = row.get("cell", [])
        if cells.size() != 2:
            continue
        var point := Vector2(float(cells[0]), float(cells[1]))
        var p: Vector2 = origin + point * cell_px
        p.y -= float(game.world.height_at(int(cells[0]), int(cells[1]))) * (12.0 / 32.0) * cell_px
        if not bounds.has_point(p):
            continue
        visible += 1
        var age: int = int(row.get("tick", 0))
        var wobble := float(posmod(int(row.get("building_id", 1)) * 13 + age, 7))
        canvas.draw_rect(Rect2((p + Vector2(5.0, 22.0) * scale).round(),
            Vector2(22.0, 6.0) * scale), Color(0.21, 0.18, 0.16, 0.55))
        for i in range(4):
            var x: float = 5.0 + float(i * 6)
            var y: float = 18.0 + float(posmod(i + int(wobble), 4)) * 2.0
            var tint := CHAR if (i + int(wobble)) % 2 == 0 else STONE
            canvas.draw_rect(Rect2((p + Vector2(x, y) * scale).round(),
                Vector2(5.0, 4.0) * scale), tint)
        canvas.draw_rect(Rect2((p + Vector2(12, 17) * scale).round(),
            Vector2(5, 3) * scale), ASH)
    for id in destruction.fires:
        if visible >= MAX_VISIBLE:
            break
        var house: Dictionary = game.world.construction.building_by_id(int(id))
        if house.is_empty():
            continue
        var x := int(house["x"])
        var y := int(house["y"])
        var p: Vector2 = origin + Vector2(float(x), float(y)) * cell_px
        p.y -= float(game.world.height_at(x, y)) * (12.0 / 32.0) * cell_px
        if not bounds.has_point(p):
            continue
        visible += 1
        var intensity: int = int(destruction.fires[id].get("intensity", 1))
        var t: float = clock * 4.0 + float(posmod(int(id) * 37, 29))
        var bottom := p + Vector2(16.0, 19.0) * scale
        var height: float = (8.0 + float(intensity) * 3.0 + sin(t) * 2.0) * scale
        # Jagged compact flames share the pixel-art scale. No smooth gradients.
        canvas.draw_colored_polygon(PackedVector2Array([
            bottom + Vector2(-7, 0) * scale,
            bottom + Vector2(-4, -height * 0.70),
            bottom + Vector2(-1, -height * 0.38),
            bottom + Vector2(3, -height),
            bottom + Vector2(6, -height * 0.3),
            bottom + Vector2(8, 0) * scale
        ]), HOT)
        canvas.draw_rect(Rect2((bottom + Vector2(-2, -3) * scale).round(),
            Vector2(4, 6) * scale), EMBER)
        for i in range(mini(intensity, 3)):
            var rise := float(posmod(int(clock * 3.0) + i * 7 + int(id), 15))
            canvas.draw_rect(Rect2((bottom + Vector2(float(i * 5 - 5), -12.0 - rise) * scale).round(),
                Vector2.ONE * maxf(1.0, scale * 2.0)), Color(0.47, 0.43, 0.40, 0.50))
        var health_ratio: float = float(house.get("condition", 0)) / maxf(1.0, float(house.get("max_health", 100)))
        if health_ratio < 0.7:
            var crack := p + Vector2(5, 11) * scale
            canvas.draw_line(crack, crack + Vector2(6, 5) * scale, CHAR, maxf(1.0, scale))
            canvas.draw_line(crack + Vector2(6, 5) * scale,
                crack + Vector2(3, 12) * scale, CHAR, maxf(1.0, scale))
