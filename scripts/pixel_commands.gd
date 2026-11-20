extends Node2D
class_name PixelCommands

# One cached CanvasItem per chunk/layer or occupied depth row, never per sprite.
# Godot retains its draw commands until a dirty chunk asks for a redraw.
var atlas: PixelAtlas
var keys: Array[String] = []
var positions := PackedVector2Array()
var sizes := PackedVector2Array()
var tints := PackedColorArray()

func clear_commands() -> void:
    keys.clear()
    positions.clear()
    sizes.clear()
    tints.clear()

func add(key: String, at_pos: Vector2, draw_size: Vector2 = Vector2.ZERO,
        tint: Color = Color.WHITE) -> void:
    keys.append(key)
    positions.append(at_pos)
    sizes.append(atlas.size_of(key) if draw_size == Vector2.ZERO else draw_size)
    tints.append(tint)

func _draw() -> void:
    for i in range(keys.size()):
        draw_texture_rect_region(atlas.texture(keys[i]), Rect2(positions[i], sizes[i]),
            atlas.region(keys[i]), tints[i], false, true)
