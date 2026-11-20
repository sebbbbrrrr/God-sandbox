extends RefCounted
# Civilisation B1: food quantities arise only from reachable biome ecology or
# physical crop production. Local customs guide choice, never human biology.
const Nav = preload("res://scripts/ai/navigation.gd")
const Calendar = preload("res://scripts/ai/sim_calendar.gd")
const FOOD_TYPES := ["berries", "fish", "grain"]
const MAX_GATHERERS := 8
const MAX_FARMS := 8
const FOOD_INTERVAL := 120
const SEARCH_RADIUS := 14
const CARRY_AMOUNT := 3

var depots: Array[Dictionary] = [
    {"berries": 0, "fish": 0, "grain": 0},
    {"berries": 0, "fish": 0, "grain": 0}]
var pantries: Dictionary = {}  # household ID -> food by type
var customs: Dictionary = {}   # household ID -> chosen practices, never national traits
var techniques: Array[Dictionary] = [{}, {}] # local capability hooks for future teaching
var wild_taken: Dictionary = {} # seasonal biomass usage by terrain cell
var wild_cycle := -1
var farms: Array[Dictionary] = []
var next_farm_id := 1
var jobs: Dictionary = {}      # citizen ID -> physically executed job/cargo
var produced := {"berries": 0, "fish": 0, "grain": 0}
var consumed := {"berries": 0, "fish": 0, "grain": 0}
var lost := {"berries": 0, "fish": 0, "grain": 0}
var planted := {"berries": 0, "fish": 0, "grain": 0}

func empty_food() -> Dictionary:
    return {"berries": 0, "fish": 0, "grain": 0}

func pantry_for(household_id: int) -> Dictionary:
    var key := str(household_id)
    if not pantries.has(key):
        pantries[key] = empty_food()
    return pantries[key]

func on_household_merge(primary_id: int, absorbed_id: int, same_home: bool) -> void:
    # A change of legal membership does not teleport supplies between houses.
    # Co-residents already physically share a single dwelling, so they may
    # consolidate its pantry without changing the food ledger.
    if not same_home:
        return
    var old_key := str(absorbed_id)
    if not pantries.has(old_key):
        return
    var target: Dictionary = pantry_for(primary_id)
    var old: Dictionary = pantries[old_key]
    for kind in FOOD_TYPES:
        target[kind] = int(target[kind]) + int(old.get(kind, 0))
    pantries.erase(old_key)

func total(stores: Dictionary) -> int:
    return int(stores.get("berries", 0)) + int(stores.get("fish", 0)) + int(stores.get("grain", 0))

func set_customs(household_id: int, data: Dictionary) -> bool:
    # Culture/religion modules may explicitly set observed customs in future.
    # No faith, ethnicity or nation is assumed to have a universal diet.
    if household_id <= 0 or not data.get("avoid", []) is Array:
        return false
    var avoid: Array = []
    for item in data["avoid"]:
        if str(item) not in FOOD_TYPES or avoid.has(str(item)):
            return false
        avoid.append(str(item))
    var preferred: String = str(data.get("preferred", ""))
    var fast_day: int = int(data.get("fast_day", 0))
    var observance: int = int(data.get("observance", 0))
    var tradition: String = str(data.get("tradition_id", ""))
    if preferred != "" and preferred not in FOOD_TYPES:
        return false
    if fast_day < 0 or fast_day > Calendar.DAYS_PER_YEAR or observance < 0 or observance > 100 or tradition.length() > 48:
        return false
    customs[str(household_id)] = {"avoid": avoid, "preferred": preferred,
        "fast_day": fast_day, "observance": observance, "tradition_id": tradition}
    return true

func set_technique(nation: int, technique: String, enabled: bool = true) -> bool:
    # An explicit knowledge-adoption interface, NOT an automatic year/era unlock.
    if nation not in [0, 1] or technique not in ["cultivation", "irrigation"]:
        return false
    techniques[nation][technique] = enabled
    return true

