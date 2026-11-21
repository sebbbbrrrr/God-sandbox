extends RefCounted
# Visual-only facility motion. All activity is keyed to real jobs or paid services.
# No new production, resources or simulation side effects.
const MAX_ANIMATED := 48

static func draw(canvas: Node2D, game: Node2D) -> void:
    var ts: float = game.tile_size()
    if ts < 12.0:
        return
    var active: Dictionary = {}
    for task in game.world.construction.jobs.values():
        if str(task.get("kind", "")) == "operate" and str(task.get("phase", "")) == "site":
            active[int(task.get("building_id", -1))] = true
    var clock: float = float(game.world.tick) * 0.13
    var origin: Vector2 = game.world_origin()
    var visible := Rect2(Vector2.ZERO, game.ui_size()).grow(ts * 3.0)
    var rendered := 0
    for house in game.world.construction.houses:
        if rendered >= MAX_ANIMATED:
            break
        if bool(house.get("abandoned", false)) or int(house.get("condition", 100)) < 25:
            continue
        var id: int = int(house.get("id", -1))
        var live: bool = active.has(id)
        var kind: String = str(house.get("definition_id", ""))
        var irrigation: bool = kind == "water_lift" and int(house.get("irrigation_until", 0)) > game.world.tick
        if not live and not irrigation:
            continue
        var row: Dictionary = game.world.construction.catalogue.definition(kind)
        var footprint: Array = row.get("footprint", [1, 1])
        var x: int = int(house["x"])
        var y: int = int(house["y"])
        var s := ts / 32.0
        var p := origin + Vector2(x, y) * ts
        p.y -= float(game.world.height_at(x, y)) * 12.0 * s
        if not visible.has_point(p):
            continue
        var center := p + Vector2(float(footprint[0]) * 16.0, 14.0) * s
        rendered += 1
        match kind:
            "grain_grinding_shelter":
                _wheel(canvas, center, 8.0 * s, clock * 1.1, s, Color("#b9a891"), 6)
                _hub(canvas, center, s)
            "water_lift":
                _wheel(canvas, center, 11.0 * s, clock * 0.72, s, Color("#987047"), 8)
                _hub(canvas, center, s)
                if irrigation:
                    canvas.draw_line(center + Vector2(0, 12) * s, center + Vector2(0, 17) * s,
                        Color("#76b8c6"), maxf(1.0, 2.0 * s))
            "timber_workyard", "masonry_workyard":
                _reciprocate(canvas, center, clock, s, Color("#ddbc8c"))
            "weaving_house", "cordage_canopy":
                _reciprocate(canvas, center, clock * 1.3, s, Color("#d8c8a2"))
            "bronze_forge", "bronze_smelter", "pottery_kiln", "charcoal_clamp":
                _embers(canvas, center + Vector2(0, 7) * s, clock, s)
            _:
                # Other production facilities have a restrained working indicator
                # rather than an unrelated moving mechanism.
                if live and not row.get("production", []).is_empty():
                    _reciprocate(canvas, center, clock * 0.65, s, Color("#c9aa78"))

static func _wheel(canvas: Node2D, center: Vector2, radius: float, angle: float, s: float, shade: Color, spokes: int) -> void:
    # 16-segment polygon keeps the motion crisp and avoids filtered textures.
    canvas.draw_arc(center, radius, 0.0, TAU, 16, shade, maxf(1.0, 2.0 * s))
    for n in range(spokes):
        var a: float = angle + float(n) * TAU / float(spokes)
        var direction := Vector2(cos(a), sin(a))
        canvas.draw_line((center + direction * radius * 0.18).round(),
            (center + direction * radius * 0.87).round(), shade, maxf(1.0, s))

static func _hub(canvas: Node2D, center: Vector2, s: float) -> void:
    canvas.draw_rect(Rect2((center - Vector2.ONE * s).round(), Vector2.ONE * maxf(2.0, s * 2.0)), Color("#594b3b"))

static func _reciprocate(canvas: Node2D, center: Vector2, clock: float, s: float, shade: Color) -> void:
    var displacement: float = roundf(sin(clock * 2.0) * 3.0) * s
    canvas.draw_line((center + Vector2(-7, displacement / s) * s).round(),
        (center + Vector2(7, displacement / s) * s).round(), shade, maxf(1.0, 2.0 * s))

static func _embers(canvas: Node2D, center: Vector2, clock: float, s: float) -> void:
    for i in range(3):
        var height: float = 3.0 + float(posmod(floori(clock * 3.0) + i * 3, 6))
        var pos := (center + Vector2(float(i - 1) * 3.0, -height) * s).round()
        canvas.draw_rect(Rect2(pos, Vector2.ONE * maxf(1.0, s)),
            Color("#e6b06b") if i % 2 == 0 else Color("#db7956"))
