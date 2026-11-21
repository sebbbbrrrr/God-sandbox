extends SceneTree
const World = preload("res://scripts/simulation.gd")
const SaveStore = preload("res://scripts/ai/save_store.gd")
var ok := true
var checks := 0

func check(value: bool, message: String) -> void:
    checks += 1
    if value:
        print("PASS: " + message)
    else:
        ok = false
        push_error("FAILED: " + message)

func _initialize() -> void:
    placement_and_eligibility()
    reservations_and_logistics()
    simultaneous_and_shortages()
    interruption_and_persistence()
    lifecycle()
    transitions()
    autonomy()
    print("UNIVERSAL_CONSTRUCTION_CHECKS=", checks)
    if ok:
        print("UNIVERSAL_CONSTRUCTION_TESTS_PASSED")
    quit(0 if ok else 1)

func village(count: int = 8):
    var w = World.new(6001, false)
    for y in range(7, 27):
        for x in range(7, 27):
            w.set_terrain_cell(x, y, World.MEADOW)
    w.set_terrain_cell(15, 16, World.FOREST)
    w.set_terrain_cell(17, 16, World.MOUNTAIN)
    w.capitals[0] = Vector2i(16, 16)
    for i in range(count):
        w.add_citizen(16, 16, 0)
    w.ai_context.begin_tick(w)
    return w

func site(w, x: int = 16, y: int = 18) -> Dictionary:
    var result: Dictionary = w.construction.request_construction(w, {"settlement_id": 0, "function": "shelter", "definition_id": "primitive_shelter", "location": [x,y]})
    return w.construction.site_by_id(int(result.get("site_id", 0)))

# Legitimate fixture resources are harvested through the actual finite-node API.
func stock(w, wood: int = 3, stone: int = 1) -> void:
    var p: Dictionary = w.citizens[0]
    var mind: Dictionary = w.citizen_ai_by_id[str(p["id"])]
    mind["route"] = []
    for attempt in range(30):
        w.tick += 1
        w.ai_context.begin_tick(w)
        if w.construction.walk(w,p,mind,w.capitals[0]):
            break
    for item in ["wood", "stone"]:
        var count: int = wood if item == "wood" else stone
        var source := Vector2i(15,16) if item == "wood" else Vector2i(17,16)
        while count > 0:
            var batch: int = mini(3, count)
            check(w.inventory.extract(w, int(p["id"]), item, source, batch), "fixture extracts finite " + item)
            check(w.inventory.transfer(w, "citizen:" + str(p["id"]), "settlement:0", {item:batch}, int(p["id"])), "fixture deposits physical " + item)
            count -= batch

func work(w, person: Dictionary, steps: int) -> void:
    for i in range(steps):
        w.tick += 1
        w.ai_context.begin_tick(w)
        w.construction.prune(w)
        w.construction.work_step(w, person, w.citizen_ai_by_id[str(person["id"])])

