extends "res://scripts/construction/material_gathering.gd"
# Existing AI facade; bounded services share D2 custody and C1 skills.
const Catalogue = preload("res://scripts/construction/building_catalogue.gd")
const Site = preload("res://scripts/construction/site_state.gd")
const Placement = preload("res://scripts/construction/placement.gd")
const StrategicPlanner = preload("res://scripts/civilisation/strategic_planner.gd")
const Tasks = preload("res://scripts/construction/construction_tasks.gd")
const Operations = preload("res://scripts/construction/building_operations.gd")
const Lifecycle = preload("res://scripts/construction/building_lifecycle.gd")
const HOUSE_WOOD := 3
const HOUSE_STONE := 1
const HOUSE_WORK := 6
const MAX_SITES := 128
const MAX_JOBS := 64
const SITE_BUDGET := 16
const PLACEMENT_SCORE_BUDGET := 48
var catalogue = Catalogue.new()
var placement = Placement.new()
var tasks = Tasks.new()
var lifecycle = Lifecycle.new()
var operations = Operations.new()
var settlement_context: Dictionary = {}
var archived: Array[Dictionary] = []
var sites_by_id: Dictionary = {}
var buildings_by_id: Dictionary = {}
var local_stockpiles: Dictionary = {} # aliases into existing custody ledger
var plan_cursor := 0
var site_cursor = 0
var revision = 0
var indexed_houses = 0
var building_revision := 0
# Derived tick-local workforce pressure cache (never persisted).
var labour_cache_tick := -1
var labour_pressure_cache: Dictionary = {}

func site_by_id(id: int) -> Dictionary:
    return sites_by_id.get(id, {})

func building_by_id(id: int) -> Dictionary:
    return buildings_by_id.get(id, {})

func project_for(nation: int) -> Dictionary:
    for site in projects:
        if int(site.get("settlement_id", site["nation"])) == nation:
            return site
    return {}

func occupied(x: int, y: int) -> bool:
    return placement.tiles.has(Vector2i(x, y))

func rebuild_indexes() -> void:
    building_revision += 1
    placement.tiles.clear()
    sites_by_id.clear()
    buildings_by_id.clear()
    lifecycle.pending.clear()
    for house in houses:
        buildings_by_id[int(house["id"])] = house
        if house.has("pending_action"):
            lifecycle.pending[int(house["id"])] = true
        placement.claim(catalogue.definition(str(house.get("definition_id", "primitive_shelter"))), house)
    for site in projects:
        sites_by_id[int(site["id"])] = site
        placement.claim(catalogue.definition(str(site["definition_id"])), site)
    indexed_houses = houses.size()

func eligible_workers(world: RefCounted, nation: int, row: Dictionary, requested: Array = []) -> int:
    var count = 0
    for person in world.citizens:
        if world.settlements.sid(person) == nation and (requested.is_empty() or int(person["id"]) in requested) and catalogue.worker_eligible(world, person, row):
            count += 1
    return count

