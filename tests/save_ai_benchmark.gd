extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")

func _initialize() -> void:
    var fixture := "/tmp/citizen-ai-save-fixture.json"
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--fixture="):
            fixture = arg.get_slice("=", 1)
    var world: RefCounted
    if FileAccess.file_exists(fixture):
        world = Simulation.from_snapshot(JSON.parse_string(FileAccess.get_file_as_string(fixture)))
    else:
        world = Simulation.new(20261120)
        var cells: Array[Vector2i] = []
        for y in range(world.HEIGHT):
            for x in range(world.WIDTH):
                if world.is_walkable(x, y):
                    cells.append(Vector2i(x, y))
        world.citizens.clear()
        world.citizen_ai_by_id.clear()
        world.next_id = 1
        world.capitals = [Vector2i(-1, -1), Vector2i(-1, -1)]
        for i in range(1500):
            var cell: Vector2i = cells[(i * 73) % cells.size()]
            world.add_citizen(cell.x, cell.y, i % 2)
        for i in range(300):
            world.step()
        var file := FileAccess.open(fixture, FileAccess.WRITE)
        file.store_string(JSON.stringify(world.snapshot()))
        file.close()
    if world == null:
        push_error("Fixture failed to load")
        quit(1)
        return
    var results: Array = []
    for i in range(3):
        results.append(measure(world, fixture + ".measurement"))
    print("SAVE_BENCHMARK ", JSON.stringify({"population":world.citizens.size(), "tick":world.tick, "samples":results}))
    quit(0)

func measure(world: RefCounted, path: String) -> Dictionary:
    var started := Time.get_ticks_usec()
    var snapshot: Dictionary = world.snapshot()
    var snapshot_ms := float(Time.get_ticks_usec() - started) / 1000.0
    started = Time.get_ticks_usec()
    var encoded := JSON.stringify(snapshot)
    var encode_ms := float(Time.get_ticks_usec() - started) / 1000.0
    started = Time.get_ticks_usec()
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(encoded)
    file.flush()
    var error := file.get_error()
    file.close()
    var write_ms := float(Time.get_ticks_usec() - started) / 1000.0
    started = Time.get_ticks_usec()
    var decoded: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
    var parse_ms := float(Time.get_ticks_usec() - started) / 1000.0
    started = Time.get_ticks_usec()
    var restored = Simulation.from_snapshot(decoded)
    var restore_ms := float(Time.get_ticks_usec() - started) / 1000.0
    var valid: bool = error == OK and restored != null and restored.snapshot() == snapshot
    if not valid:
        push_error("Save benchmark round trip failed")
    DirAccess.remove_absolute(path)
    var binary := {}
    if world.has_method("prepare_save_bytes"):
        started = Time.get_ticks_usec()
        var buffer: PackedByteArray = world.prepare_save_bytes()
        var prepare_ms := float(Time.get_ticks_usec() - started) / 1000.0
        started = Time.get_ticks_usec()
        var stored: Error = world.SaveStore.replace(path, buffer)
        var binary_write_ms := float(Time.get_ticks_usec() - started) / 1000.0
        started = Time.get_ticks_usec()
        var loaded: RefCounted = world.load_file(path)
        var binary_load_ms := float(Time.get_ticks_usec() - started) / 1000.0
        binary = {"prepare_ms":prepare_ms, "write_flush_replace_ms":binary_write_ms,
            "load_ms":binary_load_ms, "bytes":buffer.size(), "valid":stored == OK and loaded != null and loaded.snapshot() == snapshot}
        DirAccess.remove_absolute(path)
    return {"binary_atomic":binary, "snapshot_ms":snapshot_ms, "encode_ms":encode_ms, "write_flush_ms":write_ms,
        "read_parse_ms":parse_ms, "restore_ms":restore_ms, "bytes":encoded.to_utf8_buffer().size(), "valid":valid}