func placement_and_eligibility() -> void:
    var w = village()
    var engine = w.construction
    var row: Dictionary = engine.catalogue.definition("primitive_shelter")
    check(engine.catalogue.validate(w.inventory.catalogue.items).is_empty(), "building schema, stage totals and D1 item references validate")
    check(engine.catalogue.definitions.size() == 37 and row["supported_ages"].size() == 11, "legacy and authored early-age definitions share the eleven-era framework")
    check(engine.placement.validate(w,row,Vector2i(16,18),0) == "", "valid meadow footprint")
    check(engine.placement.validate(w,row,Vector2i(-1,18),0) != "", "out-of-map footprint rejected")
    check(engine.placement.validate(w,row,Vector2i(17,16),0) == "terrain", "mountain placement rejected")
    check(engine.placement.validate(w,row,Vector2i(5,5),0) == "terrain", "water placement rejected")
    var first: Dictionary = site(w)
    check(not first.is_empty() and engine.occupied(16,18), "site immediately owns persistent footprint")
    check(not engine.request_construction(w,{"settlement_id":0,"location":[16,18]})["ok"], "overlapping project rejected")
    check(not engine.evaluate_request(w,{"settlement_id":0,"require_stock":true})["ok"], "strict request refuses missing stock")
    check(not engine.catalogue.eligible(w,0,engine.catalogue.definition("timber_hut")), "worked-timber design requires actual local knowledge")
    w.tick = 100000
    check(not engine.catalogue.eligible(w,0,engine.catalogue.definition("timber_hut")), "calendar advancement cannot unlock designs")
    var advanced: Dictionary = row.duplicate(true)
    advanced["skills"] = {"shelter_builder":3}
    check(not engine.catalogue.worker_eligible(w,w.citizens[0],advanced), "advanced skill gate excludes novice worker")
    var regional: Dictionary = row.duplicate(true)
    regional["variations"]["climates"] = ["cold"]
    check(not engine.catalogue.eligible(w,0,regional) and engine.catalogue.eligible(w,0,regional,{"climates":"cold"}), "explicit regional rules constrain eligibility")
    var child: Dictionary = w.citizens[0].duplicate(true)
    child["life_stage"] = "child"
    check(not engine.catalogue.worker_eligible(w,child,row), "children cannot perform adult building work")
    var empty = village(0)
    check(not empty.construction.evaluate_request(empty,{"settlement_id":0})["ok"], "no worker means construction cannot start")
    var hut: Dictionary = engine.catalogue.definition("timber_hut")
    check(engine.placement.footprint(hut,Vector2i(1,1),1) == [Vector2i(1,1),Vector2i(1,2)], "orientation rotates multi-cell footprint")
    w.set_terrain_cell(16,18,World.OCEAN)
    check(first["paused"] and first["pause_reason"] == "terrain", "terrain painting pauses physical site safely")
    w.set_terrain_cell(16,18,World.MEADOW)
    engine.prune(w)
    check(not first["paused"], "restored terrain resumes paused project")

func reservations_and_logistics() -> void:
    var w = village()
    stock(w)
    var a: Dictionary = site(w)
    var b: Dictionary = site(w,18,18)
    var inv = w.inventory
    check(inv.available("settlement:0","wood") == 0, "first project atomically reserves real resources")
    check(not inv.reserve("competing","settlement:0",{"wood":1}), "second project cannot double-reserve the same timber")
    check(not inv.transfer(w,"settlement:0","citizen:2",{"wood":1},2), "manual withdrawal cannot steal reserved construction stock")
    check(not inv.consume(w,"settlement:0",{"wood":1},1,"competing"), "other consumers respect reservations")
    var p: Dictionary = w.citizens[0]
    work(w,p,1)
    check(inv.held("citizen:1","wood") == 1 and inv.held("site:"+str(a["id"]),"wood") == 0, "pickup produces carrier custody, no remote site delivery")
    check(not inv.transfer(w,"citizen:1","site:"+str(a["id"]),{"wood":1},1), "remote delivery is rejected")
    work(w,p,2)
    check(inv.held("site:"+str(a["id"]),"wood") == 1 and int(a["delivered"]["wood"]) == 1, "worker arrival delivers partial shipment into site inventory")
    check(int(a["progress"]) == 1 and not a["consumed"].has("wood"), "site preparation performs real labour before structural consumption")
    check(inv.ledger_ok(), "partial delivery conserves all item units")
    check(w.construction.cancel(w,int(b["id"])) and not w.construction.occupied(18,18), "cancellation frees reserved footprint")
    check(w.construction.cancel(w,int(a["id"])), "partial construction cancellation succeeds")
    check(inv.held("ground:"+str(w.index_of(16,18)),"wood") == 1 and inv.available("settlement:0","wood") == 2, "unused delivery stays at site; unused depot reservations are released")
    work(w,p,8)
    check(inv.ledger_ok() and inv.reservations.is_empty(), "cancelled worker returns cargo without duplication or orphan reservations")