func evaluate_request(world: RefCounted, request: Dictionary) -> Dictionary:
    var nation = int(request.get("settlement_id", -1))
    if nation > 1:
        local_stockpiles[str(nation)] = world.inventory.stockpile(nation)
    if world.settlements.center(world, nation).x < 0 or (nation > 1 and world.settlements.get_record(nation).is_empty()):
        return {"ok": false, "reason": "settlement"}
    var candidates: Array = request.get("candidates", catalogue.candidate_ids(str(request.get("function", "shelter"))))
    if request.has("definition_id"):
        candidates = [request["definition_id"]]
    var failures: Array = []
    for id in candidates:
        var row: Dictionary = catalogue.definition(str(id))
        if str(row.get("function", "")) != str(request.get("function", "shelter")): continue
        if not catalogue.eligible(world,nation,row,settlement_context.get(str(nation),{})):
            var knowledge: Array = catalogue.knowledge_blockers(world,nation,row)
            failures.append({"definition":str(id),"reason":"knowledge" if not knowledge.is_empty() else "region_or_climate","missing":knowledge})
            continue
        if eligible_workers(world,nation,row,request.get("available_workforce",[])) == 0:
            failures.append({"definition":str(id),"reason":"labour_skill_or_tool"})
            continue
        var missing: Dictionary = {}
        var within_limits := true
        for material in row["materials"]:
            if request.get("resource_constraints",{}).has(material) and int(row["materials"][material]) > int(request["resource_constraints"][material]): within_limits = false
            var shortage: int = int(row["materials"][material])-world.inventory.available("settlement:"+str(nation),str(material))
            if shortage>0: missing[material] = shortage
        if not within_limits or (bool(request.get("require_stock",false)) and not missing.is_empty()):
            failures.append({"definition":str(id),"reason":"materials","missing":missing})
            continue
        var supply: Dictionary = resource_plan(world,nation,missing)
        if not bool(row.get("legacy",true)) and not supply["viable"]:
            failures.append({"definition":str(id),"reason":"materials_or_transport","missing":supply["unavailable"]})
            continue
        return {"ok":true,"definition_id":str(id),"materials":row["materials"].duplicate(true),"labour":int(row["labour"]),"missing":missing,"resource_plan":supply}
    return {"ok":false,"reason":str(failures[0]["reason"]) if not failures.is_empty() else "definition_or_function","blocked":failures}

# Bounded finite-source allocation. Shared depletion means wood+fibre cannot
# both spend the same forest units, nor clay+reeds the same shore units.
func resource_plan(world: RefCounted, sid: int, missing: Dictionary) -> Dictionary:
    var left: Dictionary = {}
    var unavailable: Dictionary = {}
    var sources: Dictionary = {}
    var center: Vector2i = world.settlements.center(world,sid)
    var materials: Array = missing.keys()
    materials.sort()
    for material in materials:
        var need := int(missing[material])
        for dy in range(-RESOURCE_RADIUS,RESOURCE_RADIUS+1):
            if need<=0: break
            for dx in range(-RESOURCE_RADIUS,RESOURCE_RADIUS+1):
                if need<=0: break
                if absi(dx)+absi(dy)>RESOURCE_RADIUS: continue
                var point := center+Vector2i(dx,dy)
                var capacity := left_at(world,point.x,point.y,str(material))
                if capacity<=0 or approach(world,center,point).x<0: continue
                var index := str(world.index_of(point.x,point.y))
                if not left.has(index): left[index] = capacity
                var amount := mini(need,int(left[index]))
                if amount<=0: continue
                left[index] = int(left[index])-amount
                need -= amount
                sources[str(material)] = int(sources.get(str(material),0))+amount
        if need>0: unavailable[str(material)] = need
    return {"viable":unavailable.is_empty(),"gatherable":sources,"unavailable":unavailable}

func find_location(world: RefCounted, row: Dictionary, center: Vector2i, orientation: int, nation: int) -> Vector2i:
    var choice := Vector2i(-1, -1)
    var best := -2147483647
    var scored := 0
    var limit := clampi(int(world.settlements.get_record(nation).get("radius",9)),9,16)
    for distance in range(1, limit+1):
        for dy in range(-distance, distance + 1):
            for dx in range(-distance, distance + 1):
                if absi(dx) + absi(dy) != distance:
                    continue
                var cell := center + Vector2i(dx, dy)
                if placement.validate(world, row, cell, orientation) != "":
                    continue
                var score: int = world.settlement_planner.rank(world, row, cell, center, nation)
                if score <= -1000000:
                    continue
                scored += 1
                if score > best and score > -1000000:
                    best = score
                    choice = cell
                if scored >= PLACEMENT_SCORE_BUDGET:
                    return choice
    return choice

