extends Node2D
class_name CivilisationMapOverlay
## Non-interactive, camera-anchored map visualisation. Real link polylines
## and labels are sampled from the read-only observatory projection.
const GOOD := Color("#8bce99")
const BUILDING := Color("#e6c588")
const BLOCKED := Color("#dc8c7c")
const NATION := [Color("#e9ca8f"), Color("#c7a6c7")]
const MAX_POINTS_PER_ROUTE := 64
const MAX_VISIBLE_LINKS := 48

var game: Node2D
var snapshot: Dictionary = {}
var enabled := false

func configure(source: Node2D) -> void:
    game = source


func set_snapshot(data: Dictionary) -> void:
    snapshot = data
    if enabled:
        queue_redraw()


func set_enabled(value: bool) -> void:
    enabled = value
    visible = value
    queue_redraw()


func _screen(x: float, y: float) -> Vector2:
    return game.world_origin() + Vector2(x + 0.5, y + 0.5) * game.tile_size()


func _draw() -> void:
    if not enabled or game == null or snapshot.is_empty():
        return
    var screen := get_viewport_rect().size
    var drawn := 0
    for link in snapshot.get("routes", []):
        if drawn >= MAX_VISIBLE_LINKS:
            break
        drawn += 1
        var color := GOOD if str(link["status"]) == "connected" else (
            BLOCKED if str(link["status"]) == "blocked" else BUILDING)
        var path: Array = link.get("path", [])
        if path.size() < 2:
            continue
        var points := PackedVector2Array()
        var jump := maxi(1, ceili(float(path.size()) / float(MAX_POINTS_PER_ROUTE)))
        for i in range(0, path.size(), jump):
            var cell: Array = path[i]
            if cell.size() >= 2:
                points.append(_screen(float(cell[0]), float(cell[1])))
        var last: Array = path[path.size() - 1]
        if last.size() >= 2:
            points.append(_screen(float(last[0]), float(last[1])))
        if points.size() >= 2:
            draw_polyline(points, Color(color, 0.8), 2.4, true)
    var font := ThemeDB.fallback_font
    for row in snapshot.get("settlements", []):
        var point := _screen(float(row["x"]), float(row["y"]))
        if point.x < -100 or point.y < -40 or point.x > screen.x + 100 or point.y > screen.y + 40:
            continue
        var color: Color = NATION[clampi(int(row["nation"]), 0, NATION.size() - 1)]
        if str(row["status"]) in ["struggling", "failed", "abandoned"]:
            color = BLOCKED
        var radius := clampf(5.0 + sqrt(float(row["population"])) * 0.5, 6.0, 13.0)
        draw_circle(point, radius + 3, Color(0.04, 0.08, 0.06, 0.7))
        draw_arc(point, radius, 0.0, TAU, 24, color, 2.4, true)
        draw_circle(point, 3.5, color)
        var title: String = str(row["name"])
        var width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
        var label_pos := Vector2(point.x - width * 0.5, point.y - radius - 10)
        draw_rect(Rect2(label_pos + Vector2(-4, -11), Vector2(width + 8, 16)),
            Color(0.06, 0.13, 0.11, 0.82))
        draw_string(font, label_pos, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)
