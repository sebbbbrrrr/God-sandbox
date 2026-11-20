extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
const AI = preload("res://scripts/ai/citizen_ai.gd")
const Brush = preload("res://scripts/terrain_brush.gd")
var failures := 0
var assertions := 0

func check(ok: bool, label: String) -> void:
    assertions += 1
    if ok:
        print("PASS: ", label)
    else:
        failures += 1
        push_error("FAILED: " + label)

func fixture(count: int) -> RefCounted:
    var world = Simulation.new(20261120, false)
    world.terrain.fill(world.MEADOW)
    for i in range(count):
        world.add_citizen(30 + i % 12, 30 + (i / 12) % 12, i % 2)
    world.ai_context.begin_tick(world)
    return world

func _initialize() -> void:
    var world := fixture(2)
    var mind: Dictionary = world.citizen_ai_by_id["1"]
    var cell := Vector2i(30, 30)
    var base_cost := AI.Nav.hazard_cost(world, mind, cell)
    AI.Memory.remember(mind, "damage", cell, 0, [], 90, -90, 100)
    check(AI.Nav.hazard_cost(world, mind, cell) > base_cost, "risk cache invalidates on new significant memory")
    AI.Memory.advance(mind, 600000)
    check(AI.Nav.hazard_cost(world, mind, cell) == base_cost, "risk cache invalidates when danger memories are forgotten")
    world = fixture(2)
    mind = world.citizen_ai_by_id["1"]
    world.apply_power(1, 30, 30)
    check(AI.Nav.danger_near(world, cell), "packed hazard mask sees power edits immediately")
    world.apply_power(0, 30, 30)
    check(not AI.Nav.danger_near(world, cell), "packed hazard mask clears when fire is replaced")
    world.terrain[world.index_of(30, 30)] = world.ASH
    world.step()
    check(AI.Nav.danger_near(world, cell), "terrain revision detects legacy raw terrain writes")
    world.apply_power(0, 30, 30)
    world.apply_power(2, 30, 30)
    check(world.at(30, 30) == world.FOREST, "forest power retained")
    world.apply_power(1, 30, 30)
    var hp: int = world.citizens[0]["hp"]
    world.apply_power(3, 30, 30)
    check(hp < 100 and world.citizens[0]["hp"] == 100, "damage and blessing powers retained")
    var count: int = world.citizens.size()
    world.apply_power(4, 30, 30)
    check(world.citizens.size() == count + 1, "spawn power retains identity allocation")
    world.apply_power(5, 31, 30)
    check(not world.is_walkable(31, 30), "ocean power retains impassability")
    mind["route"] = [[31, 30]]
    var next := AI.Nav.next_step(world, world.citizens[0], mind, Vector2i(31, 30))
    check(world.is_walkable(next.x, next.y), "route execution rejects newly flooded next tile")
    var compact: Dictionary = world.snapshot()
    var legacy: Dictionary = world.snapshot(true)
    check(compact["version"] == 4 and compact["ai_version"] == 3, "compact versioned save schema is active")
    var restored = Simulation.from_snapshot(JSON.parse_string(JSON.stringify(compact)))
    check(restored != null and restored.snapshot() == compact, "compact schema restores every behavioural field")
    var migrated = Simulation.from_snapshot(JSON.parse_string(JSON.stringify(legacy)))
    check(migrated != null and migrated.snapshot() == compact, "v3 cognition migrates without changing compact behavioural state")
    var broken := compact.duplicate(true)
    broken["citizen_ai_by_id"]["1"] = [1]
    check(Simulation.from_snapshot(broken) == null, "malformed compact rows reject safely")
    broken = compact.duplicate(true)
    broken["citizen_ai_by_id"]["1"][4] = [null]
    check(Simulation.from_snapshot(broken) == null, "malformed compact episodes reject safely")
    var path := "user://phase25-atomic-test.json"
    check(world.save_atomic(path) == OK, "atomic snapshot writes successfully")
    var bytes := FileAccess.get_file_as_bytes(path)
    var corrupt := bytes.duplicate()
    corrupt[12] = corrupt[12] ^ 1
    check(Simulation.SaveStore.decode(corrupt) == null, "binary save checksum detects corruption")
    var owned: PackedByteArray = world.prepare_save_bytes()
    var before_owned: Dictionary = world.snapshot()
    world.apply_power(5, 50, 50)
    check(Simulation.from_snapshot(Simulation.SaveStore.decode(owned)).snapshot() == before_owned, "prepared bytes remain detached from later simulation edits")
    world.apply_power(0, 50, 50)
    check(Simulation.load_file(path).snapshot() == compact, "atomic file restores deterministic state")
    DirAccess.make_dir_absolute(path + ".pending")
    check(world.save_atomic(path) != OK and FileAccess.get_file_as_bytes(path) == bytes, "failed temporary write preserves the previous save")
    DirAccess.remove_absolute(path + ".pending")
    DirAccess.remove_absolute(path)
    var cap := fixture(1500)
    check(not cap.add_citizen(30, 30, 0), "population cap remains 1500")
    cap.ai_context.routine_budget = 12
    for state in cap.citizen_ai_by_id.values():
        state["next_decision"] = 0
    var bounded := true
    var deferred := 0
    for i in range(480):
        cap.step()
        bounded = bounded and int(cap.ai_context.metrics["routine_decisions"]) <= 12
        deferred += int(cap.ai_context.metrics["deferred_decisions"])
    var served := true
    for state in cap.citizen_ai_by_id.values():
        served = served and int(state["last_decision"]) > 0
    check(bounded and deferred > 0, "routine reasoning obeys deterministic count budgets under overload")
    check(served, "earliest deadlines prevent starvation at severe overload")
    var resumed = Simulation.from_snapshot(cap.snapshot())
    for i in range(30):
        cap.step()
        resumed.step()
    check(cap.snapshot() == resumed.snapshot() and resumed.ai_context.routine_budget == 12, "overloaded scheduling and budget configuration survive save/load")
    var emergency := fixture(30)
    emergency.ai_context.routine_budget = 1
    for person in emergency.citizens:
        person["x"] = 30
        person["y"] = 30
    emergency.apply_power(1, 30, 30)
    emergency.step()
    check(emergency.ai_context.metrics["urgent_decisions"] > 1 and emergency.ai_context.metrics["routine_decisions"] <= 1, "urgent hazard reasoning bypasses routine throttling")
    var meaningful := 0
    var bounded_storage := true
    for state in cap.citizen_ai_by_id.values():
        meaningful += 1 if not state["relationships"].is_empty() else 0
        bounded_storage = bounded_storage and state["relationships"].size() <= 12 and state["memories"].size() <= 12 and state["beliefs"].size() <= 16
    check(meaningful > 100, "crowded citizens retain actual social lives under overload")
    check(bounded_storage, "memories, relationships and beliefs remain individually bounded")
    check(cap.ai_context.id_to_index.size() == 1500 and cap.ai_context.update_slots[0].size() == 500, "stable IDs map to canonical packed update slots")
    if failures == 0:
        print("SCALABILITY_TESTS_PASSED assertions=", assertions)
    quit(0 if failures == 0 else 1)