func request_construction(world: RefCounted, request: Dictionary) -> Dictionary:
    if projects.size() >= MAX_SITES:
        return {"ok": false, "reason": "site_capacity"}
    var assessment = evaluate_request(world, request)
    if not assessment["ok"]:
        return assessment
    var nation = int(request["settlement_id"])
    var row: Dictionary = catalogue.definition(str(assessment["definition_id"]))
    var orientation = int(request.get("orientation", 0))
    var center: Vector2i = world.settlements.center(world, nation)
    if request.get("preferred_area") is Array and request["preferred_area"].size() == 2:
        center = Vector2i(int(request["preferred_area"][0]), int(request["preferred_area"][1]))
    var cell = find_location(world, row, center, orientation, nation)
    if request.get("location") is Array and request["location"].size() == 2:
        cell = Vector2i(int(request["location"][0]), int(request["location"][1]))
    var home: Vector2i = world.settlements.center(world, nation)
    if nation > 1 and (world.settlement_planner.reserved(world, nation, cell) or absi(cell.x - home.x) + absi(cell.y - home.y) > int(world.settlements.get_record(nation).get("radius",9))):
        return {"ok": false, "reason": "reserved_or_outside_local_plan"}
    var invalid = placement.validate(world, row, cell, orientation)
    if invalid != "":
        return {"ok": false, "reason": invalid}
    if indexed_houses != houses.size():
        rebuild_indexes()
    while sites_by_id.has(next_building_id) or buildings_by_id.has(next_building_id):
        next_building_id += 1
    var site: Dictionary = Site.create(next_building_id, world.settlements.nation(nation), row, cell, orientation, world.tick)
    site["resource_plan"] = assessment.get("resource_plan",{}).duplicate(true)
    site["architecture"] = catalogue.architecture_for(row)
    site["placement_reason"] = StrategicPlanner.explain(world,row,cell,world.settlements.center(world,nation),nation)
    site["placement_reason"]["score"] = world.settlement_planner.rank(world,row,cell,world.settlements.center(world,nation),nation)
    site["placement_reason"]["demand"] = request.get("demand", {"function":row["function"]}).duplicate(true)
    site["placement_reason"]["projected_capacity"] = int(row.get("occupancy_capacity",0)) + int(row.get("storage_capacity",0))
    site["placement_reason"]["projected_benefit"] = {"housing":int(row.get("occupancy_capacity",0)),"material_storage":int(row.get("storage_capacity",0)),"protected_grain":int(row.get("food_capacity",0)),"processes":row.get("production",[]).duplicate(true),"services":row.get("services",[]).duplicate(true)}
    site["settlement_id"] = nation
    next_building_id += 1
    site["priority"] = clampi(int(request.get("priority", 50)), 0, 100)
    site["demand"] = request.get("demand", {}).duplicate(true)
    for point in placement.footprint(row, cell, orientation):
        site["original_terrain"].append(world.at(point.x, point.y))
    Site.history(site, world.tick, "planned")
    projects.append(site)
    sites_by_id[int(site["id"])] = site
    placement.claim(row, site)
    reserve_available(world, site)
    revision += 1
    return {"ok": true, "site_id": site["id"]}

# Data-driven, needs-led support projects are independent archetypes. A charcoal
# clamp does not suppress a kiln/forge simply because both are production sites.
func support_project(world: RefCounted, sid: int) -> bool:
    var population: int = world.settlements.population(sid)
    if not project_for(sid).is_empty() or world.settlements.housing(world,sid)<population or world.food.total(world.food.store(sid))<population*2: return false
    var rows: Array = catalogue.definitions.values()
    rows.sort_custom(func(a: Variant,b: Variant)->bool: return int(a["primary_age"])<int(b["primary_age"]) or (int(a["primary_age"])==int(b["primary_age"]) and str(a["id"])<str(b["id"])))
    for row in rows:
        var goal: Dictionary = row.get("autonomous_goal",{})
        if goal.is_empty() or population<int(goal.get("minimum_population",4)) or not catalogue.eligible(world,sid,row,settlement_context.get(str(sid),{})): continue
        var present := false
        for house in houses:
            var current: Dictionary = catalogue.definition(str(house.get("definition_id","")))
            if world.settlements.sid(house)==sid and not bool(house.get("abandoned",false)) and str(current.get("archetype_id",""))==str(row["archetype_id"]): present = true
        if present: continue
        var product := str(goal.get("product",""))
        if product!="" and world.inventory.held("settlement:"+str(sid),product)>=4: continue
        if goal.has("food_grain") and int(world.food.store(sid).get("grain",0))<int(goal["food_grain"]): continue
        if goal.has("farms"):
            var farms := 0
            for farm in world.food.farms:
                if world.settlements.sid(farm)==sid: farms += 1
            if farms<int(goal["farms"]): continue
        if bool(goal.get("ore",false)):
            var ore: Dictionary = resource_plan(world,sid,{"copper_ore":1,"tin_ore":1})
            if not ore["viable"]: continue
        var request: Dictionary = request_construction(world,{"settlement_id":sid,"definition_id":row["id"],"function":row["function"],"priority":35,"demand":{"function":row["function"],"product":product,"population":population,"reason":"Low physical supply for local specialist work"}})
        if bool(request.get("ok",false)): return true
    return false

