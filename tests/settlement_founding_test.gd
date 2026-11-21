extends SceneTree
const World = preload("res://scripts/simulation.gd")
const Nav = preload("res://scripts/ai/navigation.gd")
const SaveStore = preload("res://scripts/ai/save_store.gd")
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
    checks += 1
    if value:
        print("PASS: " + label)
    else:
        failures += 1
        push_error("FAILED: " + label)

func fixture():
    var world = World.new(811, false)
    for y in range(18, 84):
        for x in range(8, 80):
            world.set_terrain_cell(x, y, World.MEADOW)
    for y in range(22, 80, 8):
        for x in range(12, 76, 8):
            world.set_terrain_cell(x, y, World.FOREST)
            world.set_terrain_cell(x + 2, y, World.MOUNTAIN)
    world.capitals[0] = Vector2i(40, 50)
    for i in range(12):
        world.add_citizen(40, 50, 0)
    world.ai_context.begin_tick(world)
    world.settlements.rebuild_membership(world)
    return world

func _initialize() -> void:
    var world = fixture()
    check(world.settlements.records.size() == 2, "legacy capitals acquire stable identities")
    check(world.settlements.population(0) == 12, "resident lookup matches living population")
    check(world.founding.pressure(world, 0) >= 48, "housing and ecological pressure trigger evaluation")
    check(not world.settlement_planner.suitable(world, Vector2i(0, 0)), "ocean and invalid terrain are rejected")
    check(not world.settlement_planner.suitable(world, world.capitals[0]), "existing settlement spacing is enforced")
    var party: Dictionary = world.founding.try_start(world, 0)
    check(not party.is_empty(), "eligible households choose a reachable practical founding site")
    if party.is_empty():
        quit(1)
        return
    var target := Vector2i(int(party["target"][0]), int(party["target"][1]))
    check(Nav.manhattan(target, world.capitals[0]) >= 16, "new settlement has useful geographic separation")
    check(world.settlement_planner.last_candidates <= 24 and world.settlement_planner.last_nodes <= 1024,
        "founding search respects hard candidate and flood budgets")
    check(world.settlements.records.size() == 2 and world.construction.houses.is_empty(),
        "deciding to found creates neither a permanent identity nor a completed building")
    check(world.founding.try_start(world, 0).is_empty(), "origin cooldown prevents duplicate parties")
    var actor: Dictionary = world.ai_context.people[int(party["founder_id"])]
    var origin := Vector2i(int(actor["x"]), int(actor["y"]))
    var count: int = world.citizens.size()
    world.step()
    var after := Vector2i(int(actor["x"]), int(actor["y"]))
    check(Nav.manhattan(origin, after) <= 1 and after != target, "founding uses physical one-cell AI movement")
    var copy = World.from_snapshot(JSON.parse_string(JSON.stringify(world.snapshot())))
    check(copy != null, "in-flight founding expedition survives JSON save/load")
    if copy != null:
        check(copy.founding.snapshot() == world.founding.snapshot(), "party assignments and cooldowns restore")
        for i in range(50):
            world.step()
            copy.step()
        check(world.snapshot() == copy.snapshot(), "full simulation replay is deterministic during migration")
    var saw_camp := false
    var saw_site := false
    var travelled := false
    var saw_cargo := false
    var saved_camp := false
    for i in range(1000):
        world.step()
        if int(party["settlement_id"]) > 1:
            saw_camp = true
            var sid := int(party["settlement_id"])
            if not saved_camp:
                var camp_copy = World.from_snapshot(SaveStore.decode(world.prepare_save_bytes()))
                check(camp_copy != null, "active camp and incomplete shelter restore from compressed save")
                saved_camp = true
            for site in world.construction.projects:
                saw_site = saw_site or world.settlements.sid(site) == sid
            travelled = world.settlements.sid(actor) == sid and Nav.manhattan(origin,
                Vector2i(int(actor["x"]), int(actor["y"]))) >= 10
        for member in party["members"]:
            saw_cargo = saw_cargo or not world.inventory.citizen_inventory(int(member)).is_empty()
        if str(party["phase"]) in ["complete", "failed"]:
            break
    check(saw_camp and travelled, "survivors arrive before household membership transfers to local camp")
    check(saw_site and saw_cargo, "local shelter uses real construction and carried finite materials")
    check(world.citizens.size() == count, "migration never clones citizens")
    check(str(party["phase"]) == "complete", "food and real shelter establish a permanent settlement")
    var id := int(party["settlement_id"])
    print("FOUNDING FINAL: tick=", world.tick, " party=", party, " houses=", world.construction.houses.size(),
        " food=", world.food.store(id), " construction jobs=", world.construction.jobs)
    check(id > 1 and world.settlements.nation(id) == 0, "independent settlement identity retains political affiliation")
    check(world.inventory.ledger_ok() and world.food.ledger_ok(), "material and edible-unit ledgers conserve all resources")
    check(world.settlements.validate(world), "resident households and building ownership remain consistent")
    if id > 1:
        check(world.settlements.housing(world, id) >= party["members"].size(), "completed shelter belongs to the new settlement")
        var remote: Dictionary = world.citizens[8]
        var holder := "settlement:" + str(id)
        check(not world.inventory.transfer(world, holder, "citizen:" + str(remote["id"]), {"wood": 1}, int(remote["id"])),
            "same-nation citizens cannot withdraw from another settlement remotely")
        check(world.occupations.grant_capability(world, 0, "stone_working", "experiment"), "capital receives evidenced technology")
        check(not world.construction.evaluate_request(world, {"settlement_id": id, "function": "shelter", "definition_id": "timber_hut"}).get("ok", false),
            "satellites cannot borrow unsupported advanced technologies")
        var plan_center: Vector2i = world.settlements.center(world, id)
        check(world.settlement_planner.reserved(world, id, plan_center), "communal centre remains reserved for local access")
        check(not world.construction.occupied(plan_center.x, plan_center.y), "local planning preserves centre instead of building over stores")
        var local_holder: Dictionary = world.inventory._holder(world, holder)
        var remote_holder: Dictionary = world.inventory._holder(world, "citizen:" + str(remote["id"]))
        check(not world.inventory._access(local_holder, remote_holder, true), "local ownership denies same-nation neighbours even at the depot")
    var restored = World.from_snapshot(JSON.parse_string(JSON.stringify(world.snapshot())))
    check(restored != null, "completed multi-settlement world restores from JSON")
    if restored != null:
        for i in range(45):
            world.step()
            restored.step()
        check(restored.snapshot() == world.snapshot(), "local construction and food replay deterministically after restore")
        check(restored.inventory.ledger_ok() and restored.food.ledger_ok(), "restore retains both resource conservation ledgers")
    var binary = World.from_snapshot(SaveStore.decode(world.prepare_save_bytes()))
    check(binary != null and binary.snapshot() == world.snapshot(), "compressed saves retain the full multi-settlement registry and plans")
    # Pre-F snapshot has the original holders and opening credits exactly once.
    var legacy = fixture()
    var old: Dictionary = legacy.snapshot()
    old.erase("settlements")
    old.erase("founding")
    for person in old["citizens"]:
        person.erase("settlement_id")
    var migrated = World.from_snapshot(old)
    check(migrated != null and migrated.inventory.snapshot() == legacy.inventory.snapshot(),
        "legacy migration reuses capital inventory without moving or duplicating units")
    # A hazardous destination fails and survivors use normal return movement.
    var damaged = fixture()
    var doomed: Dictionary = damaged.founding.try_start(damaged, 0)
    if not doomed.is_empty():
        damaged.set_terrain_cell(int(doomed["target"][0]), int(doomed["target"][1]), World.OCEAN)
        damaged.founding.tick(damaged)
        check(str(doomed["phase"]) == "return" and damaged.settlements.records.size() == 2,
            "terrain loss cancels travel without phantom camp or material refund")
        check(damaged.inventory.ledger_ok(), "failed founding preserves custody ledger")
    var invalid: Dictionary = world.snapshot()
    invalid["citizens"][0]["settlement_id"] = 99999
    check(World.from_snapshot(invalid) == null, "corrupt settlement membership fails closed")
    var autonomous = fixture()
    for i in range(10):
        autonomous.step()
    check(autonomous.founding.expeditions.size() > 0, "world.step starts founding autonomously without a command")
    var household = fixture()
    # Force one stable existing family into the eligible cohort; children use
    # ordinary dependent following and never become construction workers.
    var parent: Dictionary = household.citizens[0]
    var child: Dictionary = household.citizens[1]
    check(household.households.form_household(household, int(parent["id"]), int(child["id"])), "test family forms using real household API")
    child["birth_tick"] = -6 * household.calendar.TICKS_PER_YEAR
    child["life_stage"] = "child"
    child["guardian_id"] = int(parent["id"])
    for candidate in household.citizens:
        var traits: Dictionary = household.citizen_ai_by_id[str(candidate["id"])]["personality"]
        traits["curiosity"] = 0
        traits["diligence"] = 0
        traits["caution"] = 100
    var parent_traits: Dictionary = household.citizen_ai_by_id[str(parent["id"])]["personality"]
    parent_traits["curiosity"] = 100
    parent_traits["diligence"] = 100
    parent_traits["caution"] = 0
    household.settlements.rebuild_membership(household)
    var family_party: Dictionary = household.founding.try_start(household, 0)
    check(not family_party.is_empty() and int(child["id"]) in family_party.get("members", []), "founding selects a whole household including dependent")
    var child_origin := Vector2i(int(child["x"]), int(child["y"]))
    for i in range(180):
        household.step()
        if household.settlements.sid(child) > 1:
            break
    check(household.settlements.sid(child) == household.settlements.sid(parent) and household.settlements.sid(child) > 1,
        "household guardian and dependent migrate together")
    check(Nav.manhattan(child_origin, Vector2i(int(child["x"]), int(child["y"]))) > 8 and not household.construction.jobs.has(str(child["id"])),
        "dependent physically follows guardian and never performs adult work")
    check(household.settlements.validate(household), "household migration retains consistent membership")
    print("SETTLEMENT FOUNDING: ", checks, " checks, ", failures, " failures")
    quit(0 if failures == 0 else 1)