func source_kind(world: RefCounted, cell: Vector2i) -> String:
    var terrain: int = world.at(cell.x, cell.y)
    if terrain == world.FOREST:
        return "berries"
    if terrain == world.MEADOW:
        return "grain"
    if terrain != world.BEACH:
        return ""
    for direction in Nav.DIRS:
        var water: Vector2i = cell + direction
        if world.index_of(water.x, water.y) >= 0 and world.at(water.x, water.y) == world.OCEAN:
            return "fish"
    return ""

func seasonal_capacity(world: RefCounted, cell: Vector2i, kind: String) -> int:
    if world.index_of(cell.x, cell.y) < 0 or source_kind(world, cell) != kind:
        return 0
    var season: int = int(world.calendar.date_at(world.tick)["season_index"])
    var colder: bool = cell.y < 16 or cell.y > world.HEIGHT - 17
    if kind == "berries":
        if season == 3 or (colder and season in [0, 2]):
            return 0
        return 7 if season == 1 else 4
    if kind == "fish":
        return 6 if season == 3 else 9
    if season == 3:
        return 0
    return 5 if season in [1, 2] else 3

func resource_left(world: RefCounted, cell: Vector2i) -> int:
    var kind := source_kind(world, cell)
    if kind == "":
        return 0
    var capacity := seasonal_capacity(world, cell, kind)
    return maxi(0, capacity - int(wild_taken.get(str(world.index_of(cell.x, cell.y)), 0)))

func cell_access(world: RefCounted, from: Vector2i, source: Vector2i) -> Vector2i:
    var best := Vector2i(-1, -1)
    var distance := 2147483647
    for cell in [source, source + Vector2i(1, 0), source + Vector2i(0, 1),
            source + Vector2i(-1, 0), source + Vector2i(0, -1)]:
        if not world.is_walkable(cell.x, cell.y) or Nav.danger_near(world, cell):
            continue
        var candidate: int = Nav.manhattan(from, cell)
        if candidate < distance:
            best = cell
            distance = candidate
    return best

func source_for(world: RefCounted, person: Dictionary) -> Dictionary:
    var depot: Vector2i = world.capitals[int(person["nation"])]
    var origin := Vector2i(int(person["x"]), int(person["y"]))
    var chosen: Dictionary = {}
    var best_score := 2147483647
    for dy in range(-SEARCH_RADIUS, SEARCH_RADIUS + 1):
        for dx in range(-SEARCH_RADIUS, SEARCH_RADIUS + 1):
            if absi(dx) + absi(dy) > SEARCH_RADIUS:
                continue
            var source := depot + Vector2i(dx, dy)
            if resource_left(world, source) <= 0:
                continue
            var access := cell_access(world, origin, source)
            if access.x < 0:
                continue
            var score: int = Nav.manhattan(origin, access) + Nav.manhattan(access, depot)
            if score < best_score:
                best_score = score
                chosen = {"source": [source.x, source.y], "target": [access.x, access.y],
                    "type": source_kind(world, source)}
    return chosen

func gatherers(nation: int) -> int:
    var n := 0
    for job in jobs.values():
        if int(job["nation"]) == nation and str(job["kind"]) == "forage":
            n += 1
    return n

func move(world: RefCounted, person: Dictionary, mind: Dictionary, target: Vector2i) -> bool:
    var previous := Vector2i(int(person["x"]), int(person["y"]))
    if previous == target:
        return true
    var next: Vector2i = Nav.next_step(world, person, mind, target)
    if next != previous:
        person["x"] = next.x
        person["y"] = next.y
        world.ai_context.moved(person, previous)
    return next == target

func pick_food(household_id: int, person: Dictionary, stores: Dictionary, day: int) -> String:
    var practice: Dictionary = customs.get(str(household_id), {})
    var observe: int = int(practice.get("observance", 0))
    var avoid: Array = practice.get("avoid", [])
    var age: String = str(person.get("life_stage", "adult"))
    var desperate: bool = int(person.get("hunger", 0)) >= 75
    # Fasting is a voluntary adult observance; children are exempt, and
    # survival overrides a fast when hunger reaches a dangerous threshold.
    if observe >= 50 and int(practice.get("fast_day", 0)) == day and not desperate and age in ["adult", "elder"]:
        return ""
    var preferred: String = str(practice.get("preferred", ""))
    if preferred in FOOD_TYPES and int(stores.get(preferred, 0)) > 0 and (preferred not in avoid or desperate):
        return preferred
    for kind in FOOD_TYPES:
        if int(stores.get(kind, 0)) > 0 and (kind not in avoid or desperate or observe < 50):
            return kind
    return ""

