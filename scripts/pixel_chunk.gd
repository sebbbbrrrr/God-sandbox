extends Node2D
class_name PixelChunk

const Commands = preload("res://scripts/pixel_commands.gd")
var layers: Array[PixelCommands] = []
var rows: Array[PixelCommands] = []
var coord := Vector2i.ZERO
var dirty := true
var built_detail := -1
var build_count := 0
var far_sprite: Sprite2D

func setup(atlas: PixelAtlas, chunk_coord: Vector2i) -> void:
    coord = chunk_coord
    far_sprite=Sprite2D.new()
    far_sprite.centered=false
    far_sprite.position=Vector2(coord)*16*32-Vector2.ONE*96
    far_sprite.scale=Vector2.ONE*4
    far_sprite.visible=false
    add_child(far_sprite)
    # Water, ground, transitions, cliffs, ground details, then depth-sorted props.
    for i in range(5):
        var layer := Commands.new()
        layer.atlas = atlas
        layer.z_index = i
        layers.append(layer)
        add_child(layer)
    for i in range(16):
        var row := Commands.new()
        row.atlas = atlas
        row.z_index = 100 + (coord.y * 16 + i) * 2
        rows.append(row)
        add_child(row)

func clear_commands() -> void:
    for layer in layers:
        layer.clear_commands()
    for row in rows:
        row.clear_commands()

func finish(detail: int) -> void:
    built_detail = detail
    dirty = false
    build_count += 1
    for layer in layers:
        layer.visible=detail!=0
        layer.queue_redraw()
    for row in rows:
        row.visible=detail!=0
        row.queue_redraw()
    far_sprite.visible=detail==0
