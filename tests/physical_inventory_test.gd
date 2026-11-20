extends SceneTree
const World = preload("res://scripts/simulation.gd")
const SaveStore = preload("res://scripts/ai/save_store.gd")

func _initialize() -> void:
    var ok := true
    var world = village()
    var donor: Dictionary = world.citizens[0]
    var receiver: Dictionary = world.citizens[1]
    var source := Vector2i(15, 16)
    ok = check(not world.inventory.extract(world, int(donor["id"]), "bronze_ingot", source),
        "unsupported manufactured goods cannot be extracted from nature") and ok
    ok = check(not world.inventory.extract(world, int(donor["id"]), "wood", Vector2i(20, 20)),
        "remote resource extraction denied") and ok
    ok = check(world.inventory.extract(world, int(donor["id"]), "wood", source, 2),
        "real nearby forest deposits timber in citizen inventory") and ok
    ok = check(world.inventory.held("citizen:1", "wood") == 2 and
        world.construction.left_at(world, 15, 16, "wood") == 4,
        "finite tile depletion and carried units remain synchronized") and ok
    ok = check(world.inventory.extract(world, int(receiver["id"]), "stone", Vector2i(17, 16), 1),
        "mountain stone gathered into second citizen inventory") and ok
    var before: Dictionary = world.inventory.snapshot()
    ok = check(not world.inventory.transfer(world, "citizen:1", "settlement:0",
        {"wood": 3}, 1) and world.inventory.snapshot() == before,
        "failed transfer leaves all state unchanged") and ok
    ok = check(world.inventory.transfer(world, "citizen:1", "settlement:0",
        {"wood": 2}, 1) and world.inventory.transfer(world, "citizen:2",
        "settlement:0", {"stone": 1}, 2), "physical deposits to local settlement") and ok
    ok = check(int(world.construction.stockpiles[0]["wood"]) == 2 and
        int(world.construction.stockpiles[0]["stone"]) == 1,
        "legacy house stockpiles reference authoritative ledger") and ok
    before = world.inventory.snapshot()
    ok = check(not world.inventory.transfer(world, "settlement:0", "citizen:1",
        {"wood": 2, "stone": 2}, 1) and world.inventory.snapshot() == before,
        "all-or-nothing bundled withdrawal prevents partial material loss") and ok
    ok = check(world.inventory.transfer(world, "settlement:0", "citizen:1",
        {"wood": 2, "stone": 1}, 1), "builder physically collects construction cargo") and ok
    ok = check(world.inventory.transfer(world, "citizen:1", "citizen:2",
        {"wood": 1}, 1), "adjacent citizens can hand over owned material") and ok
    var consentless: Dictionary = world.inventory.snapshot()
    ok = check(not world.inventory.transfer(world, "citizen:1", "citizen:2",
        {"wood": 1}, 2) and world.inventory.snapshot() == consentless,
        "another person cannot take items from an unwilling carrier") and ok
    receiver["hp"] = 0
    world.inventory.reconcile_deaths(world)
    ok = check(world.inventory.held("citizen:2", "wood") == 0 and
        world.inventory.held("ground:" + str(world.index_of(16, 16)), "wood") == 1,
        "death leaves salvageable property on the actual tile") and ok
    ok = check(world.inventory.transfer(world,
        "ground:" + str(world.index_of(16, 16)), "citizen:1", {"wood": 1}, 1),
        "survivor can recover physically nearby dropped goods") and ok
    ok = check(world.inventory.consume(world, "citizen:1", {"wood": 2, "stone": 1}, 1, "test_house"),
        "real work consumes carried units with conservation accounting") and ok
    ok = check(world.inventory.ledger_ok() and
        int(world.inventory.consumed.get("wood", 0)) == 2,
        "extracted = currently held + consumed + destroyed") and ok
    var snapshot: Dictionary = world.snapshot()
    var restored = World.from_snapshot(snapshot)
    print("D2_DEBUG restored_null=", restored == null)
    if restored != null:
        print("D2_DEBUG original=", world.inventory.snapshot())
        print("D2_DEBUG returned=", restored.inventory.snapshot())
    ok = check(restored != null and restored.inventory.snapshot() == world.inventory.snapshot(),
        "JSON world snapshot restores every holder and audit counter") and ok
    var packed: PackedByteArray = world.prepare_save_bytes()
    var decoded: Variant = SaveStore.decode(packed)
    var binary_world = World.from_snapshot(decoded) if decoded is Dictionary else null
    ok = check(binary_world != null and binary_world.inventory.snapshot() == world.inventory.snapshot(),
        "compressed world save round-trips physical inventory") and ok
    if restored != null:
        ok = check(int(restored.construction.stockpiles[0]["wood"]) == 0 and
            restored.inventory.ledger_ok(), "restored stockpile aliases remain consistent") and ok
    var tampered: Dictionary = snapshot.duplicate(true)
    tampered["inventory"]["minted"]["wood"] = 500
    ok = check(World.from_snapshot(tampered) == null,
        "tampered nonconserving ledger fails closed") and ok
    var legacy: Dictionary = snapshot.duplicate(true)
    legacy.erase("inventory")
    legacy["construction"]["stockpiles"][0] = {"wood": 3, "stone": 1}
    var migrated = World.from_snapshot(legacy)
    ok = check(migrated != null and migrated.inventory.held("settlement:0", "wood") == 3 and
        migrated.inventory.ledger_ok(),
        "older save materials migrate once as explicitly tracked opening balances") and ok
    if ok:
        print("PHYSICAL_INVENTORY_TESTS_PASSED")
    quit(0 if ok else 1)

func village():
    var world = World.new(220602, false)
    for y in range(12, 21):
        for x in range(12, 21):
            world.set_terrain_cell(x, y, World.MEADOW)
    world.set_terrain_cell(15, 16, World.FOREST)
    world.set_terrain_cell(17, 16, World.MOUNTAIN)
    world.capitals[0] = Vector2i(16, 16)
    world.add_citizen(16, 16, 0)
    world.add_citizen(16, 16, 0)
    return world

func check(condition: bool, message: String) -> bool:
    if not condition:
        push_error("FAILED: " + message)
        return false
    print("PASS: " + message)
    return true
