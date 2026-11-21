extends SceneTree
const Fixture = preload("res://tests/architecture_fixture.gd")
const World = preload("res://scripts/simulation.gd")
const SaveStore = preload("res://scripts/ai/save_store.gd")
var failed := false
var checks := 0

func check(value: bool, message: String) -> void:
    checks += 1
    if value: print("PASS: "+message)
    else:
        failed = true
        push_error("FAILED: "+message)

func _initialize() -> void:
    var w = Fixture.world()
    var c = w.construction.catalogue
    check(c.validate(w.inventory.catalogue.items).is_empty(),"canonical recipes, stages, tools, repairs, entrances and eleven-age registry")
    check(c.eras.size()==11 and c.regions.size()==8,"eleven exact ages and eight regional grammar slots")
    var ids: Array = []
    for row in c.definitions.values():
        if not bool(row.get("legacy",true)) and str(row.get("asset_batch",""))!="B": ids.append(str(row["id"]))
    var built: Array = []
    for i in range(ids.size()):
        var house: Dictionary = Fixture.build(w,str(ids[i]),Vector2i(28+i%4*5,12+i/4*6))
        check(not house.is_empty(),"real material hauling and staged worker construction: "+str(ids[i]))
        if house.is_empty(): continue
        built.append(house)
        check(w.inventory.ledger_ok(),"physical item conservation: "+str(ids[i]))
        check(house.get("architecture",{}).get("sprite","")==c.definition(str(ids[i]))["visual"]["sprite"],"persistent authored sprite identity: "+str(ids[i]))
        check(not house.get("placement_reason",{}).get("reason","").is_empty(),"saved explainable placement: "+str(ids[i]))
    check(built.size()==15,"all fifteen new definitions constructed without free material fixtures")
    var original: Dictionary = built[0].duplicate(true) if not built.is_empty() else {}
    w.occupations.grant_capability(w,0,"electrical_grid","experiment")
    check(not original.is_empty() and built[0]["architecture"]==original["architecture"],"later capability leaves historical architecture unchanged")
    var json_copy = World.from_snapshot(JSON.parse_string(JSON.stringify(w.snapshot())))
    var compact_copy = World.from_snapshot(SaveStore.decode(w.prepare_save_bytes()))
    check(json_copy!=null and json_copy.snapshot()==w.snapshot(),"all material stages, architecture and recipes survive JSON save")
    check(compact_copy!=null and compact_copy.snapshot()==w.snapshot(),"architecture provenance and condition survive compressed save")
    var corrupted: Dictionary = w.snapshot().duplicate(true)
    corrupted["construction"]["houses"][0]["architecture"]["sprite"] = "nonexistent_sprite"
    check(World.from_snapshot(corrupted)==null,"save rejects nonexistent or mismatched architectural identities")
    var cold: Dictionary = c.definition("earth_shelter")
    check(not c.eligible(w,0,cold,{"climates":"arid"}) and c.eligible(w,0,cold,{"climates":"cold"}),"cold adaptation has real construction eligibility")
    check(c.definition("adobe_house")["materials"]!=c.definition("stilt_house")["materials"],"desert and tropical architecture use different complete material recipes")
    w.occupations.lose_capability(w,0,"pottery","knowledge_lost")
    var blocked: Dictionary = w.construction.evaluate_request(w,{"settlement_id":0,"function":"production","definition_id":"pottery_kiln"})
    check(not blocked["ok"] and blocked["reason"]=="knowledge","imported materials do not grant manufacturing knowledge")
    check(not w.construction.resource_plan(w,0,{"clay":100000})["viable"],"finite-source allocation rejects unattainable material plans")
    production()
    production_chains()
    collapse_during_operation()
    damage(w,built)
    granaries()
    print("ARCHITECTURE_CHECKS=",checks)
    if not failed: print("ARCHITECTURE_INTEGRATION_TESTS_PASSED")
    quit(1 if failed else 0)

func production() -> void:
    var w = Fixture.world()
    var house: Dictionary = Fixture.build(w,"charcoal_clamp",Vector2i(28,30))
    check(not house.is_empty(),"charcoal facility constructed")
    if house.is_empty(): return
    check(Fixture.stock(w,{"wood":4}),"finite forest supplies operating fuel")
    var before: int = w.inventory.held("settlement:0","wood")
    var result := false
    for i in range(180):
        Fixture.work(w,1)
        if w.inventory.held("settlement:0","charcoal")>0:
            result = true
            break
    check(result,"worker fetches wood, performs real production work and returns charcoal")
    check(w.inventory.ledger_ok() and w.inventory.held("settlement:0","wood")<=before-2,"production consumes exact recipe inputs and preserves the ledger")
    var copy = World.from_snapshot(SaveStore.decode(w.prepare_save_bytes()))
    check(copy!=null,"operational building save loads")
    if copy!=null:
        Fixture.work(w,25)
        Fixture.work(copy,25)
        check(w.snapshot()==copy.snapshot(),"operational hauling and work replay deterministically")
    var p: Dictionary = w.citizens[0]
    var process: Dictionary = w.construction.catalogue.definition("charcoal_clamp")["production"][0]
    w.construction.lifecycle.abandon(w.construction,w,int(house["id"]),true)
    check(not w.inventory.craft_in_building(w,int(p["id"]),house,process),"abandoned facilities cannot operate")

