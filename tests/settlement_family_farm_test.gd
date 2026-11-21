extends SceneTree
const World = preload("res://scripts/simulation.gd")
const Fixture = preload("res://tests/settlement_network_lifecycle_test.gd")
const Demo = preload("res://scripts/civilisation/settlement_demo_world.gd")
const Nav = preload("res://scripts/ai/navigation.gd")
var count := 0
var failures := 0

func check(value: bool, label: String) -> void:
    count += 1
    if value: print("PASS: "+label)
    else:
        failures += 1
        push_error("FAILED: "+label)

func _initialize() -> void:
    var helper = Fixture.new()
    var w = helper.fixture()
    var sid := 2
    var field: Dictionary = helper.build(w,sid,"cultivation_field")
    check(not field.is_empty(),"farm enclosure uses real construction materials and labour")
    check(not w.occupations.has_capability(w,sid,"cultivation"),"building a farm does not grant technology from calendar or appearance")
    w.occupations.on_tick(w)
    var farmer: Dictionary = w.citizens[8] # ID9, existing actual local resident
    var mind: Dictionary = w.citizen_ai_by_id[str(farmer["id"])]
    # Establish experience through actual local foraging jobs and deliveries.
    for i in range(150):
        helper.tick(w)
        w.food.work_step(w,farmer,mind)
        if w.occupations.xp_for(farmer,"forager")>=8 and w.food.total(w.food.store(sid))>=3 and not w.food.jobs.has(str(farmer["id"])): break
    check(w.food.produced["grain"]>0 and w.food.ledger_ok(),"farmer physically gathers initial edible grain reserves")
    var sowing: bool = w.food._choose_sowing(w,farmer,mind)
    check(sowing,"experienced local worker chooses a physical seed experiment")
    var snapshot: Dictionary = w.snapshot()
    var loaded = World.from_snapshot(JSON.parse_string(JSON.stringify(snapshot)))
    check(loaded!=null,"pending sowing job and seed ownership survive JSON save/load")
    var observed_seed := false
    for i in range(120):
        helper.tick(w)
        w.food.work_step(w,farmer,mind)
        observed_seed = observed_seed or int(w.food.jobs.get(str(farmer["id"]),{}).get("amount",0))==1
        if w.occupations.has_capability(w,sid,"cultivation"): break
    check(observed_seed and not w.food.farms.is_empty(),"seed is physically carried to the field before planting")
    check(w.occupations.has_capability(w,sid,"cultivation") and not w.occupations.has_capability(w,3,"cultivation"),"successful local work adopts cultivation without a national unlock")
    check(w.food.ledger_ok(),"planting consumes real seed and retains food conservation")
    if not w.food.farms.is_empty():
        var farm: Dictionary = w.food.farms[0]
        w.tick = 1800
        farm["ready_tick"] = 1800
        w.food.on_tick_households(w)
        check(bool(farm["harvested"]) and str(farm.get("failure",""))=="winter_crop_loss","winter crop failure has a persistent food-production consequence")
    # Founding with an infant and stocked pantry.
    var family_world = Demo.create()
    family_world.ai_context.begin_tick(family_world)
    family_world.settlements.rebuild_membership(family_world)
    var parent: Dictionary = family_world.citizens[0]
    var baby: Dictionary = family_world.citizens[1]
    check(family_world.households.form_household(family_world,int(parent["id"]),int(baby["id"])),"real household forms before infant migration test")
    baby["life_stage"] = "infant"
    baby["birth_tick"] = -1
    baby["guardian_id"] = int(parent["id"])
    var family: Dictionary = family_world.households.family_for(int(parent["household_id"]))
    # The recorded edible units are fixture opening credits, not runtime production.
    family_world.food.pantry_for(int(family["id"]))["grain"] = 2
    family_world.food.produced["grain"] += 2
    for person in family_world.citizens:
        var traits: Dictionary = family_world.citizen_ai_by_id[str(person["id"])]["personality"]
        traits["curiosity"] = 0
        traits["diligence"] = 0
        traits["caution"] = 100
    var traits: Dictionary = family_world.citizen_ai_by_id[str(parent["id"])]["personality"]
    traits["curiosity"] = 100
    traits["diligence"] = 100
    traits["caution"] = 0
    family_world.settlements.rebuild_membership(family_world)
    var expedition: Dictionary = family_world.founding.try_start(family_world,0)
    check(not expedition.is_empty() and int(baby["id"]) in expedition.get("members",[]),"whole founding household includes its infant and pantry supplies")
    var initial := Vector2i(int(baby["x"]),int(baby["y"]))
    var carried := false
    var packed := false
    for i in range(220):
        var before := Vector2i(int(baby["x"]),int(baby["y"]))
        family_world.step()
        carried = carried or int(baby.get("carried_by",0))==int(parent["id"])
        packed = packed or family_world.food.total(family_world.food.travel_cargo.get(str(parent["id"]),{}))>0
        check(Nav.manhattan(before,Vector2i(int(baby["x"]),int(baby["y"])))<=1,"infant movement remains physical per simulation tick")
        if family_world.settlements.sid(baby)>1: break
    check(carried and packed,"guardian carries infant and physically packed food during travel")
    check(family_world.settlements.sid(baby)>1 and family_world.settlements.sid(baby)==family_world.settlements.sid(parent) and Nav.manhattan(initial,Vector2i(int(baby["x"]),int(baby["y"])))>8,"infant household reaches the new settlement together")
    check(family_world.food.ledger_ok() and family_world.inventory.ledger_ok(),"family migration preserves material and edible-unit ledgers")
    var copy = World.from_snapshot(JSON.parse_string(JSON.stringify(family_world.snapshot())))
    check(copy!=null,"travelling-family food, care and membership restore safely")
    if copy!=null:
        for i in range(50):
            family_world.step()
            copy.step()
        check(copy.snapshot()==family_world.snapshot(),"family travel and local development replay deterministically after restoration")
    helper.free()
    print("SETTLEMENT FAMILY/FARM: ",count," checks, ",failures," failures")
    quit(0 if failures==0 else 1)
