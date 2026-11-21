extends SceneTree
# Headless regression checks for crowded depots, physical tools and labour allocation.
const World = preload("res://scripts/simulation.gd")
const Nav = preload("res://scripts/ai/navigation.gd")
const Labour = preload("res://scripts/ai/labour_priorities.gd")
const Visuals = preload("res://scripts/construction/citizen_work_visuals.gd")
var passed := true
var checks := 0

func check(value: bool, label: String) -> void:
    checks += 1
    if value:
        print("PASS: ", label)
    else:
        passed = false
        push_error("FAIL: " + label)

func _initialize() -> void:
    var world = World.new(7819, false)
    for y in range(7, 22):
        for x in range(7, 22):
            world.set_terrain_cell(x, y, World.MEADOW)
    world.capitals[0] = Vector2i(12, 12)
    check(world.add_citizen(10, 10, 0), "worker can spawn")
    for contact in [Vector2i(13,12), Vector2i(12,13), Vector2i(11,12), Vector2i(12,11)]:
        check(world.add_citizen(contact.x, contact.y, 0), "first contact worker")
        check(world.add_citizen(contact.x, contact.y, 0), "second contact worker")
    world.settlements.ensure_legacy(world)
    world.settlements.rebuild_membership(world)
    world.ai_context.begin_tick(world)
    var seeker: Dictionary = world.citizens[0]
    var centre := Vector2i(12, 12)
    var wait_cell: Vector2i = Nav.hub_access(world, seeker, centre)
    check(Nav.manhattan(wait_cell, centre) in [2,3,4] and
        world.is_walkable(wait_cell.x, wait_cell.y),
        "busy depot stages arrivals away from the contact tiles")
    var old := Vector2i(int(seeker["x"]), int(seeker["y"]))
    var count_before := int(world.ai_context.cell_counts.get(old,0))
    seeker["x"] = old.x + 1
    world.ai_context.moved(seeker, old)
    check(int(world.ai_context.cell_counts.get(old,0)) == count_before - 1 and
        int(world.ai_context.cell_counts.get(Vector2i(seeker["x"],seeker["y"]),0)) > 0,
        "cell occupancy updates even within the same spatial bucket")
    check(Nav.hub_access(world, world.citizens[1], centre) == Vector2i(
        int(world.citizens[1]["x"]), int(world.citizens[1]["y"])),
        "an existing visitor stays at a valid contact point")

    var claimed := {"4": {"kind":"forage","phase":"source","source":[15,12]},
        "5": {"kind":"forage","phase":"depot","source":[15,12]},
        "6": {"kind":"gather","phase":"source","source":[15,12]}}
    check(Labour.claim_count(claimed,[15,12],["forage"]) == 1,
        "only active workers at a matching resource count as competition")
    check(Labour.claim_count(claimed,[15,12],["gather"]) == 1,
        "different jobs count their own source claims")

    var shelter := {"definition_id":"primitive_shelter","priority":70,"x":15,"y":14}
    var pressure := {"unsheltered":8,"food_low":false,"food_emergency":false}
    var urgent_score: int = Labour.project_score(world,shelter,Vector2i(10,10),pressure)
    pressure["unsheltered"] = 0
    check(urgent_score > Labour.project_score(world,shelter,Vector2i(10,10),pressure),
        "housing shortage elevates shelter construction")

    world.set_terrain_cell(14, 12, World.FOREST)
    world.set_terrain_cell(12, 14, World.FOREST)
    var first_source: Dictionary = world.construction.source_for(world, seeker, "wood")
    check(not first_source.is_empty(), "forest resource is reachable")
    if not first_source.is_empty():
        world.construction.jobs["900"] = {"kind":"gather","phase":"source",
            "source":first_source["source"], "nation":0}
        var second_source: Dictionary = world.construction.source_for(world, seeker, "wood")
        check(not second_source.is_empty() and
            second_source.get("source", []) != first_source["source"],
            "wood gatherers reserve different viable source tiles")
        world.construction.jobs.erase("900")
    var sid := 0
    for id in ["berries", "fish", "grain"]:
        world.food.store(sid)[id] = 0
    world.food.store(sid)["berries"] = 60
    var family: int = int(world.citizens[0]["household_id"])
    check(Labour.can_deliver_food(world,sid,family),
        "surplus food permits a household courier")
    world.food.jobs["99"] = {"kind":"deliver","nation":sid,"family_id":family}
    check(not Labour.can_deliver_food(world,sid,family),
        "multiple couriers cannot deliver to the same household")
    check(Visuals._equipped_tool(world,world.citizens[0]) == "",
        "barehand workers never display fictional equipment")
    print("WORKFORCE_DISTRIBUTION_CHECKS=", checks)
    quit(0 if passed else 1)
