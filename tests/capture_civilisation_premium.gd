extends SceneTree
## Actual Godot GL Compatibility screenshots for visual review, not concept art.
class CaptureGame extends "res://scripts/unified_game.gd":
    func load_world() -> SandboxSimulation:
        return Simulation.new(424242)
    func save_world() -> void:
        pass

var game: Node2D
var failed := false

func _initialize() -> void:
    call_deferred("capture")

func settle() -> void:
    # Capture settled real frames, not translucent mid-transition states.
    await create_timer(0.43).timeout
    for i in range(5):
        await process_frame
    await RenderingServer.frame_post_draw

func save(file_name: String) -> void:
    await settle()
    var image := root.get_texture().get_image()
    if image == null or image.is_empty():
        failed = true
        push_error("FAILED: no real Godot frame for " + file_name)
        return
    var path := "res://tests/captures/" + file_name + ".png"
    var err := image.save_png(path)
    if err != OK:
        failed = true
        push_error("FAILED: screenshot save failed " + str(err) + " " + path)
    else:
        print("PREMIUM_REAL_CAPTURE: " + path)

func resize(width: int, height: int) -> void:
    root.size = Vector2i(width, height)
    root.content_scale_size = root.size
    await settle()

func capture() -> void:
    DirAccess.make_dir_recursive_absolute("res://tests/captures")
    await resize(393, 852)
    game = CaptureGame.new()
    root.add_child(game)
    game.paused = true
    # The real backend computes its initial local environment assessment,
    # allowing screenshot review of populated and evidence-based town cards.
    for i in range(2):
        game.world.settlement_planner.update_one(game.world)
    game.civilisation_ui.open_for(0)
    await save("civilisation-premium-overview")
    game.civilisation_ui._switch_tab(1)
    await save("civilisation-premium-economy")
    game.civilisation_ui._switch_tab(2)
    game.civilisation_ui._on_map_toggled(true)
    await save("civilisation-premium-routes")
    game.civilisation_ui._switch_tab(3)
    await save("civilisation-premium-people")
    game.civilisation_ui._switch_tab(4)
    await save("civilisation-premium-history")
    game.civilisation_ui._on_map_toggled(false)
    game.civilisation_ui.close()
    await settle()
    game.hud.open_palette(true)
    await save("civilisation-premium-powers")
    game.hud.open_palette(false)
    await settle()
    game.hud._show_settings(true)
    await save("civilisation-premium-settings")
    game.hud._show_settings(false)
    await resize(850, 480)
    game.civilisation_ui.open_for(0)
    await save("civilisation-premium-landscape")
    game.civilisation_ui.close()
    await resize(320, 568)
    game.civilisation_ui.open_for(0)
    await save("civilisation-premium-compact")
    root.remove_child(game)
    game.free()
    print("CIVILISATION_PREMIUM_VISUALS_%s" % ("FAILED" if failed else "PASSED"))
    quit(1 if failed else 0)
