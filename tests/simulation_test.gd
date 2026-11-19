extends SceneTree

const Simulation = preload("res://scripts/simulation.gd")
const Brush = preload("res://scripts/terrain_brush.gd")

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
    success = check(Brush.is_terrain_power(0) and Brush.is_terrain_power(2) and
        Brush.is_terrain_power(5) and not Brush.is_terrain_power(4) and
        not Brush.is_terrain_power(-1), "terrain-only continuous paint") and success
    var line := Brush.stroke_cells(Vector2i(2, 3), Vector2i(12, 3), 0)
    success = check(line.size() == 11 and line.has(Vector2i(7, 3)),
        "fast drag fills gaps") and success
    var circle := Brush.stroke_cells(Vector2i(10, 10), Vector2i(10, 10), 2)
    success = check(circle.has(Vector2i(12, 10)) and not circle.has(Vector2i(12, 12)),
        "circular brush footprint") and success
    var painting_world = Simulation.new(987)
    var changes: int = Brush.paint_segment(painting_world, 5, Vector2i(8, 8), Vector2i(28, 8), 2)
    success = check(changes > 0 and painting_world.at(18, 8) == Simulation.OCEAN,
        "ocean drag changes terrain") and success
    success = check(Brush.paint_segment(painting_world, 5,
        Vector2i(8, 8), Vector2i(28, 8), 2) == 0,
        "unchanged cells skipped") and success
    success = check(Brush.paint_segment(painting_world, 1,
        Vector2i(8, 8), Vector2i(28, 8), 4) == 0,
        "non terrain powers cannot stroke") and success
    if success:
        print("SIMULATION_TESTS_PASSED")
    quit(0 if success else 1)

func check(condition: bool, name: String) -> bool:
    if not condition:
        push_error("FAILED: " + name)
        return false
    print("PASS: " + name)
    return true
