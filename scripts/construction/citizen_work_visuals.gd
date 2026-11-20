extends RefCounted
# Presentation-only citizen work effects. All state comes from real construction jobs
# and physical cargo; animation never changes the simulation or creates materials.
static func draw(canvas: Node2D, game: Node2D, clock: float) -> void:
    var world = game.world
    var ts: float = game.tile_size()
    if ts < 9.0:
        return
    var origin: Vector2 = game.world_origin()
    var viewport := Rect2(Vector2.ZERO, game.ui_size()).grow(ts)
    var jobs: Dictionary = world.construction.jobs
    for citizen in world.citizens:
        if int(citizen.get("hp", 0)) <= 0:
            continue
        var id := int(citizen["id"])
        var job: Dictionary = jobs.get(str(id), {})
        if job.is_empty():
            continue
        var kind := str(job.get("kind", ""))
        var phase := str(job.get("phase", ""))
        var visual := Vector2(float(citizen["x"]), float(citizen["y"]))
        var moving := false
        if game.world_renderer != null and game.world_renderer.walks != null:
            var walks = game.world_renderer.walks
            if walks.tracks.has(id):
                visual = walks.visual_tile(id)
                moving = walks.walk_phase(id) >= 0.0
        var p := origin + (visual + Vector2(0.5, 0.5)) * ts
        p.y -= float(world.height_at(int(citizen["x"]), int(citizen["y"]))) * (12.0 / 32.0) * ts
        if not viewport.has_point(p):
            continue
        var size := ts / 32.0
        var cargo: Dictionary = job.get("cargo", {})
        if kind == "gather" and phase == "depot":
            cargo = {str(job.get("material", "wood")): int(job.get("amount", 0))}
        # A carried bundle exists only while the citizen actually has cargo.
        if not cargo.is_empty():
            var material := "wood" if int(cargo.get("wood", 0)) > 0 else ("stone" if int(cargo.get("stone", 0)) > 0 else str(cargo.keys()[0]))
            _bundle(canvas, p + Vector2(-7, -13) * size, size, material)
        if moving:
            continue
        var at_site := false
        if kind in ["build", "repair", "demolish"] and phase == "site":
            var site: Dictionary = world.construction.site_by_id(int(job.get("project_id", 0)))
            if not site.is_empty():
                at_site = absi(int(citizen["x"]) - int(site["x"])) <= 1 and absi(int(citizen["y"]) - int(site["y"])) <= 1
        if at_site and cargo.is_empty():
            _work(canvas, p, size, clock + float(id) * 0.7, kind)
        elif kind == "gather" and phase == "source":
            var target: Array = job.get("target", [])
            if target.size() >= 2 and int(citizen["x"]) == int(target[0]) and int(citizen["y"]) == int(target[1]):
                _work(canvas, p, size, clock + float(id) * 0.7, str(job.get("material", "wood")))
    # Stage-based scaffold and work particles are rendered with the job layer;
    # paused sites and idle citizens cannot generate working effects.

static func _bundle(canvas: Node2D, at: Vector2, scale: float, material: String) -> void:
    var q := at.round()
    if material in ["wood", "plant_fibre"]:
        for i in range(3):
            canvas.draw_line(q + Vector2(0, i * 3) * scale, q + Vector2(11, i * 3 - 2) * scale, Color("#8e5938"), maxf(1.0, 3.0 * scale))
        canvas.draw_line(q + Vector2(5, -2) * scale, q + Vector2(7, 8) * scale, Color("#d9ba79"), maxf(1.0, scale))
    else:
        canvas.draw_colored_polygon(PackedVector2Array([q, q + Vector2(6, -4) * scale, q + Vector2(12, 1) * scale, q + Vector2(9, 8) * scale, q + Vector2(1, 7) * scale]), Color("#a0a49b"))
        canvas.draw_line(q + Vector2(6, -4) * scale, q + Vector2(5, 4) * scale, Color("#dee1cb"), maxf(1.0, scale))

static func _work(canvas: Node2D, p: Vector2, scale: float, clock: float, kind: String) -> void:
    # Per-worker phase offset avoids synchronized motion, with no per-NPC Nodes.
    var swing := sin(clock * 5.0)
    var hand := p + Vector2(7, -5 + swing * 4.0) * scale
    var tool_color := Color("#b58a51") if kind in ["build", "repair", "wood"] else Color("#aeb4b2")
    canvas.draw_line(p + Vector2(2, 0) * scale, hand, Color("#d8b18a"), maxf(1.0, 2.0 * scale))
    canvas.draw_line(hand, hand + Vector2(7, -6 + swing * 2.0) * scale, Color("#634d3a"), maxf(1.0, 2.0 * scale))
    canvas.draw_rect(Rect2(hand + Vector2(5, -8 + swing * 2.0) * scale, Vector2(6, 3) * scale), tool_color)
    # Dust/chips only while a genuine work job is active at its destination.
    if swing > 0.7:
        for i in range(3):
            var offset := Vector2(10 + i * 3, 1 - i * 4) * scale
            canvas.draw_rect(Rect2((p + offset).round(), Vector2.ONE * maxf(1.0, scale * 2.0)), Color("#d6b88c", 0.8))