func plan(world: RefCounted) -> void:
    if world.tick % 15 != 1:
        return
    world.settlements.ensure_legacy(world)
    var keys: Array = world.settlements.records.keys()
    keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
    plan_cursor %= keys.size()
    var id := int(keys[plan_cursor])
    plan_cursor += 1
    var population: int = world.settlements.population(id)
    var capacity: int = world.settlements.housing(world, id)
    var record: Dictionary = world.settlements.get_record(id)
    record["plan"]["blocked_projects"] = []
    var carrying := int(record.get("plan", {}).get("carrying_capacity", 72))
    if str(record["status"]) in ["failed", "abandoned", "struggling"]:
        return
    if id > 1 and capacity > 0 and world.food.total(world.food.store(id)) < population:
        return
    if support_project(world,id): return
    if capacity >= mini(carrying,population) and population >= 4 and project_for(id).is_empty() and world.food.total(world.food.store(id)) >= population:
        var functions: Array = []
        var local: Dictionary = record.get("plan",{}).get("resources",{})
        if int(local.get("wood",0))>=6: functions.append("forestry")
        if int(local.get("stone",0))>=3: functions.append("quarry")
        functions.append_array(["storage","farm","tool_area","civic","market"])
        if int(world.food.store(id).get("grain",0)) >= 24: functions.append("granary")
        if world.occupations.has_capability(world,id,"stone_working") and int(local.get("wood",0))>=12: functions.append("production")
        var scores := {"forestry":20+maxi(0,40-int(local.get("wood",0))),"quarry":20+maxi(0,40-int(local.get("stone",0))),"storage":15+houses.size()/2,"farm":40 if world.food.total(world.food.store(id))<population*2 else 10,"tool_area":25,"civic":population,"market":0,"granary":35,"production":12}
        for member in world.settlements.residents.get(str(id),[]):
            var expert: Dictionary = world.ai_context.people.get(int(member),{})
            if not expert.is_empty(): scores["tool_area"] += mini(10,world.occupations.xp_for(expert,"stone_toolmaker"))
        for link in world.regional_economy.links.values():
            if id in [int(link["a"]),int(link["b"])] and str(link["status"])=="connected": scores["market"] += 20
        functions.sort_custom(func(a: Variant,b: Variant) -> bool: return int(scores.get(a,0))>int(scores.get(b,0)) or (int(scores.get(a,0))==int(scores.get(b,0)) and str(a)<str(b)))
        for function_name in functions:
            if str(function_name)=="market" and int(scores["market"])==0: continue
            if str(function_name)=="civic" and population<8: continue
            var present := false
            for house in houses:
                if world.settlements.sid(house)==id and str(house.get("function",house.get("type","")))==str(function_name) and not bool(house.get("abandoned",false)): present = true
            if present: continue
            var can_supply: bool = int(local.get("wood",0))+world.inventory.available("settlement:"+str(id),"wood")>=4 and int(local.get("stone",0))+world.inventory.available("settlement:"+str(id),"stone")>=3
            if not can_supply: continue
            var requested: Dictionary = request_construction(world,{"settlement_id":id,"function":function_name,"priority":clampi(int(scores.get(function_name,40)),1,100),"demand":{"function":function_name,"population":population,"food_reserves":world.food.total(world.food.store(id)),"priority_score":int(scores.get(function_name,40))}})
            if bool(requested.get("ok",false)): return
            if record["plan"]["blocked_projects"].size()<3: record["plan"]["blocked_projects"].append({"function":function_name,"reason":requested.get("reason",""),"details":requested.get("blocked",[])})
    if capacity >= population and project_for(id).is_empty() and catalogue.local_age(world,id)>=1 and world.occupations.has_capability(world,id,"stone_working"):
        for house in houses:
            if world.settlements.sid(house)==id and capacity-int(house.get("capacity",0))>=population and int(house.get("capacity",0))>0 and str(house.get("function","shelter"))=="shelter" and str(house.get("definition_id",""))=="primitive_shelter" and (population>=8 or int(record.get("plan",{}).get("resources",{}).get("land",100))<20):
                if lifecycle.begin_transition(self,world,int(house["id"]),"timber_hut","upgrade"): return
    if capacity < mini(carrying, population) and project_for(id).is_empty():
        request_construction(world, {"settlement_id": id, "function": "shelter", "priority": 70, "demand": {"unsheltered": population - capacity}})

