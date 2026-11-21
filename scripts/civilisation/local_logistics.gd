extends RefCounted
const Nav = preload("res://scripts/ai/navigation.gd")
const MAX_JOBS := 12
var jobs: Dictionary = {}

func deposit_holder(world: RefCounted, person: Dictionary, bundle: Dictionary) -> String:
    var sid: int = world.settlements.sid(person)
    var origin := Vector2i(int(person["x"]),int(person["y"]))
    var chosen := "settlement:"+str(sid)
    var best: int = Nav.manhattan(origin,world.settlements.center(world,sid))
    for house in world.construction.houses:
        if world.settlements.sid(house)!=sid or str(house.get("function",""))!="storage" or bool(house.get("abandoned",false)): continue
        var holder := "store:"+str(house["id"])
        var used := 0
        for count in world.inventory.balances.get(holder,{}).values(): used += int(count)
        for count in bundle.values(): used += int(count)
        if used>64: continue
        var distance: int = Nav.manhattan(origin,Vector2i(int(house["x"]),int(house["y"])))
        if distance < best:
            chosen = holder
            best = distance
    return chosen

func work_step(world: RefCounted, person: Dictionary, mind: Dictionary) -> bool:
    var key := str(person["id"])
    if world.lifecycle.is_dependent(person) or int(person["hp"])<=0: return false
    if not jobs.has(key):
        if jobs.size()>=MAX_JOBS or world.construction.jobs.has(key) or world.food.jobs.has(key) or world.toolmaking.jobs.has(key) or world.regional_economy.road_jobs.has(key) or world.regional_economy.trade_jobs.has(key): return false
        var sid: int = world.settlements.sid(person)
        for house in world.construction.houses:
            if world.settlements.sid(house)!=sid or str(house.get("function",""))!="storage": continue
            var holder := "store:"+str(house["id"])
            for good in ["wood","stone","flint","plant_fibre"]:
                if world.inventory.available(holder,good)<=0 or world.inventory.available("settlement:"+str(sid),good)>=6: continue
                jobs[key] = {"source":holder,"settlement_id":sid,"good":good,"phase":"pickup","started":world.tick}
                mind["route"] = []
                mind["next_path_tick"] = world.tick
                break
            if jobs.has(key): break
    if not jobs.has(key): return false
    var job: Dictionary = jobs[key]
    var bundle := {str(job["good"]):1}
    var source: Dictionary = world.inventory._holder(world,str(job["source"]))
    if str(job["phase"]) == "pickup":
        if source.is_empty():
            jobs.erase(key)
            return false
        if not world.construction.walk(world,person,mind,source["cell"]): return true
        if not world.inventory.transfer(world,str(job["source"]),"citizen:"+key,bundle,int(person["id"])):
            jobs.erase(key)
            return false
        job["phase"] = "return"
        mind["route"] = []
    var center: Vector2i = world.settlements.center(world,int(job["settlement_id"]))
    if world.construction.walk(world,person,mind,center,1) and world.inventory.transfer(world,"citizen:"+key,"settlement:"+str(job["settlement_id"]),bundle,int(person["id"])):
        jobs.erase(key)
        mind["route"] = []
    return true

func tick(world: RefCounted) -> void:
    for key in jobs.keys():
        var person: Dictionary = world.ai_context.people.get(int(key),{})
        if person.is_empty() or int(person["hp"])<=0: jobs.erase(key)

func snapshot() -> Dictionary:
    return {"version":1,"jobs":jobs.duplicate(true)}

func load_state(world: RefCounted, raw: Variant) -> bool:
    if raw==null: return true
    if not raw is Dictionary or int(raw.get("version",0))!=1 or not raw.get("jobs") is Dictionary or raw["jobs"].size()>MAX_JOBS: return false
    for key in raw["jobs"]:
        var row: Variant = raw["jobs"][key]
        var person: Dictionary = world.ai_context.people.get(int(key),{})
        if not row is Dictionary or person.is_empty() or int(row.get("settlement_id",-1))!=world.settlements.sid(person) or str(row.get("good","")) not in ["wood","stone","flint","plant_fibre"] or str(row.get("phase","")) not in ["pickup","return"]: return false
        if str(row["phase"])=="return" and world.inventory.held("citizen:"+str(key),str(row["good"]))<1: return false
    jobs = raw["jobs"].duplicate(true)
    return true
