extends SceneTree
const World = preload("res://scripts/simulation.gd")

func _initialize() -> void:
    var ok := true
    var a = village()
    var b = village()
    ok = check(a.snapshot() == b.snapshot(), "same initial people and finite ecology") and ok
    # The full simulation alone must supply work trips, materials, technology
    # experiments, skills and manufactured tools, without seeded equipment.
    for i in range(1400):
        a.step()
        b.step()
    ok = check(a.snapshot() == b.snapshot(), "autonomous toolmaking replay is deterministic") and ok
    ok = check(a.occupations.facility_present(a, 0, "tool_area"),
        "citizens autonomously assemble a real workyard") and ok
    ok = check(a.occupations.has_capability(a, 0, "stone_working") and
        a.toolmaking.experiments_total > 0,
        "local stone technology discovered through real physical experiments") and ok
    var made: Dictionary = {}
    for serial in a.toolmaking.instances:
        var instance: Dictionary = a.toolmaking.instances[serial]
        var product := str(instance["item_id"])
        made[product] = int(made.get(product, 0)) + 1
    print("D3_AUTONOMOUS_TOOLS=", made, " crafted_total=", a.toolmaking.crafted_total)
    ok = check(a.toolmaking.crafted_total > 0 and not a.toolmaking.instances.is_empty(),
        "citizens autonomously craft durable tools with unique physical identities") and ok
    ok = check(int(made.get("stone_axe", 0)) > 0,
        "autonomous chain advances beyond a hammerstone to a usable stone axe") and ok
    ok = check(a.inventory.ledger_ok() and a.food.ledger_ok(),
        "both toolcraft and food economies conserve all produced resources") and ok
    var loaded = World.from_snapshot(a.snapshot())
    ok = check(loaded != null and loaded.snapshot() == a.snapshot(),
        "autonomous work jobs and item serials restore exactly") and ok
    if loaded != null:
        for i in range(65):
            a.step()
            loaded.step()
        ok = check(a.snapshot() == loaded.snapshot(),
            "loaded autonomous toolmaker resumes exactly same physical work") and ok
    if ok:
        print("TOOLMAKING_AUTONOMY_TESTS_PASSED")
    quit(0 if ok else 1)

func village():
    var world = World.new(4023, false)
    for y in range(17, 36):
        for x in range(14, 36):
            world.set_terrain_cell(x, y, World.MEADOW)
    world.capitals[0] = Vector2i(24, 25)
    for loc in [Vector2i(22,25), Vector2i(23,23), Vector2i(24,22),
            Vector2i(28,24), Vector2i(30,25), Vector2i(26,27),
            Vector2i(20,26), Vector2i(29,29), Vector2i(21,21)]:
        world.set_terrain_cell(loc.x, loc.y, World.FOREST)
    for loc in [Vector2i(25,23), Vector2i(26,22), Vector2i(21,24),
            Vector2i(27,26), Vector2i(30,22), Vector2i(32,25),
            Vector2i(20,28), Vector2i(29,30), Vector2i(23,29)]:
        world.set_terrain_cell(loc.x, loc.y, World.MOUNTAIN)
    for i in range(22):
        world.add_citizen(24, 25, 0)
    world.ai_context.begin_tick(world)
    return world

func check(condition: bool, label: String) -> bool:
    if not condition:
        push_error("FAILED: " + label)
        return false
    print("PASS: " + label)
    return true
