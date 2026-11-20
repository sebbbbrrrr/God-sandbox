extends SceneTree
const Files = preload("res://scripts/ui/world_files.gd")
const Simulation = preload("res://scripts/simulation.gd")
const Fixture = preload("res://tests/ui_inventory_fixture.gd")
class TestGame extends "res://scripts/unified_game.gd":
    func load_world() -> SandboxSimulation:
        return preload("res://tests/ui_inventory_fixture.gd").make_world()
var ok := true
func check(condition: bool, text: String) -> void:
    if not condition:
        ok = false
        push_error("FAILED: " + text)
func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    var path := "user://premium-ui-test-world.json"
    var world := Simulation.new(44812)
    var snapshot := world.snapshot()
    check(Files.write_world(world,path) == OK, "atomic save reports success")
    var data := Files.read_snapshot(path)
    var restored = Simulation.from_snapshot(data)
    check(restored != null and restored.snapshot() == snapshot, "save adapter preserves complete physical world")
    check(not FileAccess.file_exists(path + ".tmp"), "atomic save leaves no partial file")
    world.step()
    check(Files.write_world(world,path) == OK, "existing save replaced atomically")
    restored = Simulation.from_snapshot(Files.read_snapshot(path))
    check(restored != null and restored.snapshot() == world.snapshot(), "reloaded file has latest actual state")
    check(Files.write_world(world,"user://missing-premium-folder/world.json") != OK, "write failure is reported to frontend")
    var file := FileAccess.open(path,FileAccess.WRITE)
    file.store_string("{broken json")
    file.close()
    check(Files.read_snapshot(path).is_empty(), "corrupt save rejected before runtime replacement")
    DirAccess.remove_absolute(path)
    check(Files.read_snapshot(path).is_empty(), "missing save fails without fabricating a world")
    var physical = Fixture.make_world()
    for tick in range(40):
        physical.step()
    check(Files.write_world(physical,path) == OK,"physical tools and active work saved")
    restored = Simulation.from_snapshot(Files.read_snapshot(path))
    check(restored != null,"physical inventory and in-flight jobs reload")
    if restored != null:
        for tick in range(60):
            physical.step()
            restored.step()
        check(physical.snapshot() == restored.snapshot(),"JSON continuation remains deterministic with actual physical inventories")
    root.size = Vector2i(400,866)
    root.content_scale_size = root.size
    var game := TestGame.new()
    game.world_file_path = path
    root.add_child(game)
    game.paused = true
    game._manual_save()
    var saved := game.world.snapshot()
    game.world.step()
    game._reload_saved_world()
    check(game.world.snapshot() == saved and game.world_renderer.world == game.world,"reload controller replaces actual renderer and simulation together")
    file = FileAccess.open(path,FileAccess.WRITE)
    file.store_string("{broken json")
    file.close()
    var original: RefCounted = game.world
    game._reload_saved_world()
    check(game.world == original,"failed reload preserves current playable world")
    game.world_file_path = "user://missing-premium-folder/world.json"
    game._manual_save()
    check(game.last_save_error != OK and game.hud.toast_label.text == "Could not save world","save failure never displays a false success message")
    game.world = null # Avoid an exit autosave for this deliberate failure fixture.
    game.free()
    DirAccess.remove_absolute(path)
    print("PREMIUM_SAVE_TESTS_" + ("PASSED" if ok else "FAILED"))
    quit(0 if ok else 1)
