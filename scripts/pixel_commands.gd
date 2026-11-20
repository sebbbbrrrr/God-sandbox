extends Node2D
class_name PixelCommands

# One cached CanvasItem per chunk/layer or occupied depth row, never per sprite.
# Godot retains its draw commands until a dirty chunk asks for a redraw.
var atlas: PixelAtlas
var keys: Array[String] = []
var positions := PackedVector2Array()
var sizes := PackedVector2Array()
var tints := PackedColorArray()
var sway_factors := PackedFloat32Array()
var sway_time := 0.0
var wind_strength := 0.0
var wind_x := 1.0

func clear_commands() -> void:
    keys.clear()
    positions.clear()
    sizes.clear()
    tints.clear()
    sway_factors.clear()

func add(key: String, at_pos: Vector2, draw_size: Vector2 = Vector2.ZERO,
        tint: Color = Color.WHITE, sway: float = 0.0) -> void:
    keys.append(key)
    positions.append(at_pos)
    sizes.append(atlas.size_of(key) if draw_size == Vector2.ZERO else draw_size)
    tints.append(tint)
    sway_factors.append(sway)

func set_wind(seconds: float, strength: float, horizontal: float) -> void:
    sway_time = seconds
    wind_strength = strength
    wind_x = horizontal
    if not keys.is_empty():
        queue_redraw()

func _draw() -> void:
    for i in range(keys.size()):
        if sway_factors[i] > 0.0 and wind_strength > 0.01:
            # Rotate around the rooted sprite foot, not its center. Per-position
            # phase offsets prevent identical neighboring trees moving in sync.
            var half_width := sizes[i].x * 0.5
            var pivot := positions[i] + Vector2(half_width, sizes[i].y)
            var phase := float(posmod(roundi(positions[i].x) * 17 +
                roundi(positions[i].y) * 31, 157)) * 0.12
            var wave := sin(sway_time * (1.35 + 0.23 * sin(phase)) + phase)
            var tilt := (wind_x * 0.017 + wave * 0.032) * wind_strength * sway_factors[i]
            draw_set_transform(pivot, tilt, Vector2.ONE)
            draw_texture_rect_region(atlas.texture(keys[i]),
                Rect2(Vector2(-half_width, -sizes[i].y), sizes[i]),
                atlas.region(keys[i]), tints[i], false, true)
            draw_set_transform(Vector2.ZERO)
        else:
            draw_texture_rect_region(atlas.texture(keys[i]), Rect2(positions[i], sizes[i]),
                atlas.region(keys[i]), tints[i], false, true)
