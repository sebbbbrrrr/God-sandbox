extends RefCounted
# Civilisation B1: food quantities arise only from reachable biome ecology or
# physical crop production. Local customs guide choice, never human biology.
const Nav = preload("res://scripts/ai/navigation.gd")
const Labour = preload("res://scripts/ai/labour_priorities.gd")
const Calendar = preload("res://scripts/ai/sim_calendar.gd")
const FOOD_TYPES := ["berries", "fish", "grain"]
const MAX_GATHERERS := 12
const MAX_TOTAL_GATHERERS := 24
const MAX_JOBS := 48
const MAX_FARMS := 96
const FOOD_INTERVAL := 120
const SEARCH_RADIUS := 14
const CARRY_AMOUNT := 3

var depots: Array[Dictionary] = [
    {"berries": 0, "fish": 0, "grain": 0},
    {"berries": 0, "fish": 0, "grain": 0}]
var local_depots: Dictionary = {}
var travel_cargo: Dictionary = {} # edible units physically carried by emigrants

func store(id: int) -> Dictionary:
    if id in [0, 1]:
        return depots[id]
    if not local_depots.has(str(id)):
        local_depots[str(id)] = empty_food()
    return local_depots[str(id)]

var pantries: Dictionary = {}  # household ID -> food by type
var customs: Dictionary = {}   # household ID -> chosen practices, never national traits
var techniques: Array[Dictionary] = [{}, {}] # local capability hooks for future teaching
var wild_taken: Dictionary = {} # seasonal biomass usage by terrain cell
var wild_cycle := -1
var farms: Array[Dictionary] = []
var next_farm_id := 1
var jobs: Dictionary = {}      # citizen ID -> physically executed job/cargo
var next_job_scan: Dictionary = {}  # staggered, persisted per-worker search budget
var produced := {"berries": 0, "fish": 0, "grain": 0}
var consumed := {"berries": 0, "fish": 0, "grain": 0}
var lost := {"berries": 0, "fish": 0, "grain": 0}
var planted := {"berries": 0, "fish": 0, "grain": 0}
var capacity_cache: Dictionary = {} # derived tick-local ecology map, no quantities owned here
var capacity_tick := -1

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

func reserve_target(world: RefCounted, family: Dictionary) -> int:
    # A local household prepares more stores ahead of and during winter.
    var members: int = world.households.member_count(world, family)
    var season: int = int(world.calendar.date_at(world.tick)["season_index"])
    var seasonal_extra := 4 if season in [2, 3] else 0
    return clampi(members * 3 + seasonal_extra, 4, 24)

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
    var index: int = world.index_of(cell.x, cell.y)
    if index < 0:
        return 0
    if capacity_tick != world.tick:
        capacity_cache.clear()
        capacity_tick = world.tick
    if not capacity_cache.has(index):
        var kind := source_kind(world, cell)
        capacity_cache[index] = seasonal_capacity(world, cell, kind) if kind != "" else 0
    return maxi(0, int(capacity_cache[index]) - int(wild_taken.get(str(index), 0)))

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
    var depot: Vector2i = world.settlements.center(world, world.settlements.sid(person))
    var origin := Vector2i(int(person["x"]), int(person["y"]))
    var chosen: Dictionary = {}
    var best_score := 2147483647
    var preferred: String = str(world.occupations.record_for(person).get("preference", ""))
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
            var claims: int = Labour.claim_count(jobs, [source.x, source.y], ["forage"])
            var score: int = Nav.manhattan(origin, access) + Nav.manhattan(access, depot)
            score += claims * 52 + posmod(source.x * 5 + source.y * 3 + int(person["id"]), 5)
            if (preferred == "fisher" and source_kind(world, source) == "fish") or (
                    preferred == "forager" and source_kind(world, source) != "fish"):
                score -= 4
            if score < best_score:
                best_score = score
                chosen = {"source": [source.x, source.y], "target": [access.x, access.y],
                    "type": source_kind(world, source)}
    return chosen