func simultaneous_and_shortages() -> void:
    var w = village()
    stock(w,6,2)
    var first: Dictionary = site(w)
    var second: Dictionary = site(w,18,18)
    for i in range(70):
        work(w,w.citizens[0],1)
        work(w,w.citizens[1],1)
    check(w.construction.houses.size() == 2 and w.construction.projects.is_empty(), "two concurrent projects complete through separate arriving workers")
    check(w.inventory.ledger_ok() and w.inventory.reservations.is_empty(), "simultaneous consumption never double-spends reservations")
    var short = village()
    var short_site: Dictionary = site(short)
    work(short,short.citizens[0],35)
    check(short.construction.houses.is_empty() and int(short_site["progress"]) == 1, "missing resources block structural labour and completion")
    var waiting = village()
    var no_arrival: Dictionary = site(waiting)
    for i in range(40):
        waiting.tick += 1
        waiting.construction.prune(waiting)
    check(int(no_arrival["progress"]) == 0, "simulation time alone never substitutes for an arriving worker")
    var cancel_transit = village()
    stock(cancel_transit)
    var cancelled: Dictionary = site(cancel_transit)
    work(cancel_transit,cancel_transit.citizens[0],1)
    check(cancel_transit.construction.cancel(cancel_transit,int(cancelled["id"])), "cancel while materials are carried succeeds")
    work(cancel_transit,cancel_transit.citizens[0],1)
    check(cancel_transit.inventory.held("settlement:0","wood") == 3 and cancel_transit.inventory.held("settlement:0","stone") == 1 and cancel_transit.inventory.ledger_ok(), "in-transit cancellation physically returns the exact reserved bundle")
    var invalid: Dictionary = waiting.snapshot()
    invalid["construction"]["projects"][0]["delivered"]["wood"] = 3
    check(World.from_snapshot(invalid) == null, "save with fabricated material deliveries is rejected")

