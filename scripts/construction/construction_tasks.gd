extends RefCounted
const Nav = preload("res://scripts/ai/navigation.gd")
const Site = preload("res://scripts/construction/site_state.gd")
const Labour = preload("res://scripts/ai/labour_priorities.gd")

func interrupt(engine: RefCounted, world: RefCounted, id: String) -> void:
    var task: Dictionary = engine.jobs.get(id, {})
    if str(task.get("kind", "")) == "gather" and str(task.get("phase", "")) == "depot":
        task["cargo"] = {str(task["material"]):int(task.get("amount",1))}
    var site: Dictionary = engine.site_by_id(int(task.get("project_id", 0)))
    if not site.is_empty():
        site["reserved"] = 0
        site["assigned_workers"].erase(int(id))
    var house: Dictionary = engine.building_by_id(int(task.get("building_id", 0)))
    if not house.is_empty():
        house.erase("worker")
        engine.lifecycle.pending[int(house["id"])] = true
    # Keep carried goods owned by the living worker. Recovery task returns them.
    var person: Dictionary = world.ai_context.people.get(int(id), {})
    if not person.is_empty() and int(person["hp"]) > 0 and not task.get("cargo", {}).is_empty():
        task["phase"] = "return"
        task["kind"] = "build"
        task["project_id"] = 0
        task["last_active_tick"] = world.tick
    else:
        engine.jobs.erase(id)
    if world.citizen_ai_by_id.has(id):
        world.citizen_ai_by_id[id]["route"] = []

func finish(engine: RefCounted, id: String, mind: Dictionary) -> void:
    var task: Dictionary = engine.jobs.get(id, {})
    var site: Dictionary = engine.site_by_id(int(task.get("project_id", 0)))
    if not site.is_empty():
        site["reserved"] = 0
        site["assigned_workers"].erase(int(id))
    engine.jobs.erase(id)
    mind["route"] = []

