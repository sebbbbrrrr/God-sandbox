extends SceneTree

class CaptureHUD extends "res://scripts/game.gd":
    func load_world() -> SandboxSimulation:
        return SandboxSimulation.new(424242)
    func save_world() -> void:
        pass

func _initialize() -> void:
    call_deferred("capture")

func capture() -> void:
    DirAccess.make_dir_recursive_absolute("res://tests/captures")
    root.size = Vector2i(480, 850)
    root.content_scale_size = root.size
    var game := CaptureHUD.new()
    root.add_child(game)
    game.paused = true
    game.hud.open_palette(true)
    for frame in range(20):
        await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png("res://tests/captures/hud-powers-portrait.png")
    print("HUD_CAPTURE_PORTRAIT")

    game.hud.open_palette(false)
    game.hud.show_citizen(game.world.citizens[0])
    for frame in range(12):
        await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png("res://tests/captures/hud-inspector.png")
    print("HUD_CAPTURE_INSPECTOR")

    game.hud.hide_inspector()
    root.size = Vector2i(850, 480)
    root.content_scale_size = root.size
    game.hud.open_palette(true)
    for frame in range(20):
        await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png("res://tests/captures/hud-powers-landscape.png")
    print("HUD_CAPTURE_LANDSCAPE")
    game.free()
    quit()
