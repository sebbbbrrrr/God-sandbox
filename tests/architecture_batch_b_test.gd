extends SceneTree
const F = preload("res://tests/architecture_fixture.gd")
const World = preload("res://scripts/simulation.gd")
const Store = preload("res://scripts/ai/save_store.gd")
var failures := 0
var checks := 0
func check(ok: bool, label: String) -> void:
    checks += 1
    if ok: print("PASS: "+label)
    else:
        failures += 1
        push_error("FAILED: "+label)

func complete(w) -> void:
    for i in range(700):
        F.work(w,1)
        if not w.construction.jobs.has("1"): return
    check(false,"bounded operation terminates")

func _initialize() -> void:
    var w = F.batch_b_world()
    var c = w.construction.catalogue
    for age in [1,2,3]:
        var types: Dictionary = {}
        for row in c.definitions.values():
            if int(row["primary_age"])==age and not bool(row["legacy"]): types[row["archetype_id"]] = true
        check(types.size()>=8,"eight distinct authored functional archetypes in age "+str(age))
    check(not w.occupations.has_capability(w,0,"bronze_working"),"calendar and starting inventory do not unlock bronze")
    check(not c.eligible(w,0,c.definition("bronze_forge"),{}),"forge requires actual bronze knowledge")
    check(w.construction.placement.validate(w,c.definition("water_lift"),Vector2i(45,40),0)=="water_source","dry-site irrigation blocked")
    check(w.construction.placement.validate(w,c.definition("ore_mine"),Vector2i(45,40),0)=="ore_deposit","mine requires finite discovered terrain deposit")
    var positions := {"charcoal_clamp":[30,10],"pottery_kiln":[35,10],"weaving_house":[40,10],"cordage_canopy":[30,16],"timber_workyard":[35,16],"grain_grinding_shelter":[40,16],"fenced_farmstead":[45,16],"water_lift":[24,29],"masonry_workyard":[30,22],"ore_mine":[18,26],"bronze_smelter":[35,22]}
    for id in positions:
        var cell: Array = positions[id]
        if id=="water_lift": w.occupations.grant_capability(w,0,"irrigation","teaching")
        var house: Dictionary = F.build(w,id,Vector2i(int(cell[0]),int(cell[1])))
        check(not house.is_empty(),"physical worker builds "+id)
        if house.is_empty(): quit(1); return
        check(w.inventory.ledger_ok(),"conserved construction "+id)
    check(F.stock(w,{"brick_wall_block":1}),"mason makes paid brick blocks through kiln and fuel chain")
    check(w.occupations.has_capability(w,0,"masonry"),"actual masonry work teaches local masonry")
    check(F.stock(w,{"bronze_ingot":1}),"qualified potter performs material-backed bronze experiment")
    check(w.occupations.has_capability(w,0,"bronze_working"),"successful ore and charcoal trial teaches local bronze")
    check(int(w.inventory.consumed.get("copper_ore",0))==3 and int(w.inventory.consumed.get("tin_ore",0))==1,"first ingot spends three copper units and one tin")
    check(F.stock(w,{"bronze_ingot":3}),"repeated real smelting trains smith and replenishes ingots")
    check(w.occupations.xp_for(w.citizens[0],"bronze_smith")>=160,"specialist practice earned from real workshop work")
    var more := {"bronze_forge":[40,22],"bronze_courtyard":[30,28],"bronze_granary":[35,28],"bronze_market":[40,28],"bronze_meeting_hall":[45,28]}
    # Controlled taught trade knowledge; actual round trips are covered by regional_economy_test.
    w.occupations.grant_capability(w,0,"caravan_trade","teaching")
    for id in more:
        var cell: Array = more[id]
        check(not F.build(w,id,Vector2i(int(cell[0]),int(cell[1]))).is_empty(),"physical worker builds "+id)
    check(F.stock(w,{"bronze_axe":1,"bronze_sickle":1}),"forge produces both real bronze tools")
    check(w.toolmaking._matching_serials("settlement:0","bronze_axe").size()==1,"bronze axe has exactly one persistent tool instance")
    var p: Dictionary = w.citizens[0]
    F.walk(w,p,w.capitals[0],1)
    w.toolmaking.try_equip(w,p,"wood")
    var serial: String = w.toolmaking.tool_for(w,p,"wood")
    check(serial!="" and str(w.toolmaking.instances.get(serial,{}).get("item_id",""))=="bronze_axe","wood worker borrows actual bronze axe at depot")
    if serial!="":
        var before: int = w.toolmaking.instances[serial]["condition"]
        w.toolmaking.wear(w,p,"wood")
        check(int(w.toolmaking.instances[serial]["condition"])==before-6,"bronze tool use incurs durable wear")
    check(not w.construction.resource_plan(w,0,{"copper_ore":10000})["viable"],"finite ore scarcity blocks unattainable production expansion")
    if serial!="":
        F.walk(w,p,w.capitals[0],1)
        check(w.inventory.transfer(w,"citizen:1","settlement:0",{"bronze_axe":1},1,serial),"worn axe returns with exact serial")
        var ingots: int = w.inventory.held("settlement:0","bronze_ingot")
        check(w.toolmaking.request_repair(w,1,serial),"qualified smith accepts paid durable-tool repair")
        for i in range(12):
            w.tick += 1
            w.ai_context.begin_tick(w)
            if not w.toolmaking.jobs.has("1"): break
            w.toolmaking._do_job(w,p,w.citizen_ai_by_id["1"])
        check(int(w.toolmaking.instances[serial]["condition"])==int(w.toolmaking.instances[serial]["max_condition"]) and w.inventory.held("settlement:0","bronze_ingot")==ingots-1,"repair restores original tool and spends one real ingot")
    grain(w)
    irrigation(w)
    check(w.inventory.ledger_ok() and w.food.ledger_ok(),"all new production and service ledgers conserved")
    var copy = World.from_snapshot(Store.decode(w.prepare_save_bytes()))
    check(copy!=null and copy.snapshot()==w.snapshot(),"all new buildings, irrigation and serialised bronze tools round-trip")
    if copy!=null:
        F.work(w,25); F.work(copy,25)
        check(w.snapshot()==copy.snapshot(),"saved operational world replays deterministically")
    check(w.construction.houses.filter(func(h: Dictionary)->bool:return str(h["definition_id"])=="cordage_canopy").size()==1,"Stone Age workshop remains after Bronze Age knowledge")
    autonomous()
    print("BATCH_B_CHECKS=",checks," FAILURES=",failures)
    if failures==0: print("ARCHITECTURE_BATCH_B_TESTS_PASSED")
    quit(0 if failures==0 else 1)

