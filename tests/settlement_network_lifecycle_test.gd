extends SceneTree
const World = preload("res://scripts/simulation.gd")
const Nav = preload("res://scripts/ai/navigation.gd")
const SaveStore = preload("res://scripts/ai/save_store.gd")
var checks := 0
var failed := 0

func check(value: bool, label: String) -> void:
    checks += 1
    if value: print("PASS: "+label)
    else:
        failed += 1
        push_error("FAILED: "+label)

func fixture():
    var w = World.new(911,false)
    for y in range(22,76):
        for x in range(8,76): w.set_terrain_cell(x,y,World.MEADOW)
    w.capitals[0] = Vector2i(20,40)
    w.settlements.ensure_legacy(w)
    var ids: Array = [0]
    for center in [Vector2i(36,40),Vector2i(52,40)]: ids.append(w.settlements.register_camp(w,0,center,0))
    for sid in ids:
        var center: Vector2i = w.settlements.center(w,int(sid))
        w.settlements.get_record(int(sid))["status"] = "active"
        for dy in [-3,0,3]:
            w.set_terrain_cell(center.x+1,center.y+dy,World.FOREST)
            w.set_terrain_cell(center.x-1,center.y+dy,World.MOUNTAIN)
        for i in range(6):
            w.add_citizen(center.x,center.y,0)
            w.citizens[-1]["settlement_id"] = int(sid)
    w.ai_context.begin_tick(w)
    w.settlements.rebuild_membership(w)
    return w

func tick(w) -> void:
    w.tick += 1
    w.ai_context.begin_tick(w)

func worker(w, sid: int) -> Dictionary:
    for person in w.citizens:
        if w.settlements.sid(person)==sid and not w.lifecycle.is_dependent(person): return person
    return {}

func walk(w, person: Dictionary, target: Vector2i) -> bool:
    var mind: Dictionary = w.citizen_ai_by_id[str(person["id"])]
    mind["route"] = []
    mind["next_path_tick"] = w.tick
    for i in range(150):
        tick(w)
        if w.construction.walk(w,person,mind,target): return true
    return false

func supply(w, sid: int, good: String, number: int) -> bool:
    var person := worker(w,sid)
    var mind: Dictionary = w.citizen_ai_by_id[str(person["id"])]
    for i in range(number):
        var source: Dictionary = w.construction.source_for(w,person,good)
        if source.is_empty(): return false
        var cell := Vector2i(int(source["source"][0]),int(source["source"][1]))
        if not walk(w,person,Vector2i(int(source["target"][0]),int(source["target"][1]))): return false
        if not w.inventory.extract(w,int(person["id"]),good,cell): return false
        if not walk(w,person,w.settlements.center(w,sid)): return false
        if not w.inventory.transfer(w,"citizen:"+str(person["id"]),"settlement:"+str(sid),{good:1},int(person["id"])): return false
    return true

func build(w, sid: int, definition: String) -> Dictionary:
    var row: Dictionary = w.construction.catalogue.definition(definition)
    for good in row["materials"]:
        var needed: int = int(row["materials"][good])-w.inventory.available("settlement:"+str(sid),str(good))
        if needed>0 and not supply(w,sid,str(good),needed): return {}
    var request: Dictionary = w.construction.request_construction(w,{"settlement_id":sid,"function":row["function"],"definition_id":definition})
    if not request.get("ok",false): return {}
    for i in range(500):
        tick(w)
        w.construction.prune(w)
        for person in w.citizens:
            if w.settlements.sid(person)==sid: w.construction.work_step(w,person,w.citizen_ai_by_id[str(person["id"])])
        var house: Dictionary = w.construction.building_by_id(int(request["site_id"]))
        if not house.is_empty(): return house
    return {}

