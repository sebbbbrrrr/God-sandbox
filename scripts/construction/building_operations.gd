extends RefCounted
# Bounded physical facility jobs share construction custody, workers and saves.
const Nav = preload("res://scripts/ai/navigation.gd")
const MAX_LOCAL_WORKERS := 2
const MAX_CANDIDATES := 16
var indexed_revision := -1
var by_settlement: Dictionary = {}

func processes(row: Dictionary) -> Array:
    return row.get("production",[]) + row.get("services",[])

func key(process: Dictionary) -> String:
    return "service:"+str(process["id"]) if process.has("kind") else str(process["item"])

func recipe(world: RefCounted, process: Dictionary) -> Dictionary:
    if process.has("kind"): return {"inputs":process["inputs"],"output":0,"skill":process["role"]}
    return world.inventory.catalogue.item(str(process["item"])).get("recipe",{})

func ids_for(engine: RefCounted, sid: int) -> Array:
    if indexed_revision != int(engine.building_revision):
        by_settlement.clear()
        for house in engine.houses:
            if processes(engine.catalogue.definition(str(house.get("definition_id","")))).is_empty(): continue
            var owner := int(house.get("settlement_id",house["nation"]))
            if not by_settlement.has(owner): by_settlement[owner] = []
            by_settlement[owner].append(int(house["id"]))
        for owner in by_settlement: by_settlement[owner].sort()
        indexed_revision = int(engine.building_revision)
    return by_settlement.get(sid,[])

func prototype_allowed(world: RefCounted, person: Dictionary, process: Dictionary) -> bool:
    var trial: Dictionary = process.get("prototype",{})
    if trial.is_empty() or world.calendar.age_years(int(person["birth_tick"]),world.tick)<18: return false
    for tech in trial["knowledge"]:
        if not world.occupations.has_capability(world,world.settlements.sid(person),str(tech)): return false
    return world.occupations.xp_for(person,str(trial["skill"]))>=int(trial["min_xp"])

func water_available(world: RefCounted, house: Dictionary) -> bool:
    var cell := Vector2i(int(house["x"]),int(house["y"]))
    for y in range(-2,4):
        for x in range(-2,4):
            if world.at(cell.x+x,cell.y+y)==world.OCEAN: return true
    return false

func can_run(world: RefCounted, person: Dictionary, house: Dictionary, process: Dictionary) -> bool:
    if int(person.get("hp",0))<=0 or world.lifecycle.is_dependent(person): return false
    var sid: int = world.settlements.sid(person)
    if world.settlements.sid(house)!=sid or bool(house.get("abandoned",false)) or int(house.get("condition",100))<25 or house.has("pending_action"): return false
    var row: Dictionary = world.construction.catalogue.definition(str(house.get("definition_id","")))
    if process not in processes(row) or not world.construction.catalogue.eligible(world,sid,row,world.construction.settlement_context.get(str(sid),{})): return false
    if process.has("kind"):
        return str(process["kind"])=="irrigation" and water_available(world,house) and world.occupations.enabled(world,sid,str(process["role"]))
    var item := str(process["item"])
    var rec := recipe(world,process)
    return not rec.is_empty() and (world.inventory.catalogue.can_craft(item,rec["inputs"],world.inventory.catalogue.context_for_citizen(world,person,item)) or prototype_allowed(world,person,process))

func wanted(world: RefCounted, sid: int, house: Dictionary, process: Dictionary) -> bool:
    if process.has("kind"):
        return int(house.get("irrigation_until",0))<=world.tick and int(world.food.store(sid).get("grain",0))>0
    return world.inventory.held("settlement:"+str(sid),str(process["item"]))<int(process["target_stock"])

func assign(engine: RefCounted, world: RefCounted, person: Dictionary) -> bool:
    var sid: int = world.settlements.sid(person)
    var candidates: Array = ids_for(engine,sid)
    if candidates.is_empty(): return false
    var count := 0
    var busy: Dictionary = {}
    for task in engine.jobs.values():
        if str(task.get("kind",""))=="operate":
            busy[int(task.get("building_id",0))] = true
            if int(task.get("settlement_id",-1))==sid: count += 1
    if count>=MAX_LOCAL_WORKERS: return false
    for id in candidates.slice(0,MAX_CANDIDATES):
        var house: Dictionary = engine.building_by_id(int(id))
        if house.is_empty() or busy.has(int(id)): continue
        for process in processes(engine.catalogue.definition(str(house["definition_id"]))):
            if not wanted(world,sid,house,process) or not can_run(world,person,house,process): continue
            var supplied := true
            for ingredient in recipe(world,process)["inputs"]:
                var available: int = world.inventory.available("settlement:"+str(sid),str(ingredient))
                if str(ingredient)=="grain": available += int(world.food.store(sid).get("grain",0))
                if available<int(recipe(world,process)["inputs"][ingredient]): supplied = false
            if not supplied: continue
            engine.jobs[str(person["id"])] = {"kind":"operate","phase":"depot","nation":int(person["nation"]),"settlement_id":sid,"building_id":int(id),"item":key(process),"remaining":int(process["work"]),"cargo":{},"last_active_tick":world.tick}
            return true
    return false