func gatherers(nation: int) -> int:
    var n := 0
    for job in jobs.values():
        if (nation < 0 or int(job["nation"]) == nation) and str(job["kind"]) in ["forage", "farm"]:
            n += 1
    return n

func move(world: RefCounted, person: Dictionary, mind: Dictionary,
        target: Vector2i, contact_radius: int = 0) -> bool:
    var previous := Vector2i(int(person["x"]), int(person["y"]))
    if Nav.manhattan(previous, target) <= contact_radius:
        return true
    var destination := Nav.hub_access(world, person, target) if contact_radius > 0 else target
    var next: Vector2i = Nav.next_step(world, person, mind, destination)
    if next != previous:
        person["x"] = next.x
        person["y"] = next.y
        world.ai_context.moved(person, previous)
    return Nav.manhattan(next, target) <= contact_radius

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
    var carried: Dictionary = travel_cargo.get(str(person["id"]),{})
    if total(carried)==0 and world.lifecycle.is_dependent(person):
        var guardian: Dictionary = world.ai_context.people.get(int(person.get("guardian_id",0)),{})
        if not guardian.is_empty() and int(guardian["household_id"])==int(person["household_id"]) and Nav.manhattan(Vector2i(int(person["x"]),int(person["y"])),Vector2i(int(guardian["x"]),int(guardian["y"])))<=2:
            carried = travel_cargo.get(str(guardian["id"]),{})
    for kind in FOOD_TYPES:
        if int(carried.get(kind,0))>0:
            carried[kind] -= 1
            consumed[kind] += 1
            person["hunger"] = maxi(0,int(person["hunger"])-35)
            return true
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
    var depot: Vector2i = world.settlements.center(world, world.settlements.sid(person))
    if depot.x >= 0 and Nav.manhattan(point, depot) <= 1:
        var physical_holder := "settlement:"+str(world.settlements.sid(person))
        if world.inventory.available(physical_holder,"grain_ration")>0 and world.inventory.consume(world,physical_holder,{"grain_ration":1},int(person["id"]),"processed_meal"):
            person["hunger"] = maxi(0,int(person["hunger"])-35)
            return true
        var stores: Dictionary = store(world.settlements.sid(person))
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
        var gestation_extra := 6 if world.demography.pregnancies.has(str(person["id"])) else 0
        person["hunger"] = mini(100, int(person["hunger"]) + 24 + gestation_extra)
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
    # A shoreline edit can change fishing access on adjacent beach cells.
    for direction in [Vector2i.ZERO] + Nav.DIRS:
        var cell: Vector2i = Vector2i(x, y) + direction
        capacity_cache.erase(world.index_of(cell.x, cell.y))
    for i in range(farms.size() - 1, -1, -1):
        if int(farms[i]["x"]) == x and int(farms[i]["y"]) == y and world.at(x, y) != world.MEADOW:
            farms.remove_at(i)

func find_plot(world: RefCounted, nation: int) -> Vector2i:
    var center: Vector2i = world.settlements.center(world,nation)
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
                for job in jobs.values():
                    if str(job["kind"]) == "sow" and job.get("source",[]) == [cell.x,cell.y]: occupied = true
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

func has_tech(world: RefCounted, id: int, tech: String) -> bool:
    return bool(techniques[id].get(tech,false)) if id in [0,1] else bool(world.settlements.get_record(id).get("knowledge",{}).get(tech,false))