func damage(w, built: Array) -> void:
    if built.is_empty(): return
    var house: Dictionary = built[0]
    check(w.construction.lifecycle.damage(w.construction,w,int(house["id"]),45,"test"),"damage changes real building condition")
    check(w.construction.catalogue.state_of(house,w.tick)=="partially_damaged","damaged state projection")
    w.construction.lifecycle.request_action(w.construction,w,int(house["id"]),"repair")
    check(Fixture.stock(w,{"wood":1,"plant_fibre":1}),"paid repair materials gathered")
    for i in range(160):
        Fixture.work(w,1)
        if int(house["condition"])>=75: break
    check(int(house["condition"])>=75 and w.inventory.ledger_ok(),"real repair restores condition and preserves inventory")
    check(w.construction.lifecycle.damage(w.construction,w,int(house["id"]),100,"collapse_test"),"final damage archives a persistent ruin")
    check(w.construction.building_by_id(int(house["id"])).is_empty() and not w.construction.archived.is_empty(),"collapse releases footprint and retains real ruin provenance")

func granaries() -> void:
    var w = Fixture.world()
    var house: Dictionary = Fixture.build(w,"raised_granary",Vector2i(24,30))
    check(not house.is_empty(),"granary built through shared construction engine")
    if house.is_empty(): return
    # Controlled FOOD ledger opening credit; construction still used finite nodes.
    w.food.store(0)["grain"] = 100
    w.food.produced["grain"] = 100
    w.tick = w.calendar.TICKS_PER_YEAR
    w.food.on_tick_households(w)
    check(int(w.food.store(0)["grain"])==100 and w.food.ledger_ok(),"live finite granary protects physically accounted grain")
    w.construction.lifecycle.abandon(w.construction,w,int(house["id"]),true)
    w.tick += w.calendar.TICKS_PER_YEAR
    w.food.on_tick_households(w)
    check(int(w.food.store(0)["grain"])==95 and w.food.ledger_ok(),"abandoned granary stops protection; grain loss is conserved")

func production_chains() -> void:
    var w = Fixture.world()
    var clamp: Dictionary = Fixture.build(w,"charcoal_clamp",Vector2i(28,30))
    check(not clamp.is_empty() and Fixture.stock(w,{"wood":2}),"fuel-chain clamp and finite wood")
    for i in range(150):
        Fixture.work(w,1)
        if w.inventory.held("settlement:0","charcoal")>=1: break
    var kiln: Dictionary = Fixture.build(w,"pottery_kiln",Vector2i(32,30))
    check(not kiln.is_empty() and Fixture.stock(w,{"clay":2,"sand":1}),"kiln receives finite clay and sand")
    for i in range(200):
        Fixture.work(w,1)
        if w.inventory.held("settlement:0","clay_brick")>=1: break
    check(w.inventory.held("settlement:0","clay_brick")==1 and w.inventory.held("settlement:0","charcoal")==0,"potter spends clay, sand and charcoal for one physical brick")
    var loom: Dictionary = Fixture.build(w,"weaving_house",Vector2i(36,30))
    check(not loom.is_empty() and Fixture.stock(w,{"plant_fibre":4}),"weaving station receives finite fibre")
    for i in range(200):
        Fixture.work(w,1)
        if w.inventory.held("settlement:0","woven_cloth")>=1: break
    check(w.inventory.held("settlement:0","woven_cloth")==1 and w.inventory.ledger_ok(),"trained weaver transforms four fibres into conserved cloth")

func collapse_during_operation() -> void:
    var w = Fixture.world()
    var house: Dictionary = Fixture.build(w,"charcoal_clamp",Vector2i(28,30))
    check(not house.is_empty() and Fixture.stock(w,{"wood":2}),"collapse test has a paid facility and real input cargo")
    Fixture.work(w,1)
    check(w.inventory.held("citizen:1","wood")==2,"operational worker physically picks up inputs")
    w.construction.lifecycle.damage(w.construction,w,int(house["id"]),100,"mid_operation_collapse")
    var loaded = World.from_snapshot(w.snapshot())
    check(loaded!=null and w.inventory.ledger_ok(),"immediate post-collapse save restores without a dangling facility job")
    Fixture.work(w,40)
    check(w.inventory.held("settlement:0","wood")==2 and w.inventory.ledger_ok(),"collapse survivor returns exact unconsumed inputs")
