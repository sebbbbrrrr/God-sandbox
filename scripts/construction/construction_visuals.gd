extends RefCounted
# Site artwork uses ONLY real project stage, stage_work and material custody.
# Smooth intermittent tool animation is drawn separately by citizen_work_visuals.
static func draw(canvas: Node2D, game: Node2D) -> void:
    var ts: float = game.tile_size()
    if ts < 5.0:
        return
    var origin: Vector2 = game.world_origin()
    var visible := Rect2(Vector2.ZERO, game.ui_size()).grow(ts * 2.0)
    # A camp is an actual local staging store, not a pre-completed house.
    # Reuse the original full-density crate artwork; draw only visible camps.
    if game.world_renderer != null:
        var atlas = game.world_renderer.atlas
        for key in game.world.settlements.records:
            var settlement: Dictionary = game.world.settlements.records[key]
            if str(settlement["status"]) != "camp":
                continue
            var cell: Vector2i = game.world.settlements.center(game.world, int(key))
            var p := origin + Vector2(cell) * ts
            p.y -= float(game.world.height_at(cell.x, cell.y)) * (12.0 / 32.0) * ts
            if not visible.has_point(p):
                continue
            var extent: Vector2 = atlas.size_of("crates") * ts / 32.0
            canvas.draw_texture_rect_region(atlas.texture("crates"),
                Rect2(p + Vector2(ts * 0.5, ts * 0.8) - extent * Vector2(0.5, 1.0), extent),
                atlas.region("crates"))
    for site in game.world.construction.projects:
        var row: Dictionary = game.world.construction.catalogue.definition(str(site["definition_id"]))
        if row.is_empty():
            continue
        var x: int = int(site["x"])
        var y: int = int(site["y"])
        var p := origin + Vector2(x, y) * ts
        p.y -= float(game.world.height_at(x, y)) * (12.0 / 32.0) * ts
        if not visible.has_point(p):
            continue
        var s: float = ts / 32.0
        var stages: Array = row.get("stages", [])
        var stage: int = clampi(int(site.get("stage", 0)), 0, stages.size())
        var stage_work: int = int(site.get("stage_work", 0))
        var total_labour: int = maxi(1, int(row.get("labour", 1)))
        var completed: float = clampf(float(int(site.get("progress", 0))) / float(total_labour), 0.0, 1.0)
        var current: float = 1.0
        if stage < stages.size():
            current = clampf(float(stage_work) / maxf(1.0, float(stages[stage].get("labour", 1))), 0.0, 1.0)
        var footprint: Array = row.get("footprint", [1, 1])
        var orientation: int = int(site.get("orientation", 0))
        var width: float = float(footprint[orientation % 2]) * ts
        var height: float = float(footprint[1 - orientation % 2]) * ts
        var w: float = width / s
        var h: float = height / s
        var timber := Color("#906343")
        var timber_light := Color("#c5a076")
        var stone := Color("#989991")
        var roof := Color("#ba895d")
        var paused: bool = bool(site.get("paused", false))
        # Ground / trenches / foundation, controlled by actual stage work.
        canvas.draw_rect(Rect2(p + Vector2(2, 8) * s, Vector2(width - 4 * s, height - 10 * s)), Color("#473d30", 0.4))
        if stage == 0:
            var earth_width: float = (w - 8.0) * current
            canvas.draw_rect(Rect2(p + Vector2(4, h - 8) * s, Vector2(earth_width, 4) * s), Color("#79634e"))
        # Survey stakes and string are the immediate visible site state.
        for bx in [4.0, w - 5.0]:
            canvas.draw_rect(Rect2((p + Vector2(bx, 7) * s).round(), Vector2(2, h - 12) * s), timber)
        canvas.draw_line(p + Vector2(5, h - 7) * s, p + Vector2(w - 5, h - 7) * s,
            Color("#c5b185"), maxf(1.0, s))
        # Stone foundation only appears when the structural stage begins.
        if stage >= 1:
            var stones: int = 4 if stage > 1 else maxi(1, int(floor(current * 4.0)))
            for i in range(stones):
                var fx := 5.0 + float(i) * (w - 10.0) / 4.0
                canvas.draw_rect(Rect2((p + Vector2(fx, h - 11) * s).round(),
                    Vector2((w - 11.0) / 4.0, 5) * s), stone)
            # Uprights, walls, bracing and horizontal beams are earned by labour.
            var posts: int = 4 if stage > 1 else int(floor(current * 4.0))
            for i in range(posts):
                var px := 5.0 + float(i) * (w - 10.0) / 3.0
                canvas.draw_rect(Rect2((p + Vector2(px, 10) * s).round(), Vector2(3, h - 19) * s), timber)
            if stage > 1 or current >= 0.55:
                canvas.draw_line(p + Vector2(5, 12) * s, p + Vector2(w - 5, 12) * s, timber_light, maxf(1.0, 3.0 * s))
            if stage > 1 or current >= 0.75:
                canvas.draw_line(p + Vector2(6, h - 11) * s, p + Vector2(w - 7, 12) * s, timber, maxf(1.0, 2.0 * s))
            # Finite plank rows: no pre-completion instant full house.
            var rows: int = 3 if stage > 1 else int(floor(current * 3.0))
            for i in range(rows):
                var py := h - 15.0 - float(i) * 5.0
                canvas.draw_rect(Rect2((p + Vector2(7, py) * s).round(),
                    Vector2(w - 14.0, 3) * s), Color("#ad8258", 0.8))
        # Roofing, thatch/tile rows, ridge and door are progressive finishing art.
        if stage >= 2:
            var roof_width := (w - 4.0) * current
            var a := p + Vector2(2, 12) * s
            var b := p + Vector2(2.0 + roof_width * 0.5, 2) * s
            var c := p + Vector2(2.0 + roof_width, 12) * s
            if current > 0.0:
                canvas.draw_colored_polygon(PackedVector2Array([a, b, c]), roof)
                var rows: int = int(floor(current * 4.0))
                for i in range(rows):
                    var ry := 7.0 + float(i) * 2.0
                    canvas.draw_line(p + Vector2(5, ry) * s,
                        p + Vector2(2.0 + roof_width - 3.0, ry) * s,
                        Color("#d7b078", 0.7), maxf(1.0, s))
            if current >= 0.65:
                canvas.draw_rect(Rect2((p + Vector2(w * 0.42, h - 13) * s).round(),
                    Vector2(5, 9) * s), Color("#725139"))
                canvas.draw_rect(Rect2((p + Vector2(w * 0.42 + 3, h - 8) * s).round(),
                    Vector2.ONE * maxf(1.0, s)), Color("#d8b87c"))
        # Temporary on-site supply stack: shown only for confirmed deliveries.
        var delivered: Dictionary = site.get("delivered", {})
        var consumed: Dictionary = site.get("consumed", {})
        var loose_wood := maxi(0, int(delivered.get("wood", 0)) - int(consumed.get("wood", 0)))
        var loose_stone := maxi(0, int(delivered.get("stone", 0)) - int(consumed.get("stone", 0)))
        if ts >= 13.0:
            for i in range(mini(3, loose_wood)):
                canvas.draw_line(p + Vector2(w - 12, h - 8 - i * 2) * s,
                    p + Vector2(w - 3, h - 10 - i * 2) * s, timber_light, maxf(1.0, 2.0 * s))
            for i in range(mini(3, loose_stone)):
                canvas.draw_rect(Rect2((p + Vector2(3 + i * 4, h - 6) * s).round(), Vector2(4, 3) * s), stone)
        if paused:
            canvas.draw_rect(Rect2(p + Vector2(2, 2) * s, Vector2(width - 4 * s, height - 4 * s)),
                Color("#995a45", 0.18))
        # Real labour progress only, not smooth fictitious time-based building.
        canvas.draw_rect(Rect2(p + Vector2(3, h - 1) * s,
            Vector2((w - 6.0) * completed, maxf(1.0, s))), Color("#d6bc80"))
