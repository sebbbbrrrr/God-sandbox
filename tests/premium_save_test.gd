extends SceneTree
const Files = preload("res://scripts/ui/world_files.gd")
const Simulation = preload("res://scripts/simulation.gd")
var ok := true
func check(condition: bool, text: String) -> void:
    if not condition:
        ok = false
        push_error("FAILED: " + text)
func _initialize() -> void:
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
    print("PREMIUM_SAVE_TESTS_" + ("PASSED" if ok else "FAILED"))
    quit(0 if ok else 1)