func house_for(w,id: String) -> Dictionary:
    for h in w.construction.houses:
        if str(h["definition_id"])==id: return h
    return {}

func grain(w) -> void:
    var p: Dictionary = w.citizens[0]
    # Explicit finite opening food balance, not claimed as an autonomous harvest.
    w.food.store(0)["grain"] = 20
    w.food.produced["grain"] = int(w.food.produced["grain"])+20
    var h := house_for(w,"grain_grinding_shelter")
    var process: Dictionary = w.construction.catalogue.definition("grain_grinding_shelter")["production"][0]
    check(w.construction.operations.start(w.construction,w,p,h,process),"grain processing uses normal physical work order")
    complete(w)
    check(w.inventory.held("settlement:0","grain_ration")==1 and int(w.food.store(0)["grain"])==18,"two food grains become one returned ration with no duplicated seed")
    F.walk(w,p,w.capitals[0],1)
    p["hunger"] = 70
    check(w.food.take_ration(w,p) and int(p["hunger"])<70 and w.inventory.held("settlement:0","grain_ration")==0,"prepared ration has actual consumption benefit")
    var smith := house_for(w,"bronze_smelter")
    var bronze: Dictionary = w.construction.catalogue.definition("bronze_smelter")["production"][0]
    F.walk(w,p,Vector2i(int(smith["x"]),int(smith["y"])+1))
    var old: int = w.inventory.held("citizen:1","bronze_ingot")
    check(not w.inventory.craft_in_building(w,1,smith,bronze) and w.inventory.held("citizen:1","bronze_ingot")==old,"no ingot or knowledge awarded from absent real input cargo")