func take_ration(world: RefCounted, person: Dictionary) -> bool:
    var family_id: int = int(person.get("household_id", 0))
    var family: Dictionary = world.households.family_for(family_id)
    if family.is_empty():
        return false
    var date: Dictionary = world.calendar.date_at(world.tick)
    var point := Vector2i(int(person["x"]), int(person["y"]))
    var home: Dictionary = world.households.house_by_id(world, int(family.get("home_id", 0)))
    if not home.is_empty() and Nav.manhattan(point, Vector2i(int(home["x"]), int(home["y"]))) <= 1:
        var pantry: Dictionary = pantry_for(family_id)
        var food: String = pick_food(family_id, person, pantry, int(date["day"]))
        if food != "":
            pantry[food] = int(pantry[food]) - 1
            consumed[food] = int(consumed[food]) + 1
            person["hunger"] = maxi(0, int(person["hunger"]) - 35)
            return true
    var depot: Vector2i = world.capitals[int(person["nation"])]
    if depot.x >= 0 and Nav.manhattan(point, depot) <= 1:
        var stores: Dictionary = depots[int(person["nation"])]
        var picked: String = pick_food(family_id, person, stores, int(date["day"]))
        if picked != "":
            stores[picked] = int(stores[picked]) - 1
            consumed[picked] = int(consumed[picked]) + 1
            person["hunger"] = maxi(0, int(person["hunger"]) - 35)
            return true
    return false

func on_tick(world: RefCounted) -> void:
    var next_cycle: int = world.tick / (Calendar.TICKS_PER_YEAR / 4)
    if wild_cycle != next_cycle:
        wild_cycle = next_cycle
        wild_taken.clear() # seasonal replenishment is biome/season constrained
    for person in world.citizens:
        if int(person["hp"]) <= 0:
            continue
        if int(world.tick) < int(person["next_food_tick"]):
            continue
        person["next_food_tick"] = int(world.tick) + FOOD_INTERVAL
        person["hunger"] = mini(100, int(person["hunger"]) + 24)
        if str(person["life_stage"]) in ["infant", "child", "adolescent"]:
            var guardian: Dictionary = world.ai_context.people.get(int(person.get("guardian_id", 0)), {})
            if not guardian.is_empty() and int(guardian["hp"]) > 0 and Nav.manhattan(
                    Vector2i(int(person["x"]), int(person["y"])),
                    Vector2i(int(guardian["x"]), int(guardian["y"]))) <= 2:
                take_ration(world, person)
        if int(person["hunger"]) >= 75:
            person["hp"] = maxi(0, int(person["hp"]) - 8)
            if int(person["hp"]) <= 0:
                world.lifecycle.record_death(world, person, "starvation")

func on_terrain_changed(world: RefCounted, x: int, y: int) -> void:
    wild_taken.erase(str(world.index_of(x, y)))
    for i in range(farms.size() - 1, -1, -1):
        if int(farms[i]["x"]) == x and int(farms[i]["y"]) == y and world.at(x, y) != world.MEADOW:
            farms.remove_at(i)

func find_plot(world: RefCounted, nation: int) -> Vector2i:
    var center: Vector2i = world.capitals[nation]
    for radius in range(2, 7):
        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                if absi(dx) + absi(dy) != radius:
                    continue
                var cell := center + Vector2i(dx, dy)
                if world.at(cell.x, cell.y) != world.MEADOW or not world.is_walkable(cell.x, cell.y):
                    continue
                var occupied := false
                for farm in farms:
                    if int(farm["x"]) == cell.x and int(farm["y"]) == cell.y:
                        occupied = true
                        break
                if occupied or world.construction.occupied(cell.x, cell.y):
                    continue
                return cell
    return Vector2i(-1, -1)