func create_farm(world: RefCounted, nation: int, actor_id: int = 0) -> bool:
    var experimental: bool = actor_id > 0 and world.occupations.facility_present(world,nation,"farm")
    if not has_tech(world,nation,"cultivation") and not experimental:
        return false
    # Settlement knowledge does not bypass local growing conditions.
    if int(world.calendar.date_at(world.tick)["season_index"]) == 3:
        return false
    var seed_job: Dictionary = jobs.get(str(actor_id),{})
    if actor_id == 0 and int(store(nation)["grain"]) < 1: return false
    if actor_id > 0 and (str(seed_job.get("kind",""))!="sow" or int(seed_job.get("amount",0))!=1): return false
    var reused: Dictionary = {}
    for existing in farms:
        if world.settlements.sid(existing) == nation and bool(existing["harvested"]) and int(existing["fertility"]) > 0:
            reused = existing
            break
    var plot := Vector2i(-1, -1)
    if actor_id > 0:
        reused = {}
        plot = Vector2i(int(seed_job["source"][0]),int(seed_job["source"][1]))
        for old in farms:
            if int(old["x"])==plot.x and int(old["y"])==plot.y:
                if not bool(old["harvested"]) or int(old["fertility"])<=0: return false
                reused = old
                break
        var actor: Dictionary = world.ai_context.people.get(actor_id,{})
        if actor.is_empty() or world.settlements.sid(actor)!=nation or Vector2i(int(actor["x"]),int(actor["y"])) != plot or world.at(plot.x,plot.y)!=world.MEADOW or world.construction.occupied(plot.x,plot.y) or Nav.danger_near(world,plot): return false
    elif reused.is_empty():
        plot = find_plot(world, nation)
        if plot.x < 0:
            return false
    else:
        plot = Vector2i(int(reused["x"]), int(reused["y"]))
    if reused.is_empty() and farms.size()>=MAX_FARMS: return false
    if actor_id == 0: store(nation)["grain"] = int(store(nation)["grain"]) - 1
    else: seed_job["amount"] = 0
    planted["grain"] = int(planted["grain"]) + 1
    var coastal: bool = water_near(world, plot)
    var colder: bool = plot.y < 16 or plot.y > world.HEIGHT - 17
    var crop_yield: int = 4 + (1 if coastal else 0) - (2 if colder else 0)
    # Irrigation requires actual nearby water rather than creating it.
    if has_tech(world,nation,"irrigation") and coastal:
        crop_yield += 2
    if not coastal and world.construction.operations.irrigate_sowing(world,nation,plot): crop_yield += 2
    crop_yield = maxi(2, crop_yield)
    if reused.is_empty():
        farms.append({"id": next_farm_id, "nation": world.settlements.nation(nation), "settlement_id": nation, "x": plot.x, "y": plot.y,
            "sown_tick": world.tick, "ready_tick": world.tick + 240,
            "fertility": 5, "yield": crop_yield, "collected": 0, "harvested": false})
        next_farm_id += 1
    else:
        reused["sown_tick"] = world.tick
        reused["ready_tick"] = world.tick + 240
        reused["yield"] = crop_yield
        reused["collected"] = 0
        reused["harvested"] = false
    if experimental and not has_tech(world,nation,"cultivation"):
        world.occupations.grant_capability(world,nation,"cultivation","experiment")
    return true

func ready_farm(world: RefCounted, nation: int) -> Dictionary:
    var season: int = int(world.calendar.date_at(world.tick)["season_index"])
    if season == 3 or not has_tech(world,nation,"cultivation"):
        return {}
    var chosen: Dictionary = {}
    var fewest: int = 2 # at most two people per ripe field
    for farm in farms:
        if world.settlements.sid(farm) != nation or bool(farm["harvested"]) or int(world.tick) < int(farm["ready_tick"]):
            continue
        var claims: int = Labour.claim_count(jobs, [int(farm["x"]), int(farm["y"])], ["farm"])
        if claims < fewest:
            chosen = farm
            fewest = claims
    return chosen

