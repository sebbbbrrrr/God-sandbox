extends RefCounted
const Nav = preload("res://scripts/ai/navigation.gd")
const DECLINE_TICKS := 180
const ABANDON_TICKS := 240

func evaluate(world: RefCounted, id: int, local: Dictionary) -> void:
    var row: Dictionary = world.settlements.get_record(id)
    var elapsed := clampi(world.tick-int(row.get("last_evaluation",world.tick)),0,360)
    row["last_evaluation"] = world.tick
    var count: int = world.settlements.population(id)
    var adults := 0
    var hungry := 0
    var skilled := 0
    for member in world.settlements.residents.get(str(id),[]):
        var person: Dictionary = world.ai_context.people.get(int(member),{})
        if person.is_empty(): continue
        hungry += int(person.get("hunger",0))
        if not world.lifecycle.is_dependent(person): adults += 1
        if world.occupations.xp_for(person,"stone_toolmaker")>=8: skilled += 1
    var dangerous: bool = int(local.get("hazards",0))>0 or not world.is_walkable(world.settlements.center(world,id).x,world.settlements.center(world,id).y)
    var depleted: bool = int(local.get("food",0))==0 and world.food.total(world.food.store(id))<count
    var distressed := dangerous or depleted or (count>0 and hungry/maxi(1,count)>=70) or (count>0 and adults==0)
    row["stress_ticks"] = mini(3600,int(row.get("stress_ticks",0))+elapsed) if distressed else maxi(0,int(row.get("stress_ticks",0))-elapsed*2)
    row["empty_ticks"] = int(row.get("empty_ticks",0))+elapsed if count==0 else 0
    row["security"] = 0 if dangerous else 100
    row["workers"] = adults
    row["food_insecure"] = depleted or (count>0 and hungry/maxi(1,count)>=60)
    row["isolated"] = _connections(world,id)==0
    row["radius"] = clampi(7+count/6+_connections(world,id),9,16)
    if str(row["status"])=="camp": return # founding owns its survival milestone
    if count==0 and int(row["empty_ticks"])>=ABANDON_TICKS:
        _status(world,id,"abandoned")
    elif int(row["stress_ticks"])>=DECLINE_TICKS:
        _status(world,id,"struggling")
    elif count>0 and not distressed and str(row["status"]) in ["struggling","failed","abandoned"]:
        _status(world,id,"active")
    if str(row["status"])=="struggling":
        _evacuate_one(world,id)
    if str(row["status"])=="active" and count>0:
        _recover_building(world,id)
    if skilled>0 and not world.occupations.has_capability(world,id,"stone_working") and world.occupations.facility_present(world,id,"tool_area"):
        world.occupations.grant_capability(world,id,"stone_working","teaching")
    _specialise(world,id,local,skilled)

func _connections(world: RefCounted, id: int) -> int:
    var count := 0
    for link in world.regional_economy.links.values():
        if id in [int(link["a"]),int(link["b"])] and str(link["status"])=="connected": count += 1
    return count

func _status(world: RefCounted, id: int, status: String) -> void:
    var row: Dictionary = world.settlements.get_record(id)
    if str(row["status"])==status: return
    row["status"] = status
    world.settlements.event(world,id,"settlement_"+status)
    world.settlements.revision += 1
    if status=="abandoned":
        for house in world.construction.houses:
            if world.settlements.sid(house)==id:
                world.construction.lifecycle.abandon(world.construction,world,int(house["id"]),true)
        for site in world.construction.projects:
            if world.settlements.sid(site)==id:
                site["paused"] = true
                site["pause_reason"] = "manual"
                world.inventory.release_reservation("site:"+str(site["id"]))

func _recover_building(world: RefCounted, id: int) -> void:
    for house in world.construction.houses:
        if world.settlements.sid(house)==id and bool(house.get("abandoned",false)):
            world.construction.lifecycle.abandon(world.construction,world,int(house["id"]),false)
            return
    for site in world.construction.projects:
        if world.settlements.sid(site)==id and str(site.get("pause_reason",""))=="manual":
            site["pause_reason"] = ""
            site["paused"] = false
            return

func _evacuate_one(world: RefCounted, source: int) -> void:
    if world.founding.active_count()>=world.founding.MAX_ACTIVE: return
    var target := -1
    var best := 2147483647
    var origin: Vector2i = world.settlements.center(world,source)
    var keys: Array = world.settlements.records.keys()
    keys.sort_custom(func(a: Variant,b: Variant) -> bool: return int(a)<int(b))
    for key in keys:
        var id := int(key)
        var row: Dictionary = world.settlements.get_record(id)
        if id==source or world.settlements.nation(id)!=world.settlements.nation(source) or str(row["status"]) in ["failed","abandoned","struggling","camp"]: continue
        if world.settlements.housing(world,id)<=world.settlements.population(id) or bool(row.get("food_insecure",false)): continue
        var destination: Vector2i = world.settlements.center(world,id)
        var distance: int = Nav.manhattan(origin,destination)
        if distance<best and distance<=48 and world.is_walkable(destination.x,destination.y) and not Nav.danger_near(world,destination):
            best = distance
            target = id
    if target<0: return
    for family in world.households.families:
        if int(family.get("settlement_id",family["nation"]))!=source: continue
        var members: int = world.households.member_count(world,family)
        if world.settlements.housing(world,target)-world.settlements.population(target)<members: continue
        if not world.founding.request_migration(world,family,target).is_empty(): return

func _specialise(world: RefCounted, id: int, local: Dictionary, skilled: int) -> void:
    var row: Dictionary = world.settlements.get_record(id)
    var scores := {"subsistence":1}
    for house in world.construction.houses:
        if world.settlements.sid(house)!=id or bool(house.get("abandoned",false)): continue
        match str(house.get("function",house.get("type",""))):
            "forestry": scores["forestry"] = mini(100,int(local.get("wood",0)))
            "quarry": scores["mining"] = mini(100,int(local.get("stone",0)))
            "tool_area": scores["crafting"] = skilled*20
            "market": scores["trading"] = _connections(world,id)*15
    for farm in world.food.farms:
        if world.settlements.sid(farm)==id and not bool(farm["harvested"]): scores["agricultural"] = int(scores.get("agricultural",0))+30
    if int(local.get("coast",0))>2:
        for member in world.settlements.residents.get(str(id),[]):
            var person: Dictionary = world.ai_context.people.get(int(member),{})
            if not person.is_empty() and world.occupations.xp_for(person,"fisher")>=4: scores["coastal"] = 30
    var selected := "subsistence"
    var best := 0
    var keys: Array = scores.keys()
    keys.sort()
    for key in keys:
        if int(scores[key])>best:
            best = int(scores[key])
            selected = str(key)
    if str(row["specialisation"])!=selected:
        row["specialisation"] = selected
        world.settlements.event(world,id,"specialisation:"+selected)
