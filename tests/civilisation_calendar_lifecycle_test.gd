extends SceneTree

const World = preload("res://scripts/simulation.gd")
const Calendar = preload("res://scripts/ai/sim_calendar.gd")
const Lifecycle = preload("res://scripts/ai/citizen_lifecycle.gd")
const SaveStore = preload("res://scripts/ai/save_store.gd")

func _initialize() -> void:
    var ok := true
    var clock := Calendar.new()
    ok = check(clock.date_at(0)["year"] == 1 and clock.date_at(0)["day"] == 1,
        "world starts on year one, day one") and ok
    ok = check(clock.date_at(599)["season"] == "Spring" and
        clock.date_at(600)["season"] == "Summer" and
        clock.date_at(1200)["season"] == "Autumn" and
        clock.date_at(1800)["season"] == "Winter" and
        clock.date_at(2400)["year"] == 2, "seasons and year boundaries") and ok
    ok = check(clock.age_years(-17 * Calendar.TICKS_PER_YEAR, 0) == 17,
        "biological age derives from birth tick") and ok
    var a = village()
    var b = village()
    ok = check(a.snapshot() == b.snapshot(), "identical seeded founder ages") and ok
    var person: Dictionary = a.citizens[0]
    var legacy_counter: int = int(person["age"])
    person["birth_tick"] = -18 * Calendar.TICKS_PER_YEAR + 1
    person["life_stage"] = "adolescent"
    for i in range(4):
        a.step()
    ok = check(person["life_stage"] == "adult" and
        a.calendar.age_years(int(person["birth_tick"]), a.tick) == 18,
        "birthdays change life stages, independently of legacy age") and ok
    ok = check(int(person["age"]) < legacy_counter + 5,
        "old age counter is still an opaque update counter") and ok
    var stage_events := 0
    for event in a.lifecycle.events:
        if event["kind"] == "life_stage_changed":
            stage_events += 1
    ok = check(stage_events == 1, "life-stage transition logged once") and ok
    if stage_events == 1:
        ok = check(int(a.lifecycle.events[0]["tick"]) == 1,
            "birthday event occurs on exact global tick, not AI update tick") and ok
    var pa: int = int(a.citizens[0]["id"])
    var pb: int = int(a.citizens[1]["id"])
    ok = check(not a.register_birth(12, 12, 0, pa, pb),
        "birth requires an existing nearby shelter") and ok
    a.set_terrain_cell(13, 12, World.TOWN)
    a.construction.houses.append({"id": 1, "nation": 0, "x": 13, "y": 12,
        "capacity": 6, "built_tick": a.tick})
    ok = check(a.households.form_household(a, pa, pb),
        "living parents form a persistent household") and ok
    a.households.reconcile(a)
    var family_id: int = int(a.citizens[0]["household_id"])
    a.food.pantry_for(family_id)["grain"] = 3
    a.food.produced["grain"] += 3
    ok = check(a.register_birth(12, 12, 0, pa, pb),
        "registered birth requires eligible living parents and a shelter") and ok
    var baby: Dictionary = a.citizens[-1]
    ok = check(baby["life_stage"] == "infant" and baby["parent_ids"] == [pa, pb] and
        a.lifecycle.events[-1]["kind"] == "born", "parent IDs and birth event persisted") and ok
    var initial_position := Vector2i(int(baby["x"]), int(baby["y"]))
    for i in range(15):
        a.step()
    ok = check(Vector2i(int(baby["x"]), int(baby["y"])) == initial_position and
        not a.construction.jobs.has(str(baby["id"])),
        "infants do not wander independently or work") and ok
    var json_saved = World.from_snapshot(a.snapshot())
    if json_saved != null and json_saved.snapshot() != a.snapshot():
        var expected: Dictionary = a.snapshot()
        var observed: Dictionary = json_saved.snapshot()
        for field in expected:
            if expected[field] != observed.get(field, null):
                print("D2_LIFECYCLE_DIFF_FIELD=", field)
                print("D2_LIFECYCLE_EXPECTED=", str(expected[field]).substr(0, 500))
                print("D2_LIFECYCLE_OBSERVED=", str(observed.get(field, null)).substr(0, 500))
    ok = check(json_saved != null and json_saved.snapshot() == a.snapshot(),
        "JSON snapshot keeps calendar, lifecycles and events") and ok
    var packed: PackedByteArray = a.prepare_save_bytes()
    var decoded: Variant = SaveStore.decode(packed)
    var restored = World.from_snapshot(decoded) if decoded is Dictionary else null
    ok = check(restored != null, "compressed binary world saves load") and ok
    if restored != null:
        ok = check(restored.lifecycle.snapshot() == a.lifecycle.snapshot() and
            restored.construction.snapshot() == a.construction.snapshot() and
            restored.calendar.snapshot() == a.calendar.snapshot(),
            "binary save preserves life records, dates and houses") and ok
        for i in range(65):
            a.step()
            restored.step()
        ok = check(a.snapshot() == restored.snapshot(),
            "binary save deterministic continuation") and ok
    var old_data: Dictionary = b.snapshot()
    old_data.erase("lifecycle")
    old_data.erase("calendar")
    for old_person in old_data["citizens"]:
        old_person.erase("birth_tick")
        old_person.erase("parent_ids")
        old_person.erase("life_stage")
        old_person.erase("death_tick")
        old_person.erase("death_cause")
    old_data["citizens"][0]["age"] = 400000
    var migrated = World.from_snapshot(old_data)
    ok = check(migrated != null and migrated.citizens[0]["life_stage"] == "adult",
        "legacy update counter does not turn into a 400,000-year-old human") and ok
    var elder = village()
    elder.tick = Calendar.TICKS_PER_YEAR - 1
    elder.citizens[0]["birth_tick"] = elder.tick - 120 * Calendar.TICKS_PER_YEAR
    elder.citizens[0]["life_stage"] = "elder"
    elder.step()
    ok = check(elder.citizens[0]["hp"] == 0 and
        elder.citizens[0]["death_cause"] == "old_age" and
        elder.lifecycle.events[-1]["kind"] == "died",
        "bounded natural mortality and real death event") and ok
    if ok:
        print("CIVILISATION_CALENDAR_LIFECYCLE_TESTS_PASSED")
    quit(0 if ok else 1)

func village():
    var world = World.new(123321, false)
    for y in range(8, 19):
        for x in range(8, 19):
            world.set_terrain_cell(x, y, World.MEADOW)
    world.capitals[0] = Vector2i(12, 12)
    world.add_citizen(12, 12, 0)
    world.add_citizen(12, 12, 0)
    return world

func check(condition: bool, description: String) -> bool:
    if not condition:
        push_error("FAILED: " + description)
        return false
    print("PASS: " + description)
    return true
