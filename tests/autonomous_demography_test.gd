extends SceneTree
const World = preload("res://scripts/simulation.gd")
const Calendar = preload("res://scripts/ai/sim_calendar.gd")
const Relations = preload("res://scripts/ai/relationships.gd")
const SaveStore = preload("res://scripts/ai/save_store.gd")

func _initialize() -> void:
    var ok := true
    var a = fixture()
    var b = fixture()
    ok = check(a.snapshot() == b.snapshot(), "founder demographics are seeded") and ok
    ok = check(a.citizens[0]["can_gestate"] != a.citizens[1]["can_gestate"],
        "reproductive capability is stable and independent of nation/religion") and ok
    ok = check(not a.demography.set_household_preferences(1,
        {"desired_children": 99}), "unbounded demographic rules rejected") and ok
    for world in [a, b]:
        world.tick = 180
        add_social_history(world)
        world.demography.find_partner(world)
        world.households.reconcile(world)
    var first := a.citizens[0]
    var second := a.citizens[1]
    var family_id: int = int(first["household_id"])
    ok = check(a.demography.partners[str(first["id"])] == int(second["id"]) and
        int(first["household_id"]) == int(second["household_id"]),
        "mutual observed social bonds lead to autonomous family formation") and ok
    ok = check(a.households.occupancy(a, 11) == 2,
        "partnership preserves actual physical bed occupancy") and ok
    ok = check(a.snapshot() == b.snapshot(), "family selection deterministic for equal observations") and ok
    a.demography.update_security(a)
    b.demography.update_security(b)
    a.demography.try_conception(a)
    b.demography.try_conception(b)
    ok = check(a.demography.pregnancies.size() == 1 and
        a.demography.snapshot() == b.demography.snapshot(),
        "food security and shelter enable one deterministic pregnancy") and ok
    var gestator: Dictionary = first if bool(first["can_gestate"]) else second
    var partner: Dictionary = second if gestator == first else first
    var key := str(gestator["id"])
    var due: int = int(a.demography.pregnancies[key]["due_tick"])
    ok = check(due == 180 + 1800 and a.citizens.size() == 2,
        "conception records a future due tick, not an instant newborn") and ok
    var prior_pantry: int = a.food.total(a.food.pantry_for(family_id))
    var stored: Dictionary = a.snapshot()
    var loaded = World.from_snapshot(stored)
    ok = check(loaded != null and loaded.snapshot() == stored,
        "in-progress pregnancy and partnership save through JSON") and ok
    var data: Variant = SaveStore.decode(a.prepare_save_bytes())
    var binary = World.from_snapshot(data) if data is Dictionary else null
    ok = check(binary != null and binary.demography.snapshot() == a.demography.snapshot(),
        "compressed binary stores exact pregnancy and household policy") and ok
    a.tick = due - 1
    a.ai_context.begin_tick(a)
    ok = check(not a.demography.delivery_step(a, gestator,
        a.citizen_ai_by_id[key]), "birth cannot precede the full gestation interval") and ok
    a.tick = due
    a.ai_context.begin_tick(a)
    ok = check(a.demography.delivery_step(a, gestator, a.citizen_ai_by_id[key]) and
        a.citizens.size() == 3 and a.demography.pregnancies.is_empty(),
        "physical near-home delivery creates exactly one infant") and ok
    var baby: Dictionary = a.citizens[-1]
    ok = check(baby["life_stage"] == "infant" and
        baby["parent_ids"] == [int(gestator["id"]), int(partner["id"])] and
        int(baby["household_id"]) == family_id,
        "newborn has historical parents, a guardian and a real household") and ok
    ok = check(a.households.occupancy(a, 11) == 3 and
        a.food.total(a.food.pantry_for(family_id)) == prior_pantry,
        "delivery uses a vacant physical bed and does not conjure or destroy food") and ok
    a.demography.update_security(a)
    a.demography.try_conception(a)
    ok = check(a.demography.pregnancies.is_empty(),
        "postnatal birth spacing prevents immediate repeat pregnancy") and ok
    ok = check(a.food.ledger_ok(), "family population changes conserve food") and ok
    var declining = fixture()
    declining.tick = 180
    add_social_history(declining)
    declining.demography.find_partner(declining)
    declining.households.reconcile(declining)
    var decline_family: int = int(declining.citizens[0]["household_id"])
    ok = check(declining.demography.set_household_preferences(decline_family,
        {"desired_children": 0, "minimum_spacing_years": 4, "partnership_interest": 60}),
        "household can freely prefer no additional children") and ok
    declining.demography.update_security(declining)
    declining.demography.try_conception(declining)
    ok = check(declining.demography.pregnancies.is_empty(),
        "voluntary household preference prevents unwanted births") and ok
    var starving = fixture()
    starving.tick = 180
    add_social_history(starving)
    starving.demography.find_partner(starving)
    starving.households.reconcile(starving)
    starving.citizens[0]["hunger"] = 90
    starving.demography.update_security(starving)
    starving.demography.try_conception(starving)
    ok = check(starving.demography.pregnancies.is_empty(),
        "severe hunger blocks conception regardless of calendar year") and ok
    var unsafe = fixture()
    unsafe.tick = 180
    add_social_history(unsafe)
    unsafe.demography.find_partner(unsafe)
    unsafe.households.reconcile(unsafe)
    unsafe.food.pantry_for(int(unsafe.citizens[0]["household_id"]))["grain"] = 0
    unsafe.demography.update_security(unsafe)
    unsafe.demography.try_conception(unsafe)
    ok = check(unsafe.demography.pregnancies.is_empty(),
        "inadequate actual food storage prevents population spawning") and ok
    var bereaved = fixture()
    bereaved.tick = 180
    add_social_history(bereaved)
    bereaved.demography.find_partner(bereaved)
    bereaved.households.reconcile(bereaved)
    bereaved.demography.update_security(bereaved)
    bereaved.demography.try_conception(bereaved)
    var mother: Dictionary = bereaved.citizens[0] if bool(bereaved.citizens[0]["can_gestate"]) else bereaved.citizens[1]
    var father: Dictionary = bereaved.citizens[1] if mother == bereaved.citizens[0] else bereaved.citizens[0]
    var birth_due: int = int(bereaved.demography.pregnancies[str(mother["id"])]["due_tick"])
    bereaved.lifecycle.record_death(bereaved, father, "injury")
    bereaved.households.reconcile(bereaved)
    ok = check(bereaved.demography.pregnancies.size() == 1 and
        bereaved.demography.partners.is_empty(),
        "bereavement does not erase an already existing pregnancy") and ok
    bereaved.tick = birth_due
    bereaved.ai_context.begin_tick(bereaved)
    ok = check(bereaved.demography.delivery_step(bereaved, mother,
        bereaved.citizen_ai_by_id[str(mother["id"])]) and
        bereaved.citizens[-1]["parent_ids"].has(int(father["id"])),
        "surviving parent can deliver while preserving deceased parentage") and ok
    var before_archive: int = bereaved.citizens.size()
    bereaved.tick = Calendar.TICKS_PER_YEAR * 4
    bereaved.demography.archive_dead(bereaved)
    ok = check(bereaved.citizens.size() == before_archive - 1 and
        bereaved.demography.tombstones.size() == 1 and
        bereaved.citizens[-1]["parent_ids"].has(int(father["id"])),
        "dead citizens release live simulation slots but leave history and ancestry") and ok
    var legacy: Dictionary = a.snapshot()
    legacy.erase("demography")
    for citizen in legacy["citizens"]:
        citizen.erase("can_gestate")
        citizen.erase("last_birth_tick")
        citizen.erase("last_partner_decision")
    var migrated = World.from_snapshot(legacy)
    ok = check(migrated != null and
        bool(migrated.citizens[0]["can_gestate"]) ==
            migrated.demography.can_gestate_for(migrated.seed, int(migrated.citizens[0]["id"])),
        "legacy demographic migration never rewrites citizen birth dates") and ok
    if ok:
        print("AUTONOMOUS_DEMOGRAPHY_TESTS_PASSED")
    quit(0 if ok else 1)

