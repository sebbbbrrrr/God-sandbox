extends "res://scripts/unified_game.gd"
const Demo = preload("res://scripts/civilisation/settlement_demo_world.gd")

func load_world() -> SandboxSimulation:
    return Demo.create()

func _ready() -> void:
    super._ready()
    camera_center = Vector2(40, 48)

func save_world() -> void:
    pass # repeatable fixture does not overwrite a player's world
