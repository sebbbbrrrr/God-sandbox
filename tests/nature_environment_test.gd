extends SceneTree

const Simulation = preload("res://scripts/simulation.gd")
const Environment = preload("res://scripts/nature/nature_environment.gd")

func _initialize() -> void:
    var ok := true
    var world = Simulation.new(20261120)
    var a = Environment.new(world.WIDTH, world.HEIGHT, world.seed)
    var b = Environment.new(world.WIDTH, world.HEIGHT, world.seed)
    ok = check(a.generate(world.terrain), "generate environmental fields") and ok
    ok = check(b.generate(world.terrain), "repeat environmental generation") and ok
    ok = check(a.snapshot() == b.snapshot(), "same seed produces identical environmental fields") and ok
    ok = check(a.get_cell(-1, 0).is_empty(), "out-of-bounds read is safe") and ok
    ok = check(a.get_cell(0, 0).has("fertility"), "cell values accessible") and ok
    for i in range(300):
        world.step()
        a.step(world.tick, world.terrain)
        b.step(world.tick, world.terrain)
    ok = check(a.snapshot() == b.snapshot(), "ecology steps remain deterministic") and ok
    var restored = Environment.from_snapshot(a.snapshot())
    ok = check(restored != null and restored.snapshot() == a.snapshot(), "environment save/restore") and ok
    var invalid := a.snapshot()
    invalid["moisture"] = ""
    ok = check(Environment.from_snapshot(invalid) == null, "reject corrupt environment save") and ok
    var new_world = Simulation.new(20261121)
    ok = check(not a.generate(PackedByteArray()), "reject wrong-sized terrain") and ok
    var c = Environment.new(new_world.WIDTH, new_world.HEIGHT, new_world.seed)
    ok = check(c.generate(new_world.terrain), "different world generates") and ok
    if ok:
        print("NATURE_ENVIRONMENT_TESTS_PASSED")
    quit(0 if ok else 1)

func check(condition: bool, name: String) -> bool:
    if not condition:
        push_error("FAILED: " + name)
        return false
    print("PASS: " + name)
    return true
