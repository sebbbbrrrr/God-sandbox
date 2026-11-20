extends SceneTree

const World = preload("res://scripts/simulation.gd")
const Calendar = preload("res://scripts/ai/sim_calendar.gd")
const SaveStore = preload("res://scripts/ai/save_store.gd")

func _initialize() -> void:
    var ok := true
    var a = fixture()
    var b = fixture()
    var berry := Vector2i(15, 12)
    var fish := Vector2i(15, 16)
    var grass := Vector2i(12, 16)
    ok = check(a.food.source_kind(a, berry) == "berries" and
        a.food.source_kind(a, fish) == "fish" and
        a.food.source_kind(a, grass) == "grain",
        "food sources arise from local forest, coast and meadow") and ok
    a.tick = 900
    b.tick = 900
    ok = check(a.food.seasonal_capacity(a, berry, "berries") == 7 and
        a.food.seasonal_capacity(a, fish, "fish") == 9,
        "summer supports different regional seasonal yields") and ok
    a.tick = 1900
    ok = check(a.food.seasonal_capacity(a, berry, "berries") == 0 and
        a.food.seasonal_capacity(a, grass, "grain") == 0 and
        a.food.seasonal_capacity(a, fish, "fish") > 0,
        "winter closes certain food sources while fishing remains possible") and ok
    a.tick = 0
    b.tick = 0
    var family: int = int(a.citizens[0]["household_id"])
    var practice := {"avoid": ["fish"], "preferred": "fish", "observance": 100,
        "fast_day": 8, "tradition_id": "locally_chosen_practice"}
    ok = check(a.food.set_customs(family, practice) and b.food.set_customs(family, practice),
        "food practices are configurable independently per household") and ok
    ok = check(not a.food.set_customs(family, {"avoid": ["fictional_food"]}),
        "unknown cultural diet resources are rejected") and ok
    var adult: Dictionary = a.citizens[0]
    adult["hunger"] = 24
    var portions := {"berries": 2, "fish": 2, "grain": 0}
    ok = check(a.food.pick_food(family, adult, portions, 7) == "berries",
        "observance can guide choice away from fish when alternative food exists") and ok
    ok = check(a.food.pick_food(family, adult, portions, 8) == "",
        "optional observed fast affects adult food choice on its configured day") and ok
    adult["hunger"] = 80
    ok = check(a.food.pick_food(family, adult, portions, 8) == "fish",
        "severe survival need overrides fasting and food avoidances") and ok
    adult["hunger"] = 0
    var gatherer: Dictionary = a.citizens[3]
    var corresponding: Dictionary = b.citizens[3]
    var ever_left := false
    for i in range(120):
        a.tick += 1
        b.tick += 1
        a.ai_context.begin_tick(a)
        b.ai_context.begin_tick(b)
        a.food.on_tick_households(a)
        b.food.on_tick_households(b)
        a.food.work_step(a, gatherer, a.citizen_ai_by_id[str(gatherer["id"])])
        b.food.work_step(b, corresponding, b.citizen_ai_by_id[str(corresponding["id"])])
        if int(gatherer["x"]) != 12 or int(gatherer["y"]) != 12:
            ever_left = true
    ok = check(a.food.snapshot() == b.food.snapshot() and a.citizens == b.citizens,
        "food hauling and foraging are deterministic across identical seeds") and ok
    ok = check(a.food.total(a.food.depots[0]) > 0 and a.food.ledger_ok(),
        "workers physically gather food and ledger balances with depot stock") and ok
    ok = check(ever_left, "food harvest travels to geographically separate resource sources") and ok
    ok = check(not bool(a.food.techniques[0].get("cultivation", false)),
        "agriculture does not unlock automatically from elapsed years") and ok
    ok = check(a.food.set_technique(0, "cultivation"), "explicit local adoption enables farming") and ok
    var prior_grain: int = int(a.food.depots[0]["grain"])
    if prior_grain <= 0:
        # The fixture's reachable meadow is a natural food source.
        a.food.depots[0]["grain"] = 1
        a.food.produced["grain"] += 1
    ok = check(a.food.create_farm(a, 0) and a.food.planted["grain"] == 1,
        "farming requires a real grain seed and known local technique") and ok
    ok = check(a.food.ledger_ok(), "planting keeps conservation ledger balanced") and ok
    var farm: Dictionary = a.food.farms[0]
    a.tick = int(farm["ready_tick"])
    a.ai_context.begin_tick(a)
    var farming_worker: Dictionary = a.citizens[3]
    var previous_job: Dictionary = a.food.jobs.get(str(farming_worker["id"]), {})
    if not previous_job.is_empty():
        # Test setup must account for physical cargo when changing a job.
        var cargo: int = int(previous_job.get("amount", 0))
        if cargo > 0:
            a.food.lost[str(previous_job["type"])] += cargo
        a.food.jobs.erase(str(farming_worker["id"]))
    var produced_before: int = int(a.food.produced["grain"])
    var growth := 0
    while growth < 80 and int(a.food.produced["grain"]) == produced_before:
        a.tick += 1
        a.ai_context.begin_tick(a)
        a.food.work_step(a, farming_worker, a.citizen_ai_by_id[str(farming_worker["id"])])
        growth += 1
    ok = check(int(a.food.produced["grain"]) > produced_before and a.food.ledger_ok(),
        "grain is produced by a worker harvesting a mature farm") and ok
    var household_id: int = int(a.citizens[0]["household_id"])
    var stores: Dictionary = a.food.depots[0]
    if a.food.total(stores) == 0:
        stores["grain"] = int(stores["grain"]) + 1
        a.food.produced["grain"] += 1
    var first: Dictionary = a.citizens[0]
    first["hunger"] = 80
    var start := int(first["hunger"])
    first["x"] = 12
    first["y"] = 12
    first["life_stage"] = "adult"
    var fed: bool = a.food.take_ration(a, first)
    ok = check(fed and int(first["hunger"]) < start and a.food.ledger_ok(),
        "a local meal reduces hunger and records actual food consumption") and ok
    var snapshot: Dictionary = a.snapshot()
    var restored = World.from_snapshot(snapshot)
    ok = check(restored != null and restored.snapshot() == snapshot,
        "food, technology adoption, customs, agriculture and jobs survive JSON save") and ok
    var bytes: PackedByteArray = a.prepare_save_bytes()
    var decoded: Variant = SaveStore.decode(bytes)
    var packed = World.from_snapshot(decoded) if decoded is Dictionary else null
    ok = check(packed != null and packed.food.snapshot() == a.food.snapshot(),
        "binary save round-trips food and cultural practices") and ok
    if packed != null:
        for i in range(90):
            a.step()
            packed.step()
        ok = check(a.snapshot() == packed.snapshot(),
            "mid-transport binary save resumes deterministically") and ok
    var legacy: Dictionary = a.snapshot()
    legacy.erase("food")
    for person in legacy["citizens"]:
        person.erase("hunger")
        person.erase("next_food_tick")
    var migrated = World.from_snapshot(legacy)
    ok = check(migrated != null and migrated.food.ledger_ok() and
        int(migrated.citizens[0]["hunger"]) == 0,
        "older saves migrate to a clean nutrition state without fabricated food") and ok
    var famine = fixture()
    var starving: Dictionary = famine.citizens[0]
    for i in range(16):
        famine.tick = int(starving["next_food_tick"])
        famine.ai_context.begin_tick(famine)
        famine.food.on_tick(famine)
    ok = check(int(starving["hp"]) == 0 and starving["death_cause"] == "starvation" and
        famine.lifecycle.events[-1]["kind"] == "died",
        "prolonged actual food shortage can cause a recorded starvation death") and ok
    if ok:
        print("FOOD_SURVIVAL_TESTS_PASSED")
    quit(0 if ok else 1)

func fixture():
    var world = World.new(5112, false)
    for y in range(7, 25):
        for x in range(7, 25):
            world.set_terrain_cell(x, y, World.MEADOW)
    for y in range(10, 15):
        for x in range(10, 15):
            world.set_terrain_cell(x, y, World.TOWN)
    world.set_terrain_cell(15, 12, World.FOREST)
    world.set_terrain_cell(15, 16, World.BEACH)
    world.set_terrain_cell(15, 17, World.OCEAN)
    world.capitals[0] = Vector2i(12, 12)
    for i in range(8):
        world.add_citizen(12, 12, 0)
    return world

func check(condition: bool, title: String) -> bool:
    if not condition:
        push_error("FAILED: " + title)
        return false
    print("PASS: " + title)
    return true
