extends SceneTree

const Simulation = preload("res://scripts/simulation.gd")

func _initialize() -> void:
    var success := true
    var a = Simulation.new(20261119)
    var b = Simulation.new(20261119)
    success = check(a.terrain == b.terrain, "seeded terrain") and success
    success = check(a.citizens == b.citizens, "seeded agents") and success
    success = check(a.terrain.has(Simulation.OCEAN), "ocean generated") and success
    success = check(a.terrain.has(Simulation.MEADOW), "meadow generated") and success
    for i in range(200):
        a.step()
        b.step()
    success = check(a.citizens == b.citizens and a.terrain == b.terrain,
        "deterministic 200 tick simulation") and success
    success = check(not a.apply_power(0, -1, 500), "out of bounds rejected") and success
    success = check(a.apply_power(0, 3, 3), "raise land") and success
    success = check(a.at(3, 3) == Simulation.MEADOW, "raise land changes tile") and success
    var saved = a.snapshot()
    var restored = Simulation.from_snapshot(saved)
    success = check(restored != null and restored.tick == a.tick and restored.terrain == a.terrain,
        "save / restore") and success
    if success:
        print("SIMULATION_TESTS_PASSED")
    quit(0 if success else 1)

func check(condition: bool, name: String) -> bool:
    if not condition:
        push_error("FAILED: " + name)
        return false
    print("PASS: " + name)
    return true
