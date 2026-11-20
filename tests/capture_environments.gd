extends SceneTree

class Showcase extends "res://scripts/game.gd":
    func load_world() -> SandboxSimulation:
        return SandboxSimulation.new(424242)
    func save_world() -> void:
        pass

func _initialize() -> void:
    call_deferred("capture")

func capture() -> void:
    DirAccess.make_dir_recursive_absolute("res://tests/captures")
    root.size = Vector2i(960,1280)
    root.content_scale_size = Vector2i(960,1280)
    var game := Showcase.new()
    root.add_child(game)
    game.paused = true
    game.selected_power = -1
    preload("res://tests/environment_fixture.gd").populate(game.world)
    game.world_renderer.paths_dirty = true
    for chunk in game.world_renderer.chunks.values():chunk.dirty = true
    game.world_renderer.refresh_units()
    for view in [["forest",Vector2(35,39),2.5],["coast",Vector2(20,62),2.5],["mountain",Vector2(70,39),2.5],["settlement",Vector2(45,81),2.5]]:
        game.camera_center = view[1]
        game.zoom = view[2]
        for i in range(6):await process_frame
        await RenderingServer.frame_post_draw
        var path := "res://tests/captures/%s.png" % view[0]
        root.get_texture().get_image().save_png(path)
        print("GODOT_CAPTURE ",path)
    game.free()
    game = Showcase.new()
    root.add_child(game)
    game.paused = true
    game.selected_power = -1
    game.camera_center = Vector2(48,64)
    game.zoom = 0.55
    for i in range(8):await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png("res://tests/captures/procedural-world.png")
    game.free()
    quit(0)