func reserve_available(world: RefCounted, site: Dictionary) -> void:
    var key = "site:" + str(site["id"])
    var current: Dictionary = world.inventory.reservations.get(key, {}).get("units", {}).duplicate()
    for item in current.keys():
        if int(current[item]) == 0:
            current.erase(item)
    var transit = {}
    for task in jobs.values():
        if int(task.get("project_id", 0)) == int(site["id"]):
            for item in task.get("cargo", {}):
                transit[item] = int(transit.get(item, 0)) + int(task["cargo"][item])
    var holder = "settlement:" + str(site.get("settlement_id", site["nation"]))
    var changed = false
    for item in site["required"]:
        var need = int(site["required"][item]) - int(site["delivered"].get(item, 0)) - int(transit.get(item, 0)) - int(current.get(item, 0))
        var count = mini(need, world.inventory.available(holder, str(item)))
        if count > 0:
            current[item] = int(current.get(item, 0)) + count
            changed = true
    if changed:
        world.inventory.release_reservation(key)
        world.inventory.reserve(key, holder, current)

func _stock(id: int) -> Dictionary:
    return stockpiles[id] if id in [0, 1] else local_stockpiles.get(str(id), {})

func missing_material(nation: int, world: RefCounted = null) -> String:
    for site in projects:
        if int(site.get("settlement_id", site["nation"])) != nation or bool(site["paused"]):
            continue
        var required_items: Array = site["required"].keys()
        required_items.sort()
        for item in required_items:
            var transit = 0
            for task in jobs.values():
                if int(task.get("settlement_id", task.get("nation", -1))) == nation:
                    if str(task["kind"]) == "gather" and str(task.get("material", "")) == item:
                        transit += maxi(1, int(task.get("amount", 0)))
                    else:
                        transit += int(task.get("cargo", {}).get(item, 0))
            if int(_stock(nation).get(item, 0)) + transit + int(site["delivered"].get(item, 0)) < int(site["required"][item]):
                return str(item)
    for key in lifecycle.pending:
        var house: Dictionary = building_by_id(int(key))
        if house.is_empty() or int(house.get("settlement_id", house["nation"])) != nation or str(house.get("pending_action", "")) != "repair":
            continue
        var row: Dictionary = catalogue.definition(str(house.get("definition_id", "primitive_shelter")))
        for item in row["repair"]["materials"]:
            var carried := 0
            for task in jobs.values():
                if int(task.get("settlement_id", task.get("nation", -1))) == nation and str(task.get("material", "")) == item:
                    carried += maxi(1, int(task.get("amount", 0)))
                if int(task.get("building_id", 0)) == int(house["id"]):
                    carried += int(task.get("cargo", {}).get(item, 0))
            if int(_stock(nation).get(item, 0)) + carried < int(row["repair"]["materials"][item]):
                return str(item)
    if world != null:
        for id in operations.ids_for(self,nation):
            var house: Dictionary = building_by_id(int(id))
            if house.is_empty(): continue
            var row: Dictionary = catalogue.definition(str(house.get("definition_id","")))
            for process in operations.processes(row):
                if not operations.wanted(world,nation,house,process): continue
                var trained := false
                for person in world.citizens:
                    if operations.can_run(world,person,house,process):
                        trained = true
                        break
                if not trained: continue
                var recipe: Dictionary = operations.recipe(world,process)
                for item in recipe["inputs"]:
                    if str(item)=="grain" and int(world.food.store(nation).get("grain",0))>0: continue
                    if int(_stock(nation).get(item,0))<int(recipe["inputs"][item]): return str(item)
    return ""

