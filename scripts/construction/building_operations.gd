extends RefCounted
# One operational path, using the existing construction job/custody authorities.
# Inputs are picked up physically, worked at a live building, then returned as
# outputs. No passive timer creates resources and no additional save store exists.
const Nav = preload("res://scripts/ai/navigation.gd")
const MAX_LOCAL_WORKERS := 2
const MAX_CANDIDATES := 16
var indexed_revision := -1
var by_settlement: Dictionary = {}

func ids_for(engine: RefCounted, sid: int) -> Array:
    if indexed_revision != int(engine.building_revision):
        by_settlement.clear()
        for house in engine.houses:
            if engine.catalogue.definition(str(house.get("definition_id",""))).get("production",[]).is_empty(): continue
            var owner := int(house.get("settlement_id",house["nation"]))
            if not by_settlement.has(owner): by_settlement[owner] = []
            by_settlement[owner].append(int(house["id"]))
        for key in by_settlement: by_settlement[key].sort()
        indexed_revision = int(engine.building_revision)
    return by_settlement.get(sid,[])

func can_run(world: RefCounted, person: Dictionary, house: Dictionary, process: Dictionary) -> bool:
    if int(person.get("hp",0)) <= 0 or world.lifecycle.is_dependent(person): return false
    if world.settlements.sid(house) != world.settlements.sid(person): return false
    if bool(house.get("abandoned",false)) or int(house.get("condition",100)) < 25 or house.has("pending_action"): return false
    var row: Dictionary = world.construction.catalogue.definition(str(house.get("definition_id","")))
    if process not in row.get("production",[]) or not world.construction.catalogue.eligible(world,world.settlements.sid(person),row,world.construction.settlement_context.get(str(world.settlements.sid(person)),{})): return false
    var item := str(process.get("item",""))
    var context: Dictionary = world.inventory.catalogue.context_for_citizen(world,person,item)
    var recipe: Dictionary = world.inventory.catalogue.item(item).get("recipe",{})
    return not recipe.is_empty() and world.inventory.catalogue.can_craft(item,recipe.get("inputs",{}),context)

func assign(engine: RefCounted, world: RefCounted, person: Dictionary) -> bool:
    var sid: int = world.settlements.sid(person)
    var candidates: Array = ids_for(engine,sid)
    if candidates.is_empty(): return false
    var count := 0
    var busy: Dictionary = {}
    for task in engine.jobs.values():
        if str(task.get("kind","")) == "operate":
            busy[int(task.get("building_id",0))] = true
            if int(task.get("settlement_id",-1)) == sid: count += 1
    if count >= MAX_LOCAL_WORKERS: return false
    var scanned := 0
    for id in candidates:
        var house: Dictionary = engine.building_by_id(int(id))
        if house.is_empty(): continue
        var row: Dictionary = engine.catalogue.definition(str(house.get("definition_id","")))
        if row.get("production",[]).is_empty(): continue
        scanned += 1
        if scanned > MAX_CANDIDATES: break
        if busy.has(int(house["id"])): continue
        for process in row["production"]:
            if not can_run(world,person,house,process): continue
            var item := str(process["item"])
            var holder := "settlement:"+str(sid)
            if world.inventory.held(holder,item) >= int(process["target_stock"]): continue
            var recipe: Dictionary = world.inventory.catalogue.item(item)["recipe"]
            var supplied := true
            for ingredient in recipe["inputs"]:
                if world.inventory.available(holder,str(ingredient)) < int(recipe["inputs"][ingredient]): supplied = false
            if not supplied: continue
            engine.jobs[str(person["id"])] = {"kind":"operate","phase":"depot","nation":int(person["nation"]),"settlement_id":sid,
                "building_id":int(house["id"]),"item":item,"remaining":int(process["work"]),"cargo":{},"last_active_tick":int(world.tick)}
            return true
    return false

func work(engine: RefCounted, world: RefCounted, person: Dictionary, mind: Dictionary, task: Dictionary) -> bool:
    var key := str(person["id"])
    var sid: int = world.settlements.sid(person)
    var house: Dictionary = engine.building_by_id(int(task.get("building_id",0)))
    var row: Dictionary = engine.catalogue.definition(str(house.get("definition_id","")))
    var process: Dictionary = {}
    for candidate in row.get("production",[]):
        if str(candidate["item"]) == str(task["item"]): process = candidate
    if house.is_empty() or process.is_empty() or not can_run(world,person,house,process):
        engine.tasks.interrupt(engine,world,key)
        return false
    task["last_active_tick"] = world.tick
    var depot: Vector2i = world.settlements.center(world,sid)
    var recipe: Dictionary = world.inventory.catalogue.item(str(task["item"]))["recipe"]
    if str(task["phase"]) == "depot":
        if not engine.walk(world,person,mind,depot,1): return true
        var inputs: Dictionary = {}
        for item in recipe["inputs"]: inputs[item] = int(recipe["inputs"][item])
        if not world.inventory.transfer(world,"settlement:"+str(sid),"citizen:"+key,inputs,int(person["id"])):
            engine.tasks.finish(engine,key,mind)
            return false
        task["cargo"] = inputs.duplicate(true)
        task["phase"] = "site"
        mind["route"] = []
        return true
    if str(task["phase"]) == "return":
        if engine.walk(world,person,mind,depot,1) and world.inventory.transfer(world,"citizen:"+key,"settlement:"+str(sid),task["cargo"],int(person["id"])):
            engine.tasks.finish(engine,key,mind)
        return true
    var entry: Array = row.get("entrances",[[0,0]])[0]
    var target := Vector2i(int(house["x"])+int(entry[0]),int(house["y"])+int(entry[1]))
    if not engine.walk(world,person,mind,target): return true
    task["remaining"] = maxi(0,int(task["remaining"])-1)
    if int(task["remaining"]) > 0: return true
    # Commit validates the live site, citizen, role, knowledge, cargo and capacity
    # again. Failure leaves all inputs intact for retry or return.
    if not world.inventory.craft_in_building(world,int(person["id"]),house,process):
        engine.tasks.interrupt(engine,world,key)
        return false
    task["cargo"] = {str(task["item"]):int(recipe["output"])}
    task["phase"] = "return"
    mind["route"] = []
    return true