func _initialize() -> void:
    var w = fixture()
    var second := 2
    var third := 3
    var system = w.regional_economy
    system._plan_connection(w,0,second)
    system._plan_connection(w,second,third)
    check(system.links.size()==2 and not system.connected(w,0,second),"arbitrary settlement links plan real, initially incomplete roads")
    for i in range(600):
        tick(w)
        system.on_tick(w)
        for person in w.citizens: system.work_step(w,person,w.citizen_ai_by_id[str(person["id"])])
        if system.connected(w,0,second) and system.connected(w,second,third) and system.road_queue.is_empty(): break
    check(system.connected(w,0,second) and system.connected(w,second,third),"citizens build a physical three-settlement road network")
    check(supply(w,second,"wood",5) and supply(w,third,"stone",5),"satellites accumulate real finite export surpluses")
    var proposer: Dictionary = system._trade_offer(w,second)
    check(not proposer.is_empty() and int(proposer.get("other",-1))==third,"independent same-nation settlements discover reciprocal shortages")
    var merchant := worker(w,second)
    check(walk(w,merchant,w.settlements.center(w,second)),"merchant reaches its own local pickup store")
    var m: Dictionary = w.citizen_ai_by_id[str(merchant["id"])]
    var saw_cargo := false
    for i in range(240):
        tick(w)
        system._trading_work(w,merchant,m)
        saw_cargo = saw_cargo or w.inventory.held("citizen:"+str(merchant["id"]),"wood")>0
        if system.completed_trades>0: break
    check(saw_cargo and system.completed_trades>0,"merchant physically carries exports, barters and returns imports")
    check(w.inventory.held("settlement:2","stone")>0 and w.inventory.held("settlement:3","wood")>0,"barter settles both satellite inventories atomically")
    check(w.inventory.ledger_ok(),"arbitrary network trade conserves every material")
    var restored = World.from_snapshot(JSON.parse_string(JSON.stringify(w.snapshot())))
    check(restored!=null,"multi-link road network and trade history survive JSON restoration")
    if restored!=null:
        check(restored.regional_economy.snapshot()==system.snapshot(),"arbitrary endpoint IDs, route states and price boards persist exactly")
        var replay = World.from_snapshot(w.snapshot())
        for i in range(30):
            replay.step()
            restored.step()
        check(replay.snapshot()==restored.snapshot(),"multi-settlement AI, road work and markets replay deterministically after JSON restoration")
    var aid = fixture()
    var aid_system = aid.regional_economy
    aid_system._plan_connection(aid,second,third)
    for i in range(400):
        tick(aid)
        for person in aid.citizens: aid_system.work_step(aid,person,aid.citizen_ai_by_id[str(person["id"])])
        if aid_system.connected(aid,second,third) and aid_system.road_queue.is_empty(): break
    var forager: Dictionary = aid.citizens[7]
    var fm: Dictionary = aid.citizen_ai_by_id[str(forager["id"])]
    for i in range(500):
        tick(aid)
        aid.food.work_step(aid,forager,fm)
        if aid.food.total(aid.food.store(second))>=18 and not aid.food.jobs.has(str(forager["id"])): break
    check(aid.food.total(aid.food.store(second))>=18,"exporting settlement gathers a genuine food surplus")
    var aid_merchant := worker(aid,second)
    var amind: Dictionary = aid.citizen_ai_by_id[str(aid_merchant["id"])]
    var saw_food_cargo := false
    var saved_cargo := false
    for i in range(400):
        tick(aid)
        aid_system._trading_work(aid,aid_merchant,amind)
        if aid.food.total(aid.food.travel_cargo.get(str(aid_merchant["id"]),{}))>0:
            saw_food_cargo = true
            if not saved_cargo:
                var carrying = World.from_snapshot(JSON.parse_string(JSON.stringify(aid.snapshot())))
                check(carrying!=null,"food shipment and its in-flight merchant restore together")
                saved_cargo = true
        if aid_system.completed_relief>0: break
    check(saw_food_cargo and aid_system.completed_relief>0 and aid.food.total(aid.food.store(third))>0,"food shortage creates a physical inter-settlement relief shipment")
    check(aid.food.ledger_ok() and aid.inventory.ledger_ok(),"material barter and food imports preserve their separate authorities")
    var warehouse := build(w,second,"local_storage")
    check(not warehouse.is_empty(),"universal construction physically builds a local storehouse")
    var yard := build(w,third,"tool_area")
    check(not yard.is_empty() and w.occupations.facility_present(w,third,"tool_area"),"satellite workshop is an actual material-paid building")
    if not yard.is_empty():
        check(supply(w,third,"flint",1) and supply(w,third,"stone",1),"local experimentation inputs arrive physically")
        var artisan := worker(w,third)
        var am: Dictionary = w.citizen_ai_by_id[str(artisan["id"])]
        w.toolmaking._begin(w,artisan,am,"experiment",{"remaining":3})
        for i in range(160):
            tick(w)
            w.toolmaking.work_step(w,artisan,am)
            if w.occupations.has_capability(w,third,"stone_working") and not w.toolmaking.jobs.has(str(artisan["id"])): break
        check(w.occupations.has_capability(w,third,"stone_working"),"satellite discovers stoneworking through physical workstation experiments")
        check(not w.occupations.has_capability(w,second,"stone_working"),"technology is not granted to every town in the nation")
    if not warehouse.is_empty():
        check(supply(w,second,"wood",1),"secondary-store stock is physically replenished")
        var holder := "store:"+str(warehouse["id"])
        var courier := worker(w,second)
        check(walk(w,courier,w.settlements.center(w,second)),"courier physically picks up storage stock")
        check(w.inventory.transfer(w,"settlement:2","citizen:"+str(courier["id"]),{"wood":1},int(courier["id"])),"real cargo leaves the central depot")
        check(walk(w,courier,Vector2i(int(warehouse["x"]),int(warehouse["y"]))),"courier travels to secondary storage")
        check(w.inventory.transfer(w,"citizen:"+str(courier["id"]),holder,{"wood":1},int(courier["id"])),"secondary storage owns independently located real stock")
        var wrong := worker(w,third)
        check(not w.inventory._access(w.inventory._holder(w,holder),w.inventory._holder(w,"citizen:"+str(wrong["id"])),true),"foreign-local storage access denied even for the same nation")
        for i in range(120):
            tick(w)
            w.local_logistics.work_step(w,courier,w.citizen_ai_by_id[str(courier["id"])])
            if w.inventory.held(holder,"wood")==0 and not w.local_logistics.jobs.has(str(courier["id"])): break
        check(w.inventory.held("settlement:2","wood")>0 and w.inventory.held(holder,"wood")==0,"autonomous local courier returns secondary-store materials through real transport")
        w.inventory.transfer(w,"settlement:2","citizen:"+str(courier["id"]),{"wood":1},int(courier["id"]))
        walk(w,courier,Vector2i(int(warehouse["x"]),int(warehouse["y"])))
        w.inventory.transfer(w,"citizen:"+str(courier["id"]),holder,{"wood":1},int(courier["id"]))
        w.construction.lifecycle.remove(w.construction,w,int(warehouse["id"]),false,"test_destruction")
        check(w.inventory.ledger_ok() and not w.inventory.balances.has(holder),"destroyed storage leaves physical salvage without a phantom refund")
    # Decline moves a real household to spare housing in an existing community.
    var destination_home := build(w,third,"primitive_shelter")
    var extra_home := build(w,third,"primitive_shelter")
    check(not destination_home.is_empty() and not extra_home.is_empty() and w.settlements.housing(w,third)>w.settlements.population(third),"evacuation destination builds actual spare housing")
    var source_record: Dictionary = w.settlements.get_record(second)
    source_record["last_evaluation"] = w.tick-200
    for person in w.citizens:
        if w.settlements.sid(person)==second: person["hunger"] = 80
    w.settlements.rebuild_membership(w)
    w.settlement_lifecycle.evaluate(w,second,w.settlement_planner.survey(w,w.settlements.center(w,second)))
    check(str(source_record["status"])=="struggling" and w.founding.active_count()>0,"sustained deprivation triggers a bounded physical household evacuation")
    var emigrant: Dictionary = {}
    for journey in w.founding.expeditions.values():
        if str(journey["phase"])=="travel" and int(journey.get("destination",-1))==third:
            emigrant = w.ai_context.people[int(journey["members"][0])]
            break
    if emigrant.is_empty(): emigrant = worker(w,second)
    var previous := Vector2i(int(emigrant["x"]),int(emigrant["y"]))
    for i in range(100):
        tick(w)
        w.founding.tick(w)
        for person in w.citizens:
            if w.founding.assignments.has(str(person["id"])):
                w.founding.travel_step(w,person,w.citizen_ai_by_id[str(person["id"])])
        if w.settlements.sid(emigrant)==third: break
    check(w.settlements.sid(emigrant)==third and Nav.manhattan(previous,Vector2i(int(emigrant["x"]),int(emigrant["y"])))>8,"evacuation changes residence only after actual travel to the receiving town")
    # An empty settlement keeps its buildings/history, then recovers on real return.
    var shelter := build(w,third,"primitive_shelter")
    check(not shelter.is_empty(),"recovery scenario has an actual shelter")
    for person in w.citizens:
        if w.settlements.sid(person)==third:
            person["hp"] = 0
            w.inventory.drop_on_death(w,person)
    w.settlements.rebuild_membership(w)
    var record: Dictionary = w.settlements.get_record(third)
    record["last_evaluation"] = w.tick-300
    w.settlement_lifecycle.evaluate(w,third,w.settlement_planner.survey(w,w.settlements.center(w,third)))
    check(str(record["status"])=="abandoned","population loss causes settlement abandonment")
    check(not shelter.is_empty() and bool(shelter.get("abandoned",false)),"abandoned physical buildings and historical records survive")
    w.add_citizen(52,40,0)
    w.ai_context.begin_tick(w)
    w.settlements.rebuild_membership(w)
    w.settlement_lifecycle.evaluate(w,third,w.settlement_planner.survey(w,Vector2i(52,40)))
    check(str(record["status"])=="active" and w.settlements.sid(w.citizens[-1])==third,"actual return to safe land recovers the original settlement identity")
    check(w.inventory.ledger_ok() and w.food.ledger_ok(),"network, industry, destruction and recovery retain both ledgers")
    w.construction.prune(w)
    w.toolmaking.prune(w)
    w.regional_economy.on_tick(w)
    w.local_logistics.tick(w)
    var copy = World.from_snapshot(SaveStore.decode(w.prepare_save_bytes()))
    check(copy!=null,"compressed save restores the full settlement lifecycle")
    print("SETTLEMENT NETWORK LIFECYCLE: ",checks," checks, ",failed," failures")
    quit(0 if failed==0 else 1)
