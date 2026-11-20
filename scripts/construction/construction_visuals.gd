extends RefCounted
# Temporary crisp stakes/frame/roof overlays. No texture generation or visual clock.
static func draw(canvas: Node2D, game: Node2D) -> void:
    var ts: float = game.tile_size()
    if ts < 5.0:
        return
    var origin: Vector2 = game.world_origin()
    var viewport := Rect2(Vector2.ZERO, game.ui_size()).grow(ts * 2)
    for site in game.world.construction.projects:
        var row: Dictionary = game.world.construction.catalogue.definition(str(site["definition_id"]))
        var p := origin + Vector2(int(site["x"]), int(site["y"])) * ts
        p.y -= float(game.world.height_at(int(site["x"]), int(site["y"]))) * (12.0 / 32.0) * ts
        if not viewport.has_point(p):
            continue
        var stage: int = int(site["stage"])
        var scale := ts / 32.0
        var timber := Color("#946749")
        var colour := Color("#b68166") if site["paused"] else Color("#d6bc80")
        var width := float(row["footprint"][int(site["orientation"]) % 2]) * ts
        canvas.draw_rect(Rect2(p + Vector2(3, 8) * scale, Vector2(width - 6 * scale, 21 * scale)), Color(0.3, 0.22, 0.12, 0.35))
        for x in [5.0, width / scale - 6.0]:
            canvas.draw_rect(Rect2((p + Vector2(x, 7) * scale).round(), Vector2(2, 21) * scale), timber)
        if stage >= 1:
            canvas.draw_line(p + Vector2(5, 11) * scale, p + Vector2(width / scale - 5, 11) * scale, colour, maxf(1, scale * 2))
            canvas.draw_line(p + Vector2(5, 27) * scale, p + Vector2(width / scale - 5, 10) * scale, timber, maxf(1, scale * 2))
        if stage >= 2:
            canvas.draw_colored_polygon(PackedVector2Array([p + Vector2(2, 12) * scale, p + Vector2(width / scale / 2, 3) * scale, p + Vector2(width / scale - 2, 12) * scale]), colour)
        # Incremental details use actual work completed; never visual-clock progress.
        var built := clampf(1.0 - float(site["remaining_labour"]) / maxf(1.0, float(row["labour"])), 0.0, 1.0)
        var placed := int(floor(built * 7.0))
        for plank in range(placed):
            var px := 7.0 + float(plank % 4) * 5.0
            var py := 15.0 + float(plank / 4) * 5.0
            canvas.draw_rect(Rect2((p + Vector2(px, py) * scale).round(),
                Vector2(4, 2) * scale), Color("#a97b55"))
        if stage >= 1:
            for beam in range(3):
                var bx := 7.0 + float(beam) * (width / scale - 14.0) / 2.0
                canvas.draw_line(p + Vector2(bx, 25) * scale,
                    p + Vector2(bx, 12) * scale, timber, maxf(1.0, scale * 1.5))
        # Stage markers are derived exclusively from real work progress.
        var fraction := float(site["progress"]) / float(row["labour"])
        canvas.draw_rect(Rect2(p + Vector2(3, 30) * scale, Vector2((width - 6 * scale) * fraction, maxf(1, scale))), colour)
