extends RefCounted
const World = preload("res://scripts/simulation.gd")

static func world():
    var w = World.new(191126,false)
    for y in range(5,60):
        for x in range(5,60): w.set_terrain_cell(x,y,w.MEADOW)
    for y in range(8,58):
        for x in range(10,16): w.set_terrain_cell(x,y,w.FOREST)
        if y%3==0: w.set_terrain_cell(17,y,w.MOUNTAIN)
    for y in range(10,58,3):
        w.set_terrain_cell(22,y,w.BEACH)
        w.set_terrain_cell(23,y,w.OCEAN)
        w.set_terrain_cell(18,y,w.BEACH)
        w.set_terrain_cell(19,y,w.OCEAN)
    w.capitals[0] = Vector2i(20,30)
    for i in range(8): w.add_citizen(20,30,0)
    w.ai_context.begin_tick(w)
    w.settlements.ensure_legacy(w)
    # Controlled scenario prerequisites, not a claim of autonomous invention.
    for tech in ["stone_working","cultivation","pottery","weaving"]:
        w.occupations.grant_capability(w,0,tech,"experiment")
    for p in w.citizens:
        w.occupations.record_for(p)["xp"] = {"stone_toolmaker":300,"potter":300,"basket_weaver":300,"shelter_builder":300}
        w.occupations.record_for(p)["last_practice"] = {"stone_toolmaker":0,"potter":0,"basket_weaver":0,"shelter_builder":0}
    return w

static func walk(w, p: Dictionary, target: Vector2i, radius: int = 0) -> bool:
    var mind: Dictionary = w.citizen_ai_by_id[str(p["id"])]
    mind["route"] = []
    for i in range(200):
        w.tick += 1
        w.ai_context.begin_tick(w)
        if w.construction.walk(w,p,mind,target,radius): return true
    return false

static func stock(w, units: Dictionary) -> bool:
    var p: Dictionary = w.citizens[0]
    for item in units:
        var need: int = int(units[item])-w.inventory.available("settlement:0",str(item))
        while need>0:
            var source: Dictionary = w.construction.source_for(w,p,str(item))
            if source.is_empty(): return false
            var point := Vector2i(int(source["source"][0]),int(source["source"][1]))
            var target := Vector2i(int(source["target"][0]),int(source["target"][1]))
            if not walk(w,p,target): return false
            var amount: int = mini(need,mini(2,w.construction.left_at(w,point.x,point.y,str(item))))
            if not w.inventory.extract(w,int(p["id"]),str(item),point,amount): return false
            if not walk(w,p,w.capitals[0],1): return false
            if not w.inventory.transfer(w,"citizen:"+str(p["id"]),"settlement:0",{str(item):amount},int(p["id"])): return false
            need -= amount
    return true

static func work(w, steps: int) -> void:
    var p: Dictionary = w.citizens[0]
    for i in range(steps):
        w.tick += 1
        w.ai_context.begin_tick(w)
        w.construction.prune(w)
        w.construction.work_step(w,p,w.citizen_ai_by_id[str(p["id"])])

static func build(w, id: String, cell: Vector2i) -> Dictionary:
    var row: Dictionary = w.construction.catalogue.definition(id)
    var climate := "cold" if id=="earth_shelter" else "arid" if id=="adobe_house" else "tropical" if id=="stilt_house" else "temperate"
    w.construction.settlement_context["0"] = {"climates":climate}
    if not stock(w,row["materials"]): return {}
    var result: Dictionary = w.construction.request_construction(w,{"settlement_id":0,"definition_id":id,"function":row["function"],"location":[cell.x,cell.y],"require_stock":true,"demand":{"function":row["function"],"scenario":"architectural demonstration"}})
    if not bool(result.get("ok",false)): return {}
    var site_id := int(result["site_id"])
    for i in range(800):
        work(w,1)
        var house: Dictionary = w.construction.building_by_id(site_id)
        if not house.is_empty(): return house
    return {}
