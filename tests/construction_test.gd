extends SceneTree

const Simulation = preload("res://scripts/simulation.gd")
const Economy = preload("res://scripts/ai/construction_economy.gd")

func _initialize() -> void:
    var ok := true
    var a = make_village()
    var b = make_village()
    for i in range(520):
        a.step()
        b.step()
    ok = check(a.snapshot() == b.snapshot(), "deterministic construction replay") and ok
    ok = check(a.citizens.size() == 20, "no timer-based phantom population growth") and ok
    ok = check(a.construction.houses.size() >= 1, "citizens physically construct housing") and ok
    ok = check(a.construction.projects.size() <= 1, "one active housing project per nation") and ok
    var wood_extracted := int(a.construction.depleted.get(str(a.index_of(13, 16)), 0))
    var stone_extracted := int(a.construction.depleted.get(str(a.index_of(19, 16)), 0))
    ok = check(a.inventory.ledger_ok() and wood_extracted == int(a.inventory.minted.get("wood", 0)) + int(a.inventory.minted.get("plant_fibre", 0)) and stone_extracted == int(a.inventory.minted.get("stone", 0)) + int(a.inventory.minted.get("flint", 0)),
        "finite resource conservation across stores, cargo, sites, homes and toolmaking") and ok
    var loaded = Simulation.from_snapshot(a.snapshot())
    ok = check(loaded != null, "construction snapshot loads") and ok
    if loaded != null:
        ok = check(loaded.construction.snapshot() == a.construction.snapshot(),
            "houses, projects, materials and jobs restored exactly") and ok
        for i in range(120):
            a.step()
            loaded.step()
        ok = check(a.snapshot() == loaded.snapshot(), "post-save deterministic job continuation") and ok
    if not a.construction.houses.is_empty():
        var before: int = a.construction.houses.size()
        var site: Dictionary = a.construction.houses[0]
        a.set_terrain_cell(int(site["x"]), int(site["y"]), Simulation.ASH)
        ok = check(a.construction.houses.size() == before - 1,
            "fire removes a completed building") and ok
    var legacy: Dictionary = make_village().snapshot()
    legacy.erase("construction")
    var migrated = Simulation.from_snapshot(legacy)
    ok = check(migrated != null and migrated.construction.houses.is_empty(),
        "legacy snapshots load with empty construction state") and ok
    if ok:
        print("CONSTRUCTION_TESTS_PASSED")
    quit(0 if ok else 1)

func make_village():
    var world = Simulation.new(6001, false)
    for y in range(7, 26):
        for x in range(7, 26):
            world.set_terrain_cell(x, y, Simulation.MEADOW)
    world.set_terrain_cell(13, 16, Simulation.FOREST)
    world.set_terrain_cell(19, 16, Simulation.MOUNTAIN)
    world.capitals[0] = Vector2i(16, 16)
    for i in range(20):
        world.add_citizen(16, 16, 0)
    return world

func check(condition: bool, description: String) -> bool:
    if not condition:
        push_error("FAILED: " + description)
        return false
    print("PASS: " + description)
    return true
