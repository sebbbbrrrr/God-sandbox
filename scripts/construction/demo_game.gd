extends "res://scripts/unified_game.gd"
const Demo = preload("res://scripts/construction/demo_world.gd")
func load_world() -> SandboxSimulation:
    return Demo.create()
func _ready() -> void:
    super._ready()
    camera_center = Vector2(16,16)
# This repeatable scenario does not overwrite the player's normal world save.
func save_world() -> void:
    pass