func work_step(world: RefCounted, person: Dictionary, mind: Dictionary) -> bool:
    return tasks.work_step(self, world, person, mind)

func advance_stage(world: RefCounted, person: Dictionary, site: Dictionary) -> bool:
    var row = catalogue.definition(str(site["definition_id"]))
    var stage: Dictionary = row["stages"][int(site["stage"])]
    if not bool(site["stage_started"]):
        var materials: Dictionary = stage["materials"].duplicate(true)
        for item in site.get("pending_stage_materials", {}):
            materials[item] = int(materials.get(item,0)) + int(site["pending_stage_materials"][item])
        if not materials.is_empty() and not world.inventory.consume(world, "site:" + str(site["id"]), materials, int(person["id"]), "building_stage"):
            return false
        for item in materials:
            site["consumed"][item] = int(site["consumed"].get(item, 0)) + int(materials[item])
        site.erase("pending_stage_materials")
        site["stage_started"] = true
        Site.history(site, world.tick, str(stage["id"]))
    var effort := 1
    site["quality_sum"] = int(site.get("quality_sum",0)) + (60 + 10 * world.occupations.skill_tier(person,"shelter_builder")) * effort
    site["quality"] = int(site["quality_sum"]) / maxi(1,int(site["progress"]) + effort)
    site["stage_work"] += effort
    site["progress"] += effort
    site["remaining_labour"] = maxi(0, int(site["remaining_labour"]) - effort)
    site["last_progress_tick"] = int(world.tick)
    world.occupations.on_real_work(world, person, "shelter_builder")
    revision += 1
    if int(site["stage_work"]) >= int(stage["labour"]):
        site["stage"] += 1
        site["stage_work"] = 0
        site["stage_started"] = false
        if int(site["stage"]) >= row["stages"].size():
            lifecycle.complete(self, world, person, site, row)
    return true

func cancel(world: RefCounted, id: int, reason: String = "cancelled") -> bool:
    var site = site_by_id(id)
    if site.is_empty():
        return false
    Site.history(site, world.tick, "cancelled", {"reason": reason})
    if not world.inventory.close_site(world, site, {}):
        return false
    for task in jobs.values():
        if int(task.get("project_id", 0)) == id:
            task["phase"] = "return"
    remove_site(id)
    if site.has("previous_building"):
        var previous: Dictionary = site["previous_building"]
        houses.append(previous)
        buildings_by_id[id] = previous
        placement.claim(catalogue.definition(str(previous["definition_id"])), previous)
        indexed_houses = houses.size()
        world.households.dirty = true
    archived.append(site.duplicate(true))
    if archived.size() > 128:
        archived.pop_front()
    return true

func remove_site(id: int) -> void:
    for i in range(projects.size()):
        if int(projects[i]["id"]) == id:
            projects.remove_at(i)
            break
    sites_by_id.erase(id)
    placement.release(id)
    revision += 1

func on_terrain_changed(world: RefCounted, x: int, y: int) -> void:
    depleted.erase(str(world.index_of(x, y)))
    var id = int(placement.tiles.get(Vector2i(x, y), 0))
    if id == 0:
        return
    if sites_by_id.has(id):
        if world.at(x,y) in [world.MEADOW,world.TOWN]:
            return
        var site = site_by_id(id)
        site["paused"] = true
        site["pause_reason"] = "terrain"
        site["accessible"] = false
    elif buildings_by_id.has(id) and world.at(x,y) != world.TOWN:
        lifecycle.remove(self, world, id, false, "terrain_destruction")

