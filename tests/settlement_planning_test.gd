extends SceneTree
const World = preload("res://scripts/simulation.gd")
const Demo = preload("res://scripts/civilisation/settlement_demo_world.gd")
const Nav = preload("res://scripts/ai/navigation.gd")
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
    checks += 1
    if value:
        print("PASS: " + label)
    else:
        failures += 1
        push_error("FAILED: " + label)

func _initialize() -> void:
    var world = Demo.create()
    world.ai_context.begin_tick(world)
    world.settlements.rebuild_membership(world)
    var center := Vector2i(60, 50)
    var id: int = world.settlements.register_camp(world, 0, center, 1)
    # Seed a benchmark/test colony by assigning the people already placed there.
    # Runtime relocation is tested separately and always walks.
    for i in range(3):
        world.add_citizen(center.x, center.y, 0)
        world.citizens[-1]["settlement_id"] = id
    world.ai_context.begin_tick(world)
    world.settlements.rebuild_membership(world)
    var row: Dictionary = world.construction.catalogue.definition("primitive_shelter")
    var chosen: Vector2i = world.construction.find_location(world, row, center, 0, id)
    check(chosen.x >= 0 and Nav.manhattan(chosen, center) <= 9, "settlement planner chooses valid bounded local land")
    check(not world.settlement_planner.reserved(world, id, chosen), "homes preserve communal centre and expansion corridor")
    check(world.construction.placement.validate(world, row, chosen, 0) == "", "strategic desirability preserves original terrain validation")
    var result: Dictionary = world.construction.request_construction(world, {"settlement_id": id, "function": "shelter", "location": [center.x, center.y]})
    check(not result["ok"], "explicit request cannot build over local depot reservation")
    result = world.construction.request_construction(world, {"settlement_id": id, "function": "shelter"})
    check(result["ok"], "new settlement requests actual local construction")
    var site: Dictionary = world.construction.site_by_id(int(result.get("site_id", 0)))
    check(not site.is_empty() and int(site["settlement_id"]) == id and int(site["nation"]) == 0,
        "construction separates local ownership from political affiliation")
    var next: Vector2i = world.construction.find_location(world, row, center, 0, id)
    check(next != Vector2i(int(site["x"]), int(site["y"])), "planned construction reserves its authoritative footprint")
    check(world.construction.placement.validate(world, row, Vector2i(int(site["x"]), int(site["y"])), 0) == "overlap",
        "overlapping construction rejected by the existing placement authority")
    var blocked := Vector2i(58, 50)
    world.set_terrain_cell(blocked.x, blocked.y, World.ASH)
    check(world.construction.placement.validate(world, row, blocked, 0) != "", "hazards and terrain edits invalidate placement")
    var sample: Dictionary = world.settlement_planner.survey(world, center)
    var wood_before := int(sample["wood"])
    var node := Vector2i(58, 52)
    world.set_terrain_cell(node.x, node.y, World.FOREST)
    var after: Dictionary = world.settlement_planner.survey(world, center)
    check(int(after["wood"]) > wood_before, "terrain event invalidates only affected cached ecology samples")
    var person: Dictionary = world.citizens[-1]
    person["x"] = node.x
    person["y"] = node.y
    world.ai_context.begin_tick(world)
    var available_before := int(after["wood"])
    check(world.inventory.extract(world, int(person["id"]), "wood", node), "local citizen extracts finite wood through the custody ledger")
    check(int(world.settlement_planner.survey(world, center)["wood"]) == available_before - 1,
        "resource depletion invalidates ecology cache in the same tick")
    var restored = World.from_snapshot(JSON.parse_string(JSON.stringify(world.snapshot())))
    check(restored != null, "planning and local construction restore together")
    if restored != null:
        check(restored.construction.occupied(int(site["x"]), int(site["y"])), "load rebuilds the original footprint index")
        check(restored.inventory.ledger_ok(), "planning and restoration never mint material")
    # Infrastructure limits are real ecological caps, not date-based unlocks.
    for i in range(3):
        world.settlement_planner.update_one(world)
    var plan: Dictionary = world.settlements.get_record(id)["plan"]
    check(not plan.is_empty() and int(plan["carrying_capacity"]) <= 72, "bounded development plan records actual local carrying capacity")
    check(int(plan["housing_demand"]) == 3, "housing demand follows local population and completed beds")
    check(world.settlement_planner.cache.size() <= 64, "ecology cache respects hard memory cap")
    print("SETTLEMENT PLANNING: ", checks, " checks, ", failures, " failures")
    quit(0 if failures == 0 else 1)
