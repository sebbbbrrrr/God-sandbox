extends SceneTree

class CaptureGame extends "res://scripts/game.gd":
    func load_world() -> SandboxSimulation:
        var sim := SandboxSimulation.new(424242)
        for i in range(1050): sim.step()
        return sim
    func save_world() -> void:
        pass

func _initialize() -> void:
    call_deferred("capture")

func capture() -> void:
    DirAccess.make_dir_recursive_absolute("res://tests/captures")
    root.size=Vector2i(960,1280)
    root.content_scale_size=Vector2i(960,1280)
    var game := CaptureGame.new()
    root.add_child(game)
    game.paused=true
    game.selected_power=-1
    game.zoom=2.0
    game.camera_center=Vector2(48,64)
    for i in range(8): await process_frame
    await RenderingServer.frame_post_draw
    var image := root.get_texture().get_image()
    var path := "res://tests/captures/world-close.png"
    image.save_png(path)
    print("IN_ENGINE_CAPTURE: "+path)
    game.zoom=1.0
    for i in range(4): await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png("res://tests/captures/world-medium.png")
    game.free()
    quit()