func work_step(world: RefCounted, person: Dictionary, mind: Dictionary) -> bool:
    var id := str(person["id"])
    var nation: int = world.settlements.sid(person)
    var home: Vector2i = world.settlements.center(world, nation)
    var carried: Dictionary = travel_cargo.get(id,{})
    if not world.founding.assignments.has(id) and not world.regional_economy.trade_jobs.has(id) and Nav.manhattan(Vector2i(int(person["x"]),int(person["y"])),home)<=1 and total(carried)>0:
        for kind in FOOD_TYPES:
            store(nation)[kind] = int(store(nation)[kind])+int(carried.get(kind,0))
        travel_cargo.erase(id)
    if total(carried)>0 and int(person.get("hunger",0))>=24:
        take_ration(world,person)
        return true
    if home.x < 0 or not world.is_walkable(home.x, home.y):
        return false
    if int(person.get("hunger", 0)) >= 24 and not jobs.has(id) and (
            total(store(nation)) > 0 or total(pantry_for(int(person["household_id"]))) > 0):
        var family: Dictionary = world.households.family_for(int(person["household_id"]))
        var house: Dictionary = world.households.house_by_id(world, int(family.get("home_id", 0)))
        var target := home
        if not house.is_empty() and total(pantry_for(int(person["household_id"]))) > 0:
            target = Vector2i(int(house["x"]), int(house["y"]))
        if move(world, person, mind, target, 1):
            take_ration(world, person)
        return true
    if not jobs.has(id) and world.founding.assignments.has(id):
        return false
    if not jobs.has(id) and (world.toolmaking.jobs.has(id) or world.construction.jobs.has(id) or world.regional_economy.trade_jobs.has(id) or world.regional_economy.road_jobs.has(id) or world.local_logistics.jobs.has(id)):
        return false # personal meals above still interrupt work; optional hauling does not
    if not jobs.has(id) and total(store(nation))>=maxi(8,world.settlements.population(nation)) and world.toolmaking.artisan_candidate(world,person):
        return false # keep the existing designated artisan available when survival reserves suffice
    if not jobs.has(id):
        if jobs.size() >= MAX_JOBS:
            return false
        if int(world.tick) < int(next_job_scan.get(id, 0)):
            return false
        next_job_scan[id] = int(world.tick) + 18 + int(person["id"]) % 7
        if _choose_sowing(world,person,mind): return true
        var reserves_low: bool = total(store(nation)) < maxi(8,world.settlements.population(nation)*3)
        var emergency: bool = reserves_low and int(person.get("hunger", 0)) >= 36
        var preferred: String = str(world.occupations.record_for(person).get("preference", ""))
        var vocation: bool = preferred in ["forager", "fisher", "crop_farmer"]
        var ripe: Dictionary = ready_farm(world,nation)
        if (reserves_low or not ripe.is_empty()) and (int(person["id"]) % 4 == 0 or emergency or vocation) and gatherers(nation) < MAX_GATHERERS and gatherers(-1) < MAX_TOTAL_GATHERERS:
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
            if family.is_empty() or int(family["home_id"]) <= 0 or total(pantry_for(family_id)) >= reserve_target(world, family) or total(store(nation)) < 2:
                return false
            var house: Dictionary = world.households.house_by_id(world, int(family["home_id"]))
            if house.is_empty() or not Labour.can_deliver_food(world, nation, family_id):
                return false
            jobs[id] = {"kind": "deliver", "nation": nation, "phase": "depot",
                "family_id": family_id, "target": [int(house["x"]), int(house["y"])],
                "type": "", "amount": 0}
        mind["route"] = []
        mind["next_path_tick"] = int(world.tick)
    var job: Dictionary = jobs[id]
    if str(job["kind"]) == "sow":
        if str(job["phase"]) == "depot":
            if not move(world,person,mind,home,1): return true
            if int(store(nation)["grain"]) < 1:
                jobs.erase(id)
                return false
            store(nation)["grain"] -= 1
            job["amount"] = 1
            job["phase"] = "source"
            mind["route"] = []
        var plot := Vector2i(int(job["source"][0]),int(job["source"][1]))
        if not world.is_walkable(plot.x,plot.y) or world.construction.occupied(plot.x,plot.y) or Nav.danger_near(world,plot):
            job["kind"] = "forage"
            job["phase"] = "depot"
            mind["route"] = []
            return true
        if not move(world,person,mind,plot): return true
        job["work"] = int(job.get("work",0))+1
        if int(job["work"])>=3:
            if not create_farm(world,nation,int(person["id"])):
                job["kind"] = "forage"
                job["phase"] = "depot"
                return true
            world.occupations.on_real_work(world,person,"crop_farmer")
            jobs.erase(id)
        return true
    if str(job["phase"]) == "depot":
        if move(world, person, mind, home, 1):
            if str(job["kind"]) == "farm": world.toolmaking.try_equip(world,person,"grain")
            if str(job["kind"]) == "deliver" and int(job["amount"]) == 0:
                var food: String = pick_food(int(job["family_id"]), person, store(nation), int(world.calendar.date_at(world.tick)["day"]))
                if food == "":
                    jobs.erase(id)
                    return true
                var trained: int = world.occupations.skill_tier(person, "food_courier")
                var number: int = mini(2 + (1 if trained >= 2 else 0), int(store(nation)[food]))
                store(nation)[food] = int(store(nation)[food]) - number
                job["type"] = food
                job["amount"] = number
                job["phase"] = "home"
                mind["route"] = []
            else:
                var carried_type: String = str(job["type"])
                store(nation)[carried_type] = int(store(nation)[carried_type]) + int(job["amount"])
                jobs.erase(id)
                mind["route"] = []
        return true
    if str(job["phase"]) == "home":
        var family: Dictionary = world.households.family_for(int(job["family_id"]))
        var dwelling: Dictionary = world.households.house_by_id(world, int(family.get("home_id", 0)))
        if dwelling.is_empty():
            # Lost home: physically return rations to central depot.
            job["phase"] = "depot"
            mind["route"] = []
            return true
        var target := Vector2i(int(dwelling["x"]), int(dwelling["y"]))
        if move(world, person, mind, target):
            var food: String = str(job["type"])
            pantry_for(int(family["id"]))[food] += int(job["amount"])
            world.occupations.on_real_work(world, person, "food_courier", int(job["amount"]))
            jobs.erase(id)
            mind["route"] = []
        return true
    var source := Vector2i(int(job["source"][0]), int(job["source"][1]))
    var target := source
    if str(job["kind"]) == "farm" and not has_tech(world,nation,"cultivation"):
        jobs.erase(id)
        return false
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
                var farm_tier: int = world.occupations.skill_tier(person, "crop_farmer")
                amount = mini(CARRY_AMOUNT + (1 if farm_tier >= 2 else 0), available)
                farm["collected"] = int(farm.get("collected", 0)) + amount
                if amount>0: world.toolmaking.wear(world,person,"grain")
                if int(farm["collected"]) >= int(farm["yield"]):
                    farm["harvested"] = true
                    farm["fertility"] = maxi(0, int(farm["fertility"]) - 1)
                break
    else:
        var harvest_role: String = "fisher" if str(job["type"]) == "fish" else "forager"
        var skill_tier: int = world.occupations.skill_tier(person, harvest_role)
        amount = mini(CARRY_AMOUNT + (1 if skill_tier >= 2 else 0), resource_left(world, source))
        if amount > 0:
            var key := str(world.index_of(source.x, source.y))
            wild_taken[key] = int(wild_taken.get(key, 0)) + amount
    if amount <= 0:
        jobs.erase(id)
        return true
    job["amount"] = amount
    job["phase"] = "depot"
    produced[str(job["type"])] += amount
    var completed_role: String = "crop_farmer" if str(job["kind"]) == "farm" else (
        "fisher" if str(job["type"]) == "fish" else "forager")
    world.occupations.on_real_work(world, person, completed_role, amount)
    mind["route"] = []
    return true