func work_step(engine: RefCounted, world: RefCounted, person: Dictionary, mind: Dictionary) -> bool:
    var id = str(person["id"])
    var nation = world.settlements.sid(person)
    if int(person["hp"]) <= 0 or world.lifecycle.is_dependent(person):
        return false
    var depot: Vector2i = world.settlements.center(world, nation)
    if depot.x < 0 or not world.is_walkable(depot.x, depot.y):
        return false
    if not engine.jobs.has(id):
        if engine.jobs.size() >= engine.MAX_JOBS or world.food.jobs.has(id) or world.toolmaking.jobs.has(id) or world.regional_economy.trade_jobs.has(id) or world.regional_economy.road_jobs.has(id) or world.local_logistics.jobs.has(id):
            return false
        # Actual occupation, tools, proximity and local knowledge govern work.
        var chosen = {}
        var best = -2147483647
        var pressure: Dictionary = Labour.pressures(world, nation)
        var critical_repairs := false
        for house in engine.houses:
            if world.settlements.sid(house) == nation and str(house.get("pending_action", "")) == "repair" and int(house.get("condition", 100)) < 45:
                critical_repairs = true
                break
        # Protect collapsing housing before assigning optional projects.
        var maintenance_assigned := critical_repairs and engine.lifecycle.assign(engine, world, person)
        var origin = Vector2i(int(person["x"]), int(person["y"]))
        for site in engine.projects:
            if maintenance_assigned or world.settlements.sid(site) != nation or site["paused"] or int(site["reserved"]) != 0:
                continue
            var row: Dictionary = engine.catalogue.definition(str(site["definition_id"]))
            if not engine.catalogue.worker_eligible(world, person, row):
                continue
            var score: int = Labour.project_score(world, site, origin, pressure)
            if score > best:
                chosen = site
                best = score
        if not chosen.is_empty():
            chosen["reserved"] = int(person["id"])
            chosen["assigned_workers"] = [int(person["id"])]
            engine.jobs[id] = {"kind": "build", "nation": int(person["nation"]), "settlement_id": nation, "project_id": int(chosen["id"]), "phase": "depot", "cargo": {}, "wood": 0, "stone": 0, "last_active_tick": int(world.tick)}
        elif maintenance_assigned or engine.lifecycle.assign(engine, world, person):
            pass
        else:
            if engine.gatherer_count(nation) >= engine.MAX_GATHERERS:
                return false
            var material: String = engine.missing_material(nation)
            if material == "":
                return false
            world.toolmaking.try_equip(world, person, material)
            var source: Dictionary = engine.source_for(world, person, material)
            if source.is_empty():
                return false
            engine.jobs[id] = {"kind": "gather", "nation": int(person["nation"]), "settlement_id": nation, "phase": "source", "material": material, "source": source["source"], "target": source["target"], "wood": 0, "stone": 0, "amount": 0, "last_active_tick": int(world.tick)}
        engine.jobs[id]["settlement_id"] = nation
        mind["route"] = []
        mind["next_path_tick"] = world.tick
    var task: Dictionary = engine.jobs[id]
    task["last_active_tick"] = int(world.tick)
    if str(task["kind"]) == "gather":
        return engine.gather_step(world, person, mind, id, task, depot)
    if str(task["kind"]) in ["repair", "demolish"]:
        return engine.lifecycle.work(engine, world, person, mind, task)
    var site: Dictionary = engine.site_by_id(int(task.get("project_id", 0)))
    if str(task["phase"]) == "return" or site.is_empty():
        if not task.get("cargo", {}).is_empty():
            if engine.walk(world, person, mind, depot, 1) and world.inventory.transfer(world, "citizen:" + id, "settlement:" + str(nation), task["cargo"], int(person["id"])):
                finish(engine, id, mind)
            return true
        finish(engine, id, mind)
        return false
    var row: Dictionary = engine.catalogue.definition(str(site["definition_id"]))
    if not engine.catalogue.worker_eligible(world, person, row):
        interrupt(engine, world, id)
        return false
    if site["paused"]:
        interrupt(engine, world, id)
        return false
    var target = Vector2i(int(site["x"]), int(site["y"]))
    if str(task["phase"]) == "depot":
        if not engine.walk(world, person, mind, depot, 1):
            return true
        engine.reserve_available(world, site)
        var claim: Dictionary = world.inventory.reservations.get("site:" + str(site["id"]), {}).get("units", {})
        # Partial, capacity-aware shipments. Never consume at pickup.
        var bundle = {}
        for item in claim:
            if int(claim[item]) > 0:
                var candidate = bundle.duplicate()
                candidate[item] = 1
                var carried: Dictionary = world.inventory.citizen_inventory(int(person["id"]))
                for key in candidate:
                    carried[key] = int(carried.get(key, 0)) + int(candidate[key])
                if world.inventory._weight(carried) <= world.inventory.MAX_CARRY_KG:
                    bundle = candidate
        if not bundle.is_empty() and world.inventory.transfer(world, "settlement:" + str(nation), "citizen:" + id, bundle, int(person["id"]), "", "site:" + str(site["id"])):
            task["cargo"] = bundle
            task["wood"] = int(bundle.get("wood", 0))
            task["stone"] = int(bundle.get("stone", 0))
            task["phase"] = "site"
            mind["route"] = []
        elif int(site["remaining_labour"]) > 0:
            task["phase"] = "site"
            mind["route"] = []
        return true
    var before = Vector2i(int(person["x"]), int(person["y"]))
    if not engine.walk(world, person, mind, target):
        var after = Vector2i(int(person["x"]), int(person["y"]))
        task["stalled"] = int(task.get("stalled", 0)) + 1 if after == before else 0
        if int(task["stalled"]) > 24:
            site["paused"] = true
            site["pause_reason"] = "unreachable"
            site["retry_tick"] = int(world.tick) + 120
            interrupt(engine, world, id)
        return true
    if not task.get("cargo", {}).is_empty():
        if not world.inventory.transfer(world, "citizen:" + id, "site:" + str(site["id"]), task["cargo"], int(person["id"])):
            return true
        for item in task["cargo"]:
            site["delivered"][item] = int(site["delivered"].get(item, 0)) + int(task["cargo"][item])
        Site.history(site, world.tick, "delivery", task["cargo"])
        task["cargo"] = {}
        task["wood"] = 0
        task["stone"] = 0
    if not engine.advance_stage(world, person, site):
        task["phase"] = "depot"
        mind["route"] = []
    elif engine.site_by_id(int(site["id"])).is_empty():
        finish(engine, id, mind)
    return true
