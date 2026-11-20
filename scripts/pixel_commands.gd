extends Node2D
class_name PixelCommands

# One cached CanvasItem per chunk/layer or occupied depth row, never per sprite.
# Godot retains its draw commands until a dirty chunk asks for a redraw.
var atlas: PixelAtlas
var keys: Array[String] = []
var positions := PackedVector2Array()
var sizes := PackedVector2Array()
var tints := PackedColorArray()
var walk_phases := PackedFloat32Array()
var sway_factors := PackedFloat32Array()
var sway_time := 0.0
var wind_strength := 0.0
var wind_x := 1.0

func clear_commands() -> void:
    keys.clear()
    positions.clear()
    sizes.clear()
    tints.clear()
    walk_phases.clear()
    sway_factors.clear()

func add(key: String, at_pos: Vector2, draw_size: Vector2 = Vector2.ZERO,
        tint: Color = Color.WHITE, walk_phase: float = -1.0, sway: float = 0.0) -> void:
    keys.append(key)
    positions.append(at_pos)
    sizes.append(atlas.size_of(key) if draw_size == Vector2.ZERO else draw_size)
    tints.append(tint)
    walk_phases.append(walk_phase)
    sway_factors.append(sway)

func set_wind(seconds: float, strength: float, horizontal: float) -> void:
    sway_time = seconds
    wind_strength = strength
    wind_x = horizontal
    if not keys.is_empty():
        queue_redraw()

func _draw() -> void:
    for i in range(keys.size()):
        var texture := atlas.texture(keys[i])
        var source := atlas.region(keys[i])
        var dest := Rect2(positions[i], sizes[i])
        var phase: float = walk_phases[i]
        if sway_factors[i] > 0.0 and wind_strength > 0.01:
            # Wind animates rooted foliage only. Do not change citizen gait.
            var half_width := sizes[i].x * 0.5
            var pivot := positions[i] + Vector2(half_width, sizes[i].y)
            var seed_phase := float(posmod(roundi(positions[i].x) * 17 +
                roundi(positions[i].y) * 31, 157)) * 0.12
            var wave := sin(sway_time * (1.35 + 0.23 * sin(seed_phase)) + seed_phase)
            var tilt := (wind_x * 0.017 + wave * 0.032) * wind_strength * sway_factors[i]
            draw_set_transform(pivot, tilt, Vector2.ONE)
            draw_texture_rect_region(texture,
                Rect2(Vector2(-half_width, -sizes[i].y), sizes[i]),
                source, tints[i], false, true)
            draw_set_transform(Vector2.ZERO)
            continue
        if phase < 0.0 or not keys[i].begins_with("citizen_"):
            draw_texture_rect_region(texture, dest, source, tints[i], false, true)
            continue
        # Use the original high-density character pixels: animate the lower
        # four pixel rows as alternating feet rather than adding blurry tweens.
        var legs_source_height := minf(4.0, source.size.y * 0.30)
        var body_source_height := source.size.y - legs_source_height
        var body_height := dest.size.y * body_source_height / source.size.y
        var leg_height := dest.size.y - body_height
        var left_source_width := floorf(source.size.x * 0.5)
        var left_width := dest.size.x * left_source_width / source.size.x
        var swing := sin(phase * TAU * 2.0)
        var lift := maxf(1.0, dest.size.y * 0.09)
        draw_texture_rect_region(texture,
            Rect2(dest.position, Vector2(dest.size.x, body_height)),
            Rect2(source.position, Vector2(source.size.x, body_source_height)),
            tints[i], false, true)
        draw_texture_rect_region(texture,
            Rect2((dest.position + Vector2(-swing * 0.6,
                body_height - maxf(swing, 0.0) * lift)).round(),
                Vector2(left_width, leg_height)),
            Rect2(source.position + Vector2(0.0, body_source_height),
                Vector2(left_source_width, legs_source_height)),
            tints[i], false, true)
        draw_texture_rect_region(texture,
            Rect2((dest.position + Vector2(left_width + swing * 0.6,
                body_height - maxf(-swing, 0.0) * lift)).round(),
                Vector2(dest.size.x - left_width, leg_height)),
            Rect2(source.position + Vector2(left_source_width, body_source_height),
                Vector2(source.size.x - left_source_width, legs_source_height)),
            tints[i], false, true)