func prune(world: RefCounted) -> void:
    world.inventory.reconcile_deaths(world)
    if indexed_houses != houses.size():
        rebuild_indexes()
    for key in jobs.keys():
        var person: Dictionary = world.ai_context.people.get(int(key), {})
        var task: Dictionary = jobs[key]
        if person.is_empty() or int(person["hp"]) <= 0 or world.tick - int(task.get("last_active_tick", world.tick)) > 240:
            tasks.interrupt(self, world, str(key))
    for i in range(mini(SITE_BUDGET, projects.size())):
        if projects.is_empty():
            break
        site_cursor %= projects.size()
        var site: Dictionary = projects[site_cursor]
        site_cursor += 1
        var invalid = placement.validate(world, catalogue.definition(str(site["definition_id"])), Vector2i(int(site["x"]), int(site["y"])), int(site["orientation"]), int(site["id"]))
        if invalid != "":
            site["paused"] = true
            site["pause_reason"] = invalid
            site["accessible"] = false
        elif str(site["pause_reason"]) != "manual" and world.tick >= int(site.get("retry_tick", 0)):
            site["paused"] = false
            site["pause_reason"] = ""
            site["accessible"] = true
        if world.tick % 15 == int(site["id"]) % 15 and not site["paused"]:
            reserve_available(world, site)
    lifecycle.tick(self, world)

func snapshot() -> Dictionary:
    return {"version": 2, "stockpiles": stockpiles.duplicate(true), "depleted": depleted.duplicate(true), "houses": houses.duplicate(true), "projects": projects.duplicate(true), "jobs": jobs.duplicate(true), "next_building_id": next_building_id, "settlement_context": settlement_context.duplicate(true), "archived": archived.duplicate(true), "site_cursor": site_cursor, "plan_cursor": plan_cursor, "maintenance_cursor": lifecycle.cursor}

func load_state(raw: Variant) -> bool:
    if raw is Dictionary and raw.is_empty():
        return true
    if not raw is Dictionary or int(raw.get("version", 0)) not in [1, 2]:
        return false
    if not raw.get("projects", []) is Array or not raw.get("houses", []) is Array or raw.get("projects", []).size() > MAX_SITES or raw.get("houses", []).size() > 12000:
        return false
    depleted = raw.get("depleted", {}).duplicate(true)
    settlement_context = raw.get("settlement_context", {}).duplicate(true)
    var seen = {}
    for entry in raw.get("houses", []):
        if not entry is Dictionary:
            return false
        var house: Dictionary = entry.duplicate(true)
        var id = int(house.get("id", 0))
        if id <= 0 or seen.has(id):
            return false
        seen[id] = true
        if int(raw["version"]) == 1:
            lifecycle.migrate(house)
        houses.append(house)
    for entry in raw.get("projects", []):
        var row = catalogue.definition(str(entry.get("definition_id", "primitive_shelter")))
        var id = int(entry.get("id", 0))
        if row.is_empty() or id <= 0 or seen.has(id):
            return false
        seen[id] = true
        var site: Dictionary = entry.duplicate(true)
        if int(raw["version"]) == 1:
            site = Site.create(id, int(entry["nation"]), row, Vector2i(int(entry["x"]), int(entry["y"])), 0, 0)
            site["reserved"] = int(entry.get("reserved", 0))
            var credit := clampi(int(entry.get("progress",0)),0,int(row["labour"])-1)
            site["progress"] = credit
            site["remaining_labour"] = int(row["labour"])-credit
            site["quality_sum"] = credit * 60
            site["pending_stage_materials"] = {}
            for stage in row["stages"]:
                if credit < int(stage["labour"]):
                    site["stage_work"] = credit
                    break
                credit -= int(stage["labour"])
                site["stage"] += 1
                for item in stage["materials"]:
                    site["pending_stage_materials"][item] = int(site["pending_stage_materials"].get(item,0)) + int(stage["materials"][item])
        if int(site.get("stage", -1)) not in range(row["stages"].size()):
            return false
        projects.append(site)
    jobs = raw.get("jobs", {}).duplicate(true)
    if jobs.size() > MAX_JOBS:
        return false
    for id in jobs:
        if int(raw["version"]) == 1:
            var task: Dictionary = jobs[id]
            if str(task.get("kind", "")) == "build":
                task["cargo"] = {}
                for item in ["wood", "stone"]:
                    if int(task.get(item, 0)) > 0:
                        task["cargo"][item] = int(task[item])
                task["phase"] = "site" if not task["cargo"].is_empty() else "depot"
    for i in range(2):
        stockpiles[i] = raw.get("stockpiles", [{}, {}])[i].duplicate(true)
    next_building_id = maxi(1, int(raw.get("next_building_id", 1)))
    for entry in raw.get("archived", []):
        archived.append(entry.duplicate(true))
    plan_cursor = maxi(0, int(raw.get("plan_cursor", 0)))
    site_cursor = int(raw.get("site_cursor", 0))
    lifecycle.cursor = int(raw.get("maintenance_cursor", 0))
    rebuild_indexes()
    return true