func interruption_and_persistence() -> void:
    var w = village()
    stock(w)
    var a: Dictionary = site(w)
    var p: Dictionary = w.citizens[0]
    work(w,p,3)
    var snapshot: Dictionary = w.snapshot()
    var restored = World.from_snapshot(snapshot)
    check(restored != null and restored.snapshot() == snapshot, "save after partial delivery restores exact sites, tasks and reservations")
    var json_world = World.from_snapshot(JSON.parse_string(JSON.stringify(snapshot)))
    check(json_world != null, "actual JSON text round-trip restores conserved inventory")
    var decoded: Variant = SaveStore.decode(w.prepare_save_bytes())
    var binary = World.from_snapshot(decoded)
    check(binary != null and binary.snapshot() == snapshot, "compressed active-site save restores exact state")
    if restored != null:
        for i in range(50):
            work(w,p,1)
            work(restored,restored.citizens[0],1)
        check(w.snapshot() == restored.snapshot() and w.construction.houses.size() == 1, "resumed shipments/stages replay deterministically to completion")
    var dead = village()
    stock(dead)
    var project: Dictionary = site(dead)
    work(dead,dead.citizens[0],1)
    dead.citizens[0]["hp"] = 0
    dead.construction.prune(dead)
    check(project["reserved"] == 0 and not dead.construction.jobs.has("1") and dead.inventory.ledger_ok(), "dead carrier releases assignment and drops physical cargo")
    check(dead.inventory.held("ground:"+str(dead.index_of(16,16)),"wood") == 1, "interrupted cargo remains at actual death location")
    work(dead,dead.citizens[1],1)
    check(int(project["reserved"]) == 2, "another eligible citizen recovers abandoned worker assignment")
    var interrupted = village()
    stock(interrupted)
    site(interrupted)
    work(interrupted,interrupted.citizens[0],1)
    interrupted.construction.tasks.interrupt(interrupted.construction,interrupted,"1")
    work(interrupted,interrupted.citizens[0],1)
    check(interrupted.inventory.held("citizen:1","wood") == 0 and interrupted.inventory.ledger_ok(), "living interrupted carrier physically returns collected goods")
    var old: Dictionary = village().snapshot()
    old["construction"] = {"version":1,"houses":[{"id":9,"nation":0,"x":16,"y":18,"capacity":6,"built_tick":25}],"projects":[],"jobs":{},"stockpiles":[{},{}],"depleted":{},"next_building_id":10}
    var migrated = World.from_snapshot(old)
    check(migrated != null and int(migrated.construction.houses[0]["built_tick"]) == 25 and int(migrated.construction.houses[0]["condition"]) == 100, "legacy houses migrate without losing construction dates or inventing salvage")
    var old_active = village()
    stock(old_active)
    check(old_active.inventory.transfer(old_active,"settlement:0","citizen:1",{"wood":3,"stone":1},1), "old-save fixture has legitimately collected builder cargo")
    var legacy_active: Dictionary = old_active.snapshot()
    legacy_active["construction"] = {"version":1,"houses":[],"projects":[{"id":7,"nation":0,"x":16,"y":18,"progress":3,"reserved":1}],"jobs":{"1":{"kind":"build","nation":0,"project_id":7,"phase":"site","wood":3,"stone":1}},"stockpiles":[{},{}],"depleted":old_active.construction.depleted.duplicate(true),"next_building_id":8}
    var migrated_active = World.from_snapshot(legacy_active)
    check(migrated_active != null and int(migrated_active.construction.projects[0]["progress"]) == 3, "legacy active projects preserve earned work and actual carrier custody")
    if migrated_active != null:
        work(migrated_active,migrated_active.citizens[0],25)
        check(migrated_active.construction.houses.size() == 1 and migrated_active.inventory.ledger_ok(), "legacy builder resumes and consumes each carried resource exactly once")
    var unreachable = village()
    stock(unreachable)
    var isolated: Dictionary = site(unreachable,22,22)
    for y in range(20,25):
        for x in range(20,25):
            if x in [20,24] or y in [20,24]:
                unreachable.set_terrain_cell(x,y,World.OCEAN)
    work(unreachable,unreachable.citizens[0],100)
    check(isolated["pause_reason"] == "unreachable" and int(isolated["progress"]) == 0 and unreachable.inventory.ledger_ok(), "unreachable island site pauses without work or teleportation")

func completed_world():
    var w = village()
    stock(w)
    site(w)
    work(w,w.citizens[0],60)
    return w

func lifecycle() -> void:
    var w = completed_world()
    var e = w.construction
    check(e.houses.size() == 1 and e.projects.is_empty(), "three physical stages complete a dwelling")
    if e.houses.is_empty():
        return
    var house: Dictionary = e.houses[0]
    var id: int = int(house["id"])
    check(int(house["capacity"]) == 6 and house["materials"] == {"wood":3,"stone":1}, "dwelling functionality and material provenance persist")
    w.households.reconcile(w)
    check(w.households.occupancy(w,id) > 0, "existing households occupy genuine constructed beds")
    check(e.lifecycle.damage(e,w,id,30,"test_fire") and int(house["condition"]) == 70, "external damage interface changes structural condition")
    stock(w,1,0)
    check(e.lifecycle.request_action(e,w,id,"repair"), "repair creates a paid worker task")
    # Repair is scheduled only when no building project claims the worker.
    work(w,w.citizens[0],20)
    check(int(house["condition"]) == 95 and int(w.inventory.consumed.get("wood",0)) == 4, "real travel, repair labour and wood consumption restore structure")
    check(e.lifecycle.abandon(e,w,id) and int(house["capacity"]) == 0, "abandonment disables dwelling capacity")
    w.households.reconcile(w)
    check(w.households.occupancy(w,id) == 0, "abandonment clears household residency")
    check(e.lifecycle.abandon(e,w,id,false), "historical dwelling may be reoccupied")
    var saved: Dictionary = w.snapshot()
    var restored = World.from_snapshot(saved)
    check(restored != null and restored.construction.houses[0] == house, "condition, provenance and lifecycle histories survive save")
    check(e.lifecycle.request_action(e,w,id,"demolish"), "controlled demolition schedules labour")
    work(w,w.citizens[0],20)
    check(e.houses.is_empty() and not e.occupied(16,18) and w.at(16,18) == World.MEADOW, "worker demolition releases terrain and physical footprint")
    check(w.inventory.held("ground:"+str(w.index_of(16,18)),"wood") == 1 and w.inventory.ledger_ok(), "defined 50-percent salvage returns exactly one embodied timber locally")
    check(not e.lifecycle.remove(e,w,id,true,"duplicate"), "repeated demolition cannot duplicate salvage")