func irrigation(w) -> void:
    var p: Dictionary = w.citizens[0]
    var h := house_for(w,"water_lift")
    var service: Dictionary = w.construction.catalogue.definition("water_lift")["services"][0]
    check(F.stock(w,{"plant_fibre":1}),"lift upkeep gathered from finite environment")
    check(w.construction.operations.start(w.construction,w,p,h,service),"trained keeper starts paid lift service")
    F.work(w,4)
    var mid = World.from_snapshot(Store.decode(w.prepare_save_bytes()))
    check(mid!=null,"in-progress service hauling survives compressed save")
    complete(w)
    if mid!=null:
        complete(mid)
        check(mid.snapshot()==w.snapshot(),"mid-service save restores exact paid work and allocations")
    var bad: Dictionary = w.snapshot().duplicate(true)
    for b in bad["construction"]["houses"]:
        if str(b["definition_id"])=="water_lift": b["irrigation_slots"] = 999
    check(World.from_snapshot(bad)==null,"save validator rejects fabricated irrigation capacity")
    check(int(h.get("irrigation_slots",0))==2 and int(h.get("irrigation_until",0))>w.tick,"one paid work cycle grants two time-limited water allocations")
    check(w.construction.operations.irrigate_sowing(w,0,Vector2i(24,32)) and w.construction.operations.irrigate_sowing(w,0,Vector2i(24,32)) and not w.construction.operations.irrigate_sowing(w,0,Vector2i(24,32)),"water allocations finite and cannot be applied three times")
    w.construction.lifecycle.abandon(w.construction,w,int(h["id"]),true)
    check(not w.construction.operations.can_run(w,p,h,service),"abandoned water infrastructure stops service")

func autonomous() -> void:
    var w = F.world()
    check(not F.build(w,"communal_longhouse",Vector2i(28,30)).is_empty(),"planner scenario has finite residential capacity")
    w.food.store(0)["grain"] = 32
    w.food.produced["grain"] = 32
    w.settlements.rebuild_membership(w)
    check(w.construction.support_project(w,0),"planner proposes a real specialist supply bottleneck")
    var first: Dictionary = w.construction.project_for(0)
    check(str(first.get("definition_id",""))=="charcoal_clamp" and not first.get("placement_reason",{}).get("reason","").is_empty(),"fuel proposal contains valid site and explainable reason")
    for i in range(1800):
        w.tick += 1
        w.ai_context.begin_tick(w)
        w.construction.prune(w)
        for person in w.citizens:
            w.construction.work_step(w,person,w.citizen_ai_by_id[str(person["id"])])
        if w.construction.project_for(0).is_empty(): break
    var builders := 0
    for task in w.construction.jobs.values():
        if str(task["kind"])=="build": builders += 1
    check(builders<=1 and w.inventory.ledger_ok(),"bounded builders leave separate workers for finite material gathering")
    check(w.construction.support_project(w,0),"one production facility does not suppress other specialist archetypes")
    var second: Dictionary = w.construction.project_for(0)
    check(str(second.get("definition_id",""))=="cordage_canopy","planner chooses missing cordage work instead of another charcoal clamp")
    var clone = World.from_snapshot(w.snapshot())
    check(clone!=null and clone.snapshot()==w.snapshot(),"autonomous proposal, priorities and site provenance persist")