func water_near(world: RefCounted, cell: Vector2i) -> bool:
    for dy in range(-3, 4):
        for dx in range(-3, 4):
            if absi(dx) + absi(dy) > 3:
                continue
            if world.index_of(cell.x + dx, cell.y + dy) >= 0 and world.at(cell.x + dx, cell.y + dy) in [world.OCEAN, world.BEACH]:
                return true
    return false

func create_farm(world: RefCounted, nation: int) -> bool:
    if nation not in [0, 1] or not bool(techniques[nation].get("cultivation", false)):
        return false
    # Settlement knowledge does not bypass local growing conditions.
    if int(world.calendar.date_at(world.tick)["season_index"]) == 3:
        return false
    if int(depots[nation]["grain"]) < 1:
        return false
    var reused: Dictionary = {}
    for existing in farms:
        if int(existing["nation"]) == nation and bool(existing["harvested"]) and int(existing["fertility"]) > 0:
            reused = existing
            break
    if reused.is_empty() and farms.size() >= MAX_FARMS:
        return false
    var plot := Vector2i(-1, -1)
    if reused.is_empty():
        plot = find_plot(world, nation)
        if plot.x < 0:
            return false
    else:
        plot = Vector2i(int(reused["x"]), int(reused["y"]))
    depots[nation]["grain"] = int(depots[nation]["grain"]) - 1
    planted["grain"] = int(planted["grain"]) + 1
    var coastal: bool = water_near(world, plot)
    var colder: bool = plot.y < 16 or plot.y > world.HEIGHT - 17
    var crop_yield: int = 4 + (1 if coastal else 0) - (2 if colder else 0)
    # Irrigation requires actual nearby water rather than creating it.
    if bool(techniques[nation].get("irrigation", false)) and coastal:
        crop_yield += 2
    crop_yield = maxi(2, crop_yield)
    if reused.is_empty():
        farms.append({"id": next_farm_id, "nation": nation, "x": plot.x, "y": plot.y,
            "sown_tick": world.tick, "ready_tick": world.tick + 240,
            "fertility": 5, "yield": crop_yield, "collected": 0, "harvested": false)
        next_farm_id += 1
    else:
        reused["sown_tick"] = world.tick
        reused["ready_tick"] = world.tick + 240
        reused["yield"] = crop_yield
        reused["collected"] = 0
        reused["harvested"] = false
    return true

func ready_farm(world: RefCounted, nation: int) -> Dictionary:
    var season: int = int(world.calendar.date_at(world.tick)["season_index"])
    if season == 3:
        return {}
    for farm in farms:
        if int(farm["nation"]) == nation and not bool(farm["harvested"]) and int(world.tick) >= int(farm["ready_tick"]):
            return farm
    return {}

func work_step(world: RefCounted, person: Dictionary, mind: Dictionary) -> bool:
    var id := str(person["id"])
    var nation: int = int(person["nation"])
    var home: Vector2i = world.capitals[nation]
    if home.x < 0 or not world.is_walkable(home.x, home.y):
        return false
    if int(person.get("hunger", 0)) >= 24 and not jobs.has(id) and (
            total(depots[nation]) > 0 or total(pantry_for(int(person["household_id"]))) > 0):
        var family: Dictionary = world.households.family_for(int(person["household_id"]))
        var house: Dictionary = world.households.house_by_id(world, int(family.get("home_id", 0)))
        var target := home
        if not house.is_empty() and total(pantry_for(int(person["household_id"]))) > 0:
            target = Vector2i(int(house["x"]), int(house["y"]))
        if move(world, person, mind, target):
            take_ration(world, person)
        return true
    if not jobs.has(id):
        if int(person["id"]) % 4 == 0 and gatherers(nation) < MAX_GATHERERS:
            var farm: Dictionary = ready_farm(world, nation)
            if not farm.is_empty():
                jobs[id] = {"kind": "farm", "nation": nation, "phase": "source",
                    "source": [int(farm["x"]), int(farm["y"])], "farm_id": int(farm["id"]),
                    "type": "grain", "amount": 0}
            else:
                var source := source_for(world, person)
                if source.is_empty():
                    return false
                jobs[id] = {"kind": "forage", "nation": nation, "phase": "source",
                    "source": source["source"], "target": source["target"],
                    "type": source["type"], "amount": 0}
        else:
            var family_id: int = int(person["household_id"])
            var family: Dictionary = world.households.family_for(family_id)
            if family.is_empty() or int(family["home_id"]) <= 0 or total(pantry_for(family_id)) >= 3 or total(depots[nation]) < 2:
                return false
            var house := world.households.house_by_id(world, int(family["home_id"]))
            if house.is_empty():
                return false
            jobs[id] = {"kind": "deliver", "nation": nation, "phase": "depot",
                "family_id": family_id, "target": [int(house["x"]), int(house["y"])],
                "type": "", "amount": 0}
        mind["route"] = []
        mind["next_path_tick"] = int(world.tick)
    var job: Dictionary = jobs[id]
    if str(job["phase"]) == "depot":
        if move(world, person, mind, home):
            if str(job["kind"]) == "deliver" and int(job["amount"]) == 0:
                var food: String = pick_food(int(job["family_id"]), person, depots[nation], int(world.calendar.date_at(world.tick)["day"]))
                if food == "":
                    jobs.erase(id)
                    return true
                var number: int = mini(2, int(depots[nation][food]))
                depots[nation][food] = int(depots[nation][food]) - number
                job["type"] = food
                job["amount"] = number
                job["phase"] = "home"
                mind["route"] = []
            else:
                var carried_type: String = str(job["type"])
                depots[nation][carried_type] = int(depots[nation][carried_type]) + int(job["amount"])
                jobs.erase(id)
                mind["route"] = []
        return true
    if str(job["phase"]) == "home":
        var family: Dictionary = world.households.family_for(int(job["family_id"]))
        var dwelling := world.households.house_by_id(world, int(family.get("home_id", 0)))
        if dwelling.is_empty():
            # Lost home: physically return rations to central depot.
            job["phase"] = "depot"
            mind["route"] = []
            return true
        var target := Vector2i(int(dwelling["x"]), int(dwelling["y"]))
        if move(world, person, mind, target):
            var food: String = str(job["type"])
            pantry_for(int(family["id"]))[food] += int(job["amount"])
            jobs.erase(id)
            mind["route"] = []
        return true
    var source := Vector2i(int(job["source"][0]), int(job["source"][1]))
    var target := source
    if str(job["kind"]) == "forage":
        target = Vector2i(int(job["target"][0]), int(job["target"][1]))
        if source_kind(world, source) != str(job["type"]) or resource_left(world, source) <= 0:
            jobs.erase(id)
            return false
    if not world.is_walkable(target.x, target.y) or Nav.danger_near(world, target):
        jobs.erase(id)
        return false
    if not move(world, person, mind, target):
        return true
    var amount := 0
    if str(job["kind"]) == "farm":
        for farm in farms:
            if int(farm["id"]) == int(job["farm_id"]) and not bool(farm["harvested"]) and int(world.tick) >= int(farm["ready_tick"]):
                var available: int = maxi(0, int(farm["yield"]) - int(farm.get("collected", 0)))
                amount = mini(CARRY_AMOUNT, available)
                farm["collected"] = int(farm.get("collected", 0)) + amount
                if int(farm["collected"]) >= int(farm["yield"]):
                    farm["harvested"] = true
                    farm["fertility"] = maxi(0, int(farm["fertility"]) - 1)
                break
    else:
        amount = mini(CARRY_AMOUNT, resource_left(world, source))
        if amount > 0:
            var key := str(world.index_of(source.x, source.y))
            wild_taken[key] = int(wild_taken.get(key, 0)) + amount
    if amount <= 0:
        jobs.erase(id)
        return true
    job["amount"] = amount
    job["phase"] = "depot"
    produced[str(job["type"])] += amount
    mind["route"] = []
    return true

func on_tick_households(world: RefCounted) -> void:
    if world.tick % 60 != 0:
        return
    # Recover a little fallow soil capacity once per game year; no crop
    # outputs are created until a new seed and harvesting work are supplied.
    if world.tick % Calendar.TICKS_PER_YEAR == 0:
        for farm in farms:
            if bool(farm["harvested"]):
                farm["fertility"] = mini(5, int(farm["fertility"]) + 1)
    for nation in range(2):
        if bool(techniques[nation].get("cultivation", false)):
            var count := 0
            for farm in farms:
                if int(farm["nation"]) == nation and not bool(farm["harvested"]):
                    count += 1
            if count < 2:
                create_farm(world, nation)
    for id in jobs.keys():
        var person: Dictionary = world.ai_context.people.get(int(id), {})
        if not person.is_empty() and int(person["hp"]) > 0:
            continue
        var job: Dictionary = jobs[id]
        var amount: int = int(job.get("amount", 0))
        if amount > 0:
            lost[str(job["type"])] += amount
        jobs.erase(id)

func snapshot() -> Dictionary:
    return {"version": 1, "depots": depots.duplicate(true), "pantries": pantries.duplicate(true),
        "customs": customs.duplicate(true), "techniques": techniques.duplicate(true),
        "wild_cycle": wild_cycle, "wild_taken": wild_taken.duplicate(true),
        "farms": farms.duplicate(true), "next_farm_id": next_farm_id,
        "jobs": jobs.duplicate(true), "produced": produced.duplicate(true),
        "consumed": consumed.duplicate(true), "lost": lost.duplicate(true),
        "planted": planted.duplicate(true)}

func load_state(raw: Variant) -> bool:
    if raw == null:
        return true
    if not raw is Dictionary or int(raw.get("version", -1)) != 1:
        return false
    var incoming_depots: Variant = raw.get("depots", [])
    if not incoming_depots is Array or incoming_depots.size() != 2:
        return false
    for nation in range(2):
        if not incoming_depots[nation] is Dictionary:
            return false
        for kind in FOOD_TYPES:
            depots[nation][kind] = maxi(0, int(incoming_depots[nation].get(kind, 0)))
    for field in ["pantries", "customs", "wild_taken", "jobs"]:
        if not raw.get(field) is Dictionary:
            return false
    pantries = raw["pantries"].duplicate(true)
    customs = raw["customs"].duplicate(true)
    wild_taken = raw["wild_taken"].duplicate(true)
    jobs = raw["jobs"].duplicate(true)
    wild_cycle = int(raw.get("wild_cycle", -1))
    if not raw.get("techniques") is Array or raw["techniques"].size() != 2:
        return false
    techniques = raw["techniques"].duplicate(true)
    if not raw.get("farms") is Array or raw["farms"].size() > MAX_FARMS:
        return false
    farms.clear()
    for farm in raw["farms"]:
        if not farm is Dictionary:
            return false
        farms.append(farm.duplicate(true))
    next_farm_id = maxi(1, int(raw.get("next_farm_id", 1)))
    for field in ["produced", "consumed", "lost", "planted"]:
        if not raw.get(field) is Dictionary:
            return false
        var dest: Dictionary = produced
        match field:
            "consumed":
                dest = consumed
            "lost":
                dest = lost
            "planted":
                dest = planted
        for kind in FOOD_TYPES:
            dest[kind] = maxi(0, int(raw[field].get(kind, 0)))
    return true

func ledger_ok() -> bool:
    # Ecological harvest or crop output is the only source of edible units.
    for kind in FOOD_TYPES:
        var held := 0
        for store in depots:
            held += int(store[kind])
        for store in pantries.values():
            held += int(store.get(kind, 0))
        for job in jobs.values():
            if str(job.get("type", "")) == kind:
                held += int(job.get("amount", 0))
        if int(produced[kind]) != held + int(consumed[kind]) + int(lost[kind]) + int(planted[kind]):
            return false
    return true