func transitions() -> void:
    var w = completed_world()
    var e = w.construction
    var original: Dictionary = e.houses[0].duplicate(true)
    var id: int = int(original["id"])
    check(not e.lifecycle.begin_transition(e,w,id,"timber_hut","upgrade"), "upgrade cannot bypass actual construction knowledge")
    w.occupations.grant_capability(w,0,"stone_working","experiment")
    check(e.lifecycle.begin_transition(e,w,id,"timber_hut","upgrade"), "eligible upgrade creates a physical staged project")
    check(e.cancel(w,id) and e.building_by_id(id) == original, "cancelled renovation restores the original historical building")
    check(e.lifecycle.begin_transition(e,w,id,"timber_hut","conversion"), "conversion follows declared path through the same engine")
    stock(w,3,2)
    work(w,w.citizens[0],30)
    # Further wood must come from another finite source, not from an opening balance.
    w.set_terrain_cell(16,15,World.FOREST)
    var person: Dictionary = w.citizens[1]
    for i in range(3):
        check(w.inventory.extract(w,int(person["id"]),"wood",Vector2i(16,15),1) and w.inventory.transfer(w,"citizen:2","settlement:0",{"wood":1},2), "conversion harvests additional real timber")
    work(w,w.citizens[0],80)
    var converted: Dictionary = e.building_by_id(id)
    check(not converted.is_empty() and converted["definition_id"] == "timber_hut" and int(converted["built_tick"]) == int(original["built_tick"]) and int(converted["capacity"]) == 8, "conversion preserves identity and original date while changing function capacity")
    check(w.inventory.ledger_ok(), "renovation and conversion preserve physical material conservation")

func autonomy() -> void:
    var a = village(20)
    var b = village(20)
    var saw_site := false
    var saw_shipment := false
    var saw_stage := false
    for i in range(650):
        a.step()
        b.step()
        if not a.construction.projects.is_empty():
            saw_site = true
            var active: Dictionary = a.construction.projects[0]
            saw_stage = saw_stage or int(active["stage"]) >= 1
            saw_shipment = saw_shipment or not active["delivered"].is_empty()
    check(saw_site and saw_shipment and saw_stage and a.construction.houses.any(func(h): return int(h.get("capacity",0)) >= 6), "actual world.step autonomously requests, gathers, transports and constructs shelter")
    check(a.inventory.ledger_ok() and not a.inventory.minted.is_empty(), "autonomous demo uses legitimate finite resources")
    check(a.snapshot() == b.snapshot(), "identical autonomous worlds remain deterministic")
    var loaded = World.from_snapshot(a.snapshot())
    check(loaded != null and loaded.snapshot() == a.snapshot(), "autonomous dwelling capacities, identities and history persist")
    print("DEMO_RESULT houses=",a.construction.houses.size()," sites=",a.construction.projects.size()," ticks=",a.tick," ledger=",a.inventory.ledger_ok())
