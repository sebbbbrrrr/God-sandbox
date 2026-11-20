extends SceneTree

const Destruction = preload("res://scripts/destruction/structural_destruction.gd")
const Simulation = preload("res://scripts/simulation.gd")
var failed := false

class FakeLifecycle:
    extends RefCounted
    var damage_calls := 0
    func damage(engine, world, id: int, amount: int, reason: String) -> bool:
        var house: Dictionary = engine.building_by_id(id)
        if house.is_empty():
            return false
        damage_calls += 1
        house["condition"] = maxi(0, int(house["condition"]) - amount)
        if int(house["condition"]) == 0:
            engine.destruction.record_removal(house, "collapse", int(world.tick))
            engine.houses.erase(house)
            engine.buildings_by_id.erase(id)
        return true

class FakePlacement:
    extends RefCounted
    var tiles := {}

class FakeEngine:
    extends RefCounted
    var lifecycle := FakeLifecycle.new()
    var placement := FakePlacement.new()
    var houses: Array[Dictionary] = []
    var buildings_by_id := {}
    var destruction = Destruction.new()
    func building_by_id(id: int) -> Dictionary:
        return buildings_by_id.get(id, {})
    func add_building(id: int, x: int, y: int, materials: Dictionary) -> void:
        var row := {"id": id, "x": x, "y": y, "condition": 60,
            "max_health": 60, "materials": materials, "original_age": 1,
            "definition_id": "primitive_shelter"}
        houses.append(row)
        buildings_by_id[id] = row
        placement.tiles[Vector2i(x, y)] = id

class FakeWorld:
    extends RefCounted
    var tick := 0

func _initialize() -> void:
    var engine = FakeEngine.new()
    var world = FakeWorld.new()
    engine.add_building(11, 5, 6, {"wood": 4})
    engine.add_building(12, 6, 6, {"wood": 4})
    engine.add_building(13, 40, 40, {"stone": 6})
    _check(Destruction.resistance({"stone": 6}) > Destruction.resistance({"wood": 6}),
        "stone has higher fire resistance than timber")
    _check(Destruction.hazard_damage(engine.building_by_id(13), "flood", 3) > 0,
        "flood impact only through explicit hazard action")
    _check(engine.destruction.ignite_at(engine, world, Vector2i(5, 6), 3),
        "ignite a real occupied building")
    _check(not engine.destruction.ignite_at(engine, world, Vector2i(0, 0), 3),
        "empty terrain cannot invent a house fire")
    _check(engine.building_by_id(11)["condition"] == 60,
        "ignition does not instantly erase a building")
    for i in range(12):
        world.tick += 1
        engine.destruction.on_tick(engine, world)
    _check(engine.building_by_id(11)["condition"] < 60,
        "authoritative fire advances structural damage")
    _check(engine.lifecycle.damage_calls > 0, "existing lifecycle receives damage")
    var saved: Dictionary = engine.destruction.snapshot()
    var restored = Destruction.new()
    _check(restored.load_state(saved, engine), "active fire survives save roundtrip")
    _check(restored.fires.has(11), "fire identity preserved")
    var broken = saved.duplicate(true)
    broken["fires"][999] = {"started": 0, "last_damage_tick": 0, "intensity": 4}
    _check(not Destruction.new().load_state(broken, engine),
        "dangling building reference rejected")
    for i in range(120):
        world.tick += 1
        engine.destruction.on_tick(engine, world)
    _check(engine.building_by_id(11).is_empty(), "fire eventually collapses weak wood structure")
    _check(engine.destruction.rubble.size() > 0, "collapse leaves bounded rubble")
    _check(engine.destruction.rubble[0]["building_id"] == 11,
        "rubble retains original building provenance")
    _check(engine.destruction.rubble[0]["materials"]["wood"] == 4,
        "debris metadata does not mint inventory or remove material identity")
    var rubble_save := engine.destruction.snapshot()
    _check(Destruction.new().load_state(rubble_save, engine), "rubble is persistent")
    if failed:
        push_error("STRUCTURAL_DESTRUCTION_TESTS_FAILED")
    else:
        print("STRUCTURAL_DESTRUCTION_TESTS_PASSED")
    quit(1 if failed else 0)

func _check(ok: bool, label: String) -> void:
    if ok:
        print("PASS: " + label)
    else:
        failed = true
        push_error("FAILED: " + label)
