extends SceneTree

const World = preload("res://scripts/simulation.gd")
const SaveStore = preload("res://scripts/ai/save_store.gd")

func _initialize() -> void:
    var ok := true
    var a = village()
    var b = village()
    var first: int = int(a.citizens[0]["id"])
    var second: int = int(a.citizens[1]["id"])
    ok = check(int(a.citizens[0]["household_id"]) != int(a.citizens[1]["household_id"]),
        "initial founders have distinct persistent household identities") and ok
    ok = check(a.households.form_household(a, first, second) and
        b.households.form_household(b, first, second),
        "two nearby adults form a shared family") and ok
    ok = check(int(a.citizens[0]["household_id"]) == int(a.citizens[1]["household_id"]),
        "household membership is reflected in both citizen records") and ok
    add_house(a, 300, 6)
    add_house(b, 300, 6)
    a.households.reconcile(a)
    b.households.reconcile(b)
    ok = check(a.households.occupancy(a, 300) == 2 and
        int(a.citizens[0]["home_id"]) == 300,
        "two members occupy real beds in a completed house") and ok
    ok = check(a.register_birth(12, 12, 0, first, second) and
        b.register_birth(12, 12, 0, first, second),
        "newborn joins parents only when their home has free beds") and ok
    var child: Dictionary = a.citizens[-1]
    var child_id: int = int(child["id"])
    ok = check(int(child["household_id"]) == int(a.citizens[0]["household_id"]) and
        int(child["home_id"]) == 300 and int(child["guardian_id"]) == first and
        a.households.occupancy(a, 300) == 3,
        "birth records ancestry, guardianship and an occupied bed") and ok
    ok = check(a.snapshot() == b.snapshot(),
        "same seed and household actions replay deterministically") and ok
    a.tick = 36
    a.ai_context.begin_tick(a)
    var guardian: Dictionary = a.citizens[0]
    var guardian_mind: Dictionary = a.citizen_ai_by_id[str(first)]
    ok = check(a.households.care_step(a, guardian, guardian_mind) and
        int(child["care_visits"]) == 1 and int(child["last_care_tick"]) == 36,
        "guardian performs an actual scheduled childcare visit") and ok
    # Place the infant away from the house; the guardian must fetch and carry
    # it home through the existing movement controller, not teleport it.
    var old_child := Vector2i(int(child["x"]), int(child["y"]))
    child["x"] = 9
    child["y"] = 12
    a.ai_context.moved(child, old_child)
    var ever_carried := false
    for i in range(35):
        a.tick += 1
        a.ai_context.begin_tick(a)
        guardian_mind["next_path_tick"] = a.tick
        a.households.care_step(a, guardian, guardian_mind)
        if int(child["carried_by"]) == first:
            ever_carried = true
    ok = check(ever_carried and int(child["carried_by"]) == 0 and
        int(child["x"]) == 13 and int(child["y"]) == 12,
        "infant is physically carried back to assigned shelter") and ok
    var snapshot: Dictionary = a.snapshot()
    var from_json = World.from_snapshot(snapshot)
    ok = check(from_json != null and from_json.snapshot() == snapshot,
        "household and care state survive JSON save/load") and ok
    var saved: PackedByteArray = a.prepare_save_bytes()
    var decoded: Variant = SaveStore.decode(saved)
    var loaded = World.from_snapshot(decoded) if decoded is Dictionary else null
    ok = check(loaded != null and loaded.households.snapshot() == a.households.snapshot(),
        "household identities and occupancy survive binary save/load") and ok
    if loaded != null:
        for i in range(70):
            a.step()
            loaded.step()
        ok = check(a.snapshot() == loaded.snapshot(),
            "long-running caregiving and construction continue deterministically after load") and ok
    # The eldest household steward dies; the surviving adult inherits the
    # household's stewardship (not an invented private property title).
    a.lifecycle.record_death(a, a.citizens[0], "injury")
    a.households.reconcile(a)
    var family: Dictionary = a.households.family_for(int(child["household_id"]))
    ok = check(int(family["steward_id"]) == second and
        int(child["guardian_id"]) == second,
        "death transfers stewardship and dependent care to a living adult") and ok
    var other_id: int = 0
    ok = check(a.add_citizen(12, 12, 0), "new potential guardian is a living citizen") and ok
    other_id = int(a.citizens[-1]["id"])
    a.households.reconcile(a)
    a.lifecycle.record_death(a, a.citizens[1], "injury")
    a.households.reconcile(a)
    ok = check(int(child["guardian_id"]) == other_id and
        int(child["household_id"]) == int(a.citizens[-1]["household_id"]),
        "orphan receives a real eligible guardian, without changing birth parents") and ok
    ok = check(child["parent_ids"] == [first, second],
        "adoption preserves biological ancestry") and ok
    a.set_terrain_cell(13, 12, World.ASH)
    a.households.reconcile(a)
    ok = check(int(child["home_id"]) == 0 and
        a.households.house_by_id(a, 300).is_empty(),
        "destroyed house clears residence without inventing replacement housing") and ok
    var legacy: Dictionary = b.snapshot()
    legacy.erase("households")
    for person in legacy["citizens"]:
        person.erase("household_id")
        person.erase("home_id")
        person.erase("guardian_id")
        person.erase("carried_by")
        person.erase("last_care_tick")
        person.erase("care_visits")
    var migrated = World.from_snapshot(legacy)
    ok = check(migrated != null and migrated.households.families.size() ==
        migrated.citizens.size(), "older saves migrate to unique founding households") and ok
    var limit = village()
    var left: int = int(limit.citizens[0]["id"])
    var right: int = int(limit.citizens[1]["id"])
    limit.households.form_household(limit, left, right)
    add_house(limit, 301, 2)
    limit.households.reconcile(limit)
    ok = check(not limit.register_birth(12, 12, 0, left, right),
        "a completely full home cannot accommodate a newborn") and ok
    limit.construction.houses[0]["capacity"] = 3
    ok = check(limit.register_birth(12, 12, 0, left, right) and
        not limit.register_birth(12, 12, 0, left, right),
        "an additional bed allows exactly one additional resident") and ok
    if ok:
        print("HOUSEHOLD_CARE_TESTS_PASSED")
    quit(0 if ok else 1)

func village():
    var world = World.new(8133, false)
    for y in range(7, 20):
        for x in range(7, 20):
            world.set_terrain_cell(x, y, World.MEADOW)
    world.capitals[0] = Vector2i(12, 12)
    world.add_citizen(12, 12, 0)
    world.add_citizen(12, 12, 0)
    return world

func add_house(world, id: int, capacity: int) -> void:
    world.set_terrain_cell(13, 12, World.TOWN)
    world.construction.houses.append({"id": id, "nation": 0,
        "x": 13, "y": 12, "capacity": capacity, "built_tick": world.tick})
    world.households.dirty = true

func check(condition: bool, name: String) -> bool:
    if not condition:
        push_error("FAILED: " + name)
        return false
    print("PASS: " + name)
    return true
