extends SceneTree
const World = preload("res://scripts/simulation.gd")
var checks := 0
var ok := true

func check(condition: bool, message: String) -> void:
    checks += 1
    if condition:
        print("PASS: " + message)
    else:
        ok = false
        push_error("FAILED: " + message)

func fixture():
    var world = World.new(7788, false)
    for y in range(10, 17):
        for x in range(8, 26):
            world.set_terrain_cell(x, y, World.MEADOW)
    world.set_terrain_cell(9, 12, World.FOREST)
    world.set_terrain_cell(23, 12, World.MOUNTAIN)
    world.capitals[0] = Vector2i(10, 12)
    world.capitals[1] = Vector2i(22, 12)
    world.add_citizen(10, 12, 0)
    world.add_citizen(22, 12, 1)
    world.ai_context.begin_tick(world)
    return world

func supply(world, nation: int, commodity: String, quantity: int, source: Vector2i) -> void:
    var person: Dictionary = world.citizens[nation]
    var actor := int(person["id"])
    for i in range(quantity):
        check(world.inventory.extract(world, actor, commodity, source, 1),
            "resources acquired from finite " + commodity + " terrain")
        check(world.inventory.transfer(world, "citizen:" + str(actor),
            "settlement:" + str(nation), {commodity: 1}, actor),
            "physical resource deposited to owned capital")

func _initialize() -> void:
    var world = fixture()
    var system = world.regional_economy
    check(not system.connected(world), "a newly generated route is not a built road")
    world.tick += 1
    world.ai_context.begin_tick(world)
    system.on_tick(world)
    check(system.route.size() >= 3 and system.road_queue.size() > 0,
        "deterministic continent route produces citizen construction sites")
    check(not system.connected(world), "road planning does not instantly construct infrastructure")
    var origin := world.citizens[0]
    var origin_mind: Dictionary = world.citizen_ai_by_id[str(origin["id"])]
    var foreign := world.citizens[1]
    var foreign_mind: Dictionary = world.citizen_ai_by_id[str(foreign["id"])]
    for i in range(500):
        world.tick += 1
        world.ai_context.begin_tick(world)
        system.on_tick(world)
        system.work_step(world, origin, origin_mind)
        system.work_step(world, foreign, foreign_mind)
        if system.connected(world) and system.road_queue.is_empty():
            break
    check(system.connected(world) and system.roads.size() > 0,
        "living builders walk and complete contiguous physical road segments")
    check(system.road_queue.is_empty(), "road labour and assignments finish without phantom work")
    check(world.inventory.ledger_ok(), "road building does not mint materials")
    supply(world, 0, "wood", 5, Vector2i(9, 12))
    supply(world, 1, "stone", 5, Vector2i(23, 12))
    check(not world.inventory.exchange_at_market(world, 1, 1, {"wood": 1}, {"stone": 1}),
        "unauthorised remote barter is rejected")
    for i in range(300):
        world.tick += 1
        world.ai_context.begin_tick(world)
        system.on_tick(world)
        system.work_step(world, origin, origin_mind)
        system.work_step(world, foreign, foreign_mind)
        if system.completed_trades > 0:
            break
    check(system.completed_trades > 0, "merchants physically deliver goods, barter and return home")
    check(world.inventory.held("settlement:0", "stone") > 0 and
        world.inventory.held("settlement:1", "wood") > 0,
        "different capital markets exchange real reciprocal commodities")
    check(world.inventory.ledger_ok(), "cross-capital trade preserves authoritative physical item ledger")
    var copy = World.from_snapshot(world.snapshot())
    check(copy != null, "road and trade snapshot can be restored")
    if copy != null:
        check(copy.regional_economy.snapshot() == system.snapshot(),
            "road segments, route, jobs, market quotes and trade history persist")
        check(copy.inventory.ledger_ok(), "save/restore retains commodity conservation")
    var before := system.roads.size()
    if before > 0:
        var key := str(system.roads.keys()[0])
        var cell := Vector2i(int(key) % world.WIDTH, int(key) / world.WIDTH)
        world.set_terrain_cell(cell.x, cell.y, World.OCEAN)
        check(system.roads.size() < before, "terrain god powers destroy invalid physical road tiles")
    print("REGIONAL_ECONOMY_CHECKS=", checks)
    if ok:
        print("REGIONAL_ECONOMY_TESTS_PASSED")
    quit(0 if ok else 1)