# Explicit work orders use the same role gates, quotas and physical job path as AI.
func start(engine: RefCounted, world: RefCounted, person: Dictionary, house: Dictionary, process: Dictionary) -> bool:
    var worker := str(person["id"])
    if engine.jobs.has(worker) or world.food.jobs.has(worker) or world.toolmaking.jobs.has(worker) or not can_run(world,person,house,process): return false
    var count := 0
    for task in engine.jobs.values():
        if str(task.get("kind",""))=="operate":
            if int(task.get("building_id",0))==int(house["id"]): return false
            if int(task.get("settlement_id",-1))==world.settlements.sid(person): count += 1
    if count>=MAX_LOCAL_WORKERS: return false
    engine.jobs[worker] = {"kind":"operate","phase":"depot","nation":int(person["nation"]),"settlement_id":world.settlements.sid(person),"building_id":int(house["id"]),"item":key(process),"remaining":int(process["work"]),"cargo":{},"last_active_tick":world.tick}
    world.citizen_ai_by_id[worker]["route"] = []
    return true

func work(engine: RefCounted, world: RefCounted, person: Dictionary, mind: Dictionary, task: Dictionary) -> bool:
    var worker := str(person["id"])
    var sid: int = world.settlements.sid(person)
    var house: Dictionary = engine.building_by_id(int(task.get("building_id",0)))
    var row: Dictionary = engine.catalogue.definition(str(house.get("definition_id","")))
    var process: Dictionary = {}
    for candidate in processes(row):
        if key(candidate)==str(task["item"]): process = candidate
    if house.is_empty() or process.is_empty() or not can_run(world,person,house,process):
        engine.tasks.interrupt(engine,world,worker)
        return false
    task["last_active_tick"] = world.tick
    var depot: Vector2i = world.settlements.center(world,sid)
    var rec := recipe(world,process)
    if str(task["phase"])=="depot":
        if not engine.walk(world,person,mind,depot,1): return true
        var inputs: Dictionary = {}
        for item in rec["inputs"]: inputs[item] = int(rec["inputs"][item])
        if inputs.has("grain"): world.inventory.allocate_food_grain(world,int(person["id"]),int(inputs["grain"]))
        if not world.inventory.transfer(world,"settlement:"+str(sid),"citizen:"+worker,inputs,int(person["id"])):
            engine.tasks.finish(engine,worker,mind)
            return false
        task["cargo"] = inputs
        task["phase"] = "site"
        mind["route"] = []
        return true
    if str(task["phase"])=="return":
        if engine.walk(world,person,mind,depot,1) and world.inventory.transfer(world,"citizen:"+worker,"settlement:"+str(sid),task["cargo"],int(person["id"])): engine.tasks.finish(engine,worker,mind)
        return true
    var entry: Array = row.get("entrances",[[0,0]])[0]
    var target := Vector2i(int(house["x"])+int(entry[0]),int(house["y"])+int(entry[1]))
    if not engine.walk(world,person,mind,target): return true
    task["remaining"] = maxi(0,int(task["remaining"])-1)
    var practice := str(process.get("prototype",{}).get("practice_skill",""))
    if practice!="" and world.occupations.enabled(world,sid,practice): world.occupations.on_real_work(world,person,practice)
    if int(task["remaining"])>0: return true
    if process.has("kind"):
        if not world.inventory.consume(world,"citizen:"+worker,task["cargo"],int(person["id"]),"irrigation_upkeep"):
            engine.tasks.interrupt(engine,world,worker)
            return false
        house["irrigation_until"] = world.tick+int(process["duration"])
        house["irrigation_slots"] = int(process["capacity"])
        house["operating_cycles"] = int(house.get("operating_cycles",0))+1
        world.occupations.on_real_work(world,person,str(process["role"]))
        task["cargo"] = {}
        engine.tasks.finish(engine,worker,mind)
        return true
    if not world.inventory.craft_in_building(world,int(person["id"]),house,process):
        engine.tasks.interrupt(engine,world,worker)
        return false
    task["cargo"] = {str(process["item"]):int(rec["output"])}
    task["phase"] = "return"
    mind["route"] = []
    return true

# Called from real sowing, not from a passive tick: one paid lift cycle has two
# allocations. Actual nearby water, local ownership and condition remain gates.
func irrigate_sowing(world: RefCounted, sid: int, plot: Vector2i) -> bool:
    for id in ids_for(world.construction,sid):
        var house: Dictionary = world.construction.building_by_id(int(id))
        if bool(house.get("abandoned",false)) or int(house.get("condition",100))<25 or int(house.get("irrigation_until",0))<=world.tick or int(house.get("irrigation_slots",0))<=0 or not water_available(world,house): continue
        var row: Dictionary = world.construction.catalogue.definition(str(house["definition_id"]))
        for service in row.get("services",[]):
            if str(service["kind"])=="irrigation" and Nav.manhattan(plot,Vector2i(int(house["x"]),int(house["y"])))<=int(service["radius"]):
                house["irrigation_slots"] -= 1
                return true
    return false