# Cross-service validation after all save components have been restored.
func validate_restored(world: RefCounted) -> bool:
    var footprints := {}
    for group in [houses, projects]:
        for entity in group:
            if int(entity.get("nation", -1)) not in [0,1] or world.index_of(int(entity.get("x", -1)),int(entity.get("y", -1))) < 0:
                return false
            var row: Dictionary = catalogue.definition(str(entity.get("definition_id", "primitive_shelter")))
            if row.is_empty():
                return false
            if entity.has("architecture"):
                var architecture: Variant = entity["architecture"]
                if not architecture is Dictionary or str(architecture.get("sprite","")) != str(row["visual"]["sprite"]) or int(architecture.get("primary_age",0)) != int(row["primary_age"]): return false
            if entity.has("irrigation_slots") or entity.has("irrigation_until"):
                var services: Array = row.get("services",[])
                if services.is_empty() or int(entity.get("irrigation_slots",-1))<0 or int(entity.get("irrigation_slots",999))>int(services[0]["capacity"]) or int(entity.get("irrigation_until",-1))<0 or int(entity.get("irrigation_until",0))>world.tick+int(services[0]["duration"]): return false
            for cell in placement.footprint(row,Vector2i(int(entity["x"]),int(entity["y"])),int(entity.get("orientation",0))):
                if footprints.has(cell) or world.index_of(cell.x,cell.y) < 0:
                    return false
                footprints[cell] = true
    for site in projects:
        var row: Dictionary = catalogue.definition(str(site["definition_id"]))
        for item in row["materials"]:
            var delivered := int(site["delivered"].get(item,0))
            var used := int(site["consumed"].get(item,0))
            if delivered < 0 or used < 0 or delivered > int(row["materials"][item]) or delivered != used + world.inventory.held("site:"+str(site["id"]),str(item)):
                return false
        if int(site["remaining_labour"]) < 0 or int(site["progress"]) + int(site["remaining_labour"]) != int(row["labour"]):
            return false
    for key in jobs:
        var task: Dictionary = jobs[key]
        if str(task.get("kind","")) != "operate": continue
        var house: Dictionary = building_by_id(int(task.get("building_id",0)))
        if house.is_empty() or str(task.get("phase","")) not in ["depot","site","return"] or int(task.get("remaining",-1))<0: return false
        var matched := false
        for process in operations.processes(catalogue.definition(str(house["definition_id"]))):
            if operations.key(process)==str(task.get("item","")) and int(task["remaining"])<=int(process["work"]): matched = true
        if not matched: return false
    for key in world.inventory.reservations:
        var site: Dictionary = site_by_id(int(str(key).trim_prefix("site:")))
        if site.is_empty() or str(world.inventory.reservations[key]["holder"]) != "settlement:"+str(site.get("settlement_id", site["nation"])):
            return false
    return true