func on_tick_households(world: RefCounted) -> void:
    if world.tick % 60 != 0:
        return
    if int(world.calendar.date_at(world.tick)["season_index"])==3:
        for farm in farms:
            if not bool(farm["harvested"]) and world.tick>=int(farm["ready_tick"]):
                farm["harvested"] = true
                farm["failure"] = "winter_crop_loss"
                farm["fertility"] = maxi(0,int(farm["fertility"])-1)
                world.settlements.event(world,world.settlements.sid(farm),"crop_failure")
    # Recover a little fallow soil capacity once per game year; no crop
    # outputs are created until a new seed and harvesting work are supplied.
    if world.tick % Calendar.TICKS_PER_YEAR == 0:
        for farm in farms:
            if bool(farm["harvested"]):
                farm["fertility"] = mini(5, int(farm["fertility"]) + 1)
    # A granary protects finite grain reserves; exposed grain incurs a recorded
    # annual 5% loss. Buildings outside local access, ruined or abandoned do not
    # provide protection. The existing food ledger owns every unit.
    if world.tick % Calendar.TICKS_PER_YEAR == 0:
        var protected: Dictionary = {}
        for house in world.construction.houses:
            if str(house.get("function","")) != "granary" or bool(house.get("abandoned",false)) or int(house.get("condition",100))<25: continue
            var sid: int = world.settlements.sid(house)
            var center: Vector2i = world.settlements.center(world,sid)
            if Nav.manhattan(center,Vector2i(int(house["x"]),int(house["y"])))>8: continue
            var row: Dictionary = world.construction.catalogue.definition(str(house["definition_id"]))
            protected[sid] = int(protected.get(sid,0))+int(row.get("food_capacity",0))
        for key in world.settlements.records:
            var sid := int(key)
            var depot: Dictionary = store(sid)
            var exposed := maxi(0,int(depot.get("grain",0))-int(protected.get(sid,0)))
            var loss := (exposed+19)/20
            depot["grain"] = int(depot.get("grain",0))-loss
            lost["grain"] += loss
    for key in travel_cargo.keys():
        var traveller: Dictionary = world.ai_context.people.get(int(key),{})
        if traveller.is_empty() or int(traveller["hp"])<=0:
            for kind in FOOD_TYPES: lost[kind] += int(travel_cargo[key].get(kind,0))
            travel_cargo.erase(key)
    for id in jobs.keys():
        var person: Dictionary = world.ai_context.people.get(int(id), {})
        if not person.is_empty() and int(person["hp"]) > 0:
            continue
        var job: Dictionary = jobs[id]
        var amount: int = int(job.get("amount", 0))
        if amount > 0:
            lost[str(job["type"])] += amount
        jobs.erase(id)
    # Reclaim records after death or historical archiving.
    for key in next_job_scan.keys():
        var candidate: Dictionary = world.ai_context.people.get(int(key), {})
        if candidate.is_empty() or int(candidate["hp"]) <= 0:
            next_job_scan.erase(key)

