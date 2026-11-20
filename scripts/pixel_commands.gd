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

func clear_commands() -> void:
    keys.clear()
    positions.clear()
    sizes.clear()
    tints.clear()
    walk_phases.clear()

func add(key: String, at_pos: Vector2, draw_size: Vector2 = Vector2.ZERO,
        tint: Color = Color.WHITE, walk_phase: float = -1.0) -> void:
    keys.append(key)
    positions.append(at_pos)
    sizes.append(atlas.size_of(key) if draw_size == Vector2.ZERO else draw_size)
    tints.append(tint)
    walk_phases.append(walk_phase)

func _draw() -> void:
    for i in range(keys.size()):
        var texture := atlas.texture(keys[i])
        var source := atlas.region(keys[i])
        var dest := Rect2(positions[i], sizes[i])
        var phase: float = walk_phases[i]
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
