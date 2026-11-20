extends SceneTree
## Screenshots from the actual Godot GL Compatibility scene, never mockups.
class CaptureGame extends "res://scripts/unified_game.gd":
    func load_world() -> SandboxSimulation:
        return Simulation.new(424242)
    func save_world() -> void:
        pass
var game: Node2D
func _initialize() -> void:
    call_deferred("capture")
func settle() -> void:
    for frame in range(8):
        await process_frame
    await create_timer(0.25).timeout
func shot(file: String) -> void:
    await settle()
    await RenderingServer.frame_post_draw
    var img := root.get_texture().get_image()
    if img == null or img.is_empty():
        push_error("FAILED: real renderer returned no screenshot")
        quit(1)
        return
    img.save_png("res://tests/captures/" + file + ".png")
func resize(width: int, height: int) -> void:
    root.size = Vector2i(width, height)
    root.content_scale_size = root.size
    await settle()
func capture() -> void:
    DirAccess.make_dir_recursive_absolute("res://tests/captures")
    await resize(400, 866)
    game = CaptureGame.new()
    root.add_child(game)
    game.paused = true
    game._refresh_hud()
    await shot("premium-portrait-play")
    game.hud._choose_category(0)
    await shot("premium-portrait-terrain")
    game.hud._choose_power(2)
    game.hud._choose_category(1)
    await shot("premium-portrait-nature")
    game.hud._choose_category(4)
    await shot("premium-world-information")
    game.hud._show_settings(true)
    await shot("premium-menu")
    game.hud._show_settings(false)
    game._open_items()
    await shot("premium-inventory")
    game.hud.close_modal()
    game.hud.set_hud_hidden(true)
    await shot("premium-minimal-world")
    game.hud.set_hud_hidden(false)
    await resize(866, 400)
    game.hud._choose_category(0)
    await shot("premium-landscape-terrain")
    game.hud._show_settings(true)
    await shot("premium-landscape-menu")
    game.hud.close_modal()
    await resize(320, 568)
    game.hud.open_palette(true)
    await shot("premium-small-phone")
    game.hud.open_palette(false)
    await resize(400, 866)
    game.hud.safe_override = Rect2(0, 32, 400, 802)
    game.hud._layout()
    game.hud._choose_category(2)
    await shot("premium-safe-area")
    game.free()
    print("PREMIUM_HUD_CAPTURES_PASSED")
    quit()