func snapshot() -> Dictionary:
    return {"version": 1, "depots": depots.duplicate(true), "local_depots": local_depots.duplicate(true), "travel_cargo": travel_cargo.duplicate(true), "pantries": pantries.duplicate(true),
        "customs": customs.duplicate(true), "techniques": techniques.duplicate(true),
        "wild_cycle": wild_cycle, "wild_taken": wild_taken.duplicate(true),
        "farms": farms.duplicate(true), "next_farm_id": next_farm_id,
        "jobs": jobs.duplicate(true), "next_job_scan": next_job_scan.duplicate(true),
        "produced": produced.duplicate(true),
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
    var incoming_local: Variant = raw.get("local_depots", {})
    if not incoming_local is Dictionary or incoming_local.size() > 24:
        return false
    for key in incoming_local:
        if not str(key).is_valid_int() or int(key) < 2 or not incoming_local[key] is Dictionary:
            return false
        for kind in FOOD_TYPES:
            if int(incoming_local[key].get(kind, -1)) < 0:
                return false
    if not raw.get("travel_cargo",{}) is Dictionary: return false
    travel_cargo = raw.get("travel_cargo",{}).duplicate(true)
    for key in travel_cargo:
        if not travel_cargo[key] is Dictionary or total(travel_cargo[key])>3: return false
        for kind in FOOD_TYPES:
            if int(travel_cargo[key].get(kind,0))<0: return false
    local_depots = incoming_local.duplicate(true)
    pantries = raw["pantries"].duplicate(true)
    customs = raw["customs"].duplicate(true)
    wild_taken = raw["wild_taken"].duplicate(true)
    jobs = raw["jobs"].duplicate(true)
    if raw.has("next_job_scan"):
        if not raw["next_job_scan"] is Dictionary:
            return false
        next_job_scan = raw["next_job_scan"].duplicate(true)
    wild_cycle = int(raw.get("wild_cycle", -1))
    if not raw.get("techniques") is Array or raw["techniques"].size() != 2:
        return false
    techniques.assign(raw["techniques"].duplicate(true))
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
        for cargo in travel_cargo.values(): held += int(cargo.get(kind,0))
        for local_store in local_depots.values():
            held += int(local_store.get(kind, 0))
        for store in pantries.values():
            held += int(store.get(kind, 0))
        for job in jobs.values():
            if str(job.get("type", "")) == kind:
                held += int(job.get("amount", 0))
        if int(produced[kind]) != held + int(consumed[kind]) + int(lost[kind]) + int(planted[kind]):
            return false
    return true

func _choose_sowing(world: RefCounted, person: Dictionary, mind: Dictionary) -> bool:
    if jobs.has(str(person["id"])): return false
    if not ready_farm(world,world.settlements.sid(person)).is_empty(): return false
    var id: int = world.settlements.sid(person)
    if int(store(id)["grain"])<1 or int(world.calendar.date_at(world.tick)["season_index"])==3: return false
    if not has_tech(world,id,"cultivation") and (not world.occupations.facility_present(world,id,"farm") or world.occupations.xp_for(person,"forager")<8): return false
    var count := 0
    for farm in farms:
        if world.settlements.sid(farm)==id and not bool(farm["harvested"]): count += 1
    for job in jobs.values():
        if int(job["nation"])==id and str(job["kind"])=="sow": count += 1
    if count>=2: return false
    var plot := Vector2i(-1,-1)
    for farm in farms:
        if world.settlements.sid(farm)==id and bool(farm["harvested"]) and int(farm["fertility"])>0:
            var claimed := false
            for job in jobs.values():
                if str(job["kind"])=="sow" and job["source"]==[int(farm["x"]),int(farm["y"])]: claimed = true
            if not claimed:
                plot = Vector2i(int(farm["x"]),int(farm["y"]))
                break
    if plot.x<0: plot = find_plot(world,id)
    if plot.x<0: return false
    jobs[str(person["id"])] = {"kind":"sow","nation":id,"phase":"depot","source":[plot.x,plot.y],"type":"grain","amount":0,"work":0}
    mind["route"] = []
    mind["next_path_tick"] = world.tick
    return true

func relief_transfer(world: RefCounted, actor_id: int, settlement_id: int, good: String, pickup: bool) -> bool:
    if good not in FOOD_TYPES: return false
    var job: Dictionary = world.regional_economy.trade_jobs.get(str(actor_id),{})
    var actor: Dictionary = world.ai_context.people.get(actor_id,{})
    if actor.is_empty() or int(actor["hp"])<=0 or str(job.get("kind",""))!="relief" or str(job.get("offer",""))!=good: return false
    var origin := int(job.get("settlement_id",-1))
    if world.settlements.sid(actor)!=origin or world.settlements.nation(origin)!=world.settlements.nation(settlement_id): return false
    if settlement_id not in [origin,int(job.get("other",-1))]: return false
    if pickup and (settlement_id!=origin or str(job["phase"])!="pickup"): return false
    if not pickup and str(job["phase"]) not in ["exchange","return"]: return false
    var center: Vector2i = world.settlements.center(world,settlement_id)
    if Nav.manhattan(Vector2i(int(actor["x"]),int(actor["y"])),center)>1: return false
    var cargo: Dictionary = travel_cargo.get(str(actor_id),empty_food())
    var depot: Dictionary = store(settlement_id)
    if pickup:
        if int(depot[good])<1 or total(cargo)>=3: return false
        depot[good] -= 1
        cargo[good] += 1
        travel_cargo[str(actor_id)] = cargo
    else:
        if int(cargo.get(good,0))<1: return false
        cargo[good] -= 1
        depot[good] += 1
    return true