func fixture():
    var w = World.new(8133, false)
    for y in range(7, 20):
        for x in range(7, 20):
            w.set_terrain_cell(x, y, World.MEADOW)
    w.capitals[0] = Vector2i(12, 12)
    w.add_citizen(12, 12, 0)
    w.add_citizen(12, 12, 0)
    for person in w.citizens:
        person["birth_tick"] = -25 * Calendar.TICKS_PER_YEAR
        person["life_stage"] = "adult"
    w.set_terrain_cell(13, 12, World.TOWN)
    w.construction.houses.append({"id": 11, "nation": 0, "x": 13,
        "y": 12, "capacity": 4, "built_tick": 0})
    w.households.reconcile(w)
    # A seeded, tracked pantry fixture; never invent food without recording it.
    w.food.pantry_for(int(w.citizens[0]["household_id"]))["grain"] = 8
    w.food.produced["grain"] = 8
    w.ai_context.begin_tick(w)
    return w

func add_social_history(world) -> void:
    var a: Dictionary = world.citizens[0]
    var b: Dictionary = world.citizens[1]
    var mind_a: Dictionary = world.citizen_ai_by_id[str(a["id"])]
    var mind_b: Dictionary = world.citizen_ai_by_id[str(b["id"])]
    for i in range(3):
        Relations.encounter(mind_a, int(b["id"]), Vector2i(int(b["x"]), int(b["y"])),
            world.tick, "friendly")
        Relations.encounter(mind_b, int(a["id"]), Vector2i(int(a["x"]), int(a["y"])),
            world.tick, "friendly")

func check(condition: bool, title: String) -> bool:
    if not condition:
        push_error("FAILED: " + title)
        return false
    print("PASS: " + title)
    return true
