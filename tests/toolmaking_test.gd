extends SceneTree
const World = preload("res://scripts/simulation.gd")
const SaveStore = preload("res://scripts/ai/save_store.gd")

func _initialize() -> void:
    var ok := true
    var w = fixture()
    var artisan: Dictionary = w.citizens[0]
    var pid: int = int(artisan["id"])
    var mind: Dictionary = w.citizen_ai_by_id[str(pid)]
    ok = check(not w.occupations.enabled(w, 0, "stone_toolmaker"),
        "no stone toolmaker without real knowledge and a tool area") and ok
    ok = check(not w.inventory.craft_at(w, "stone_axe", pid),
        "advanced goods cannot craft without trained workshop") and ok
    ok = check(gather(w, pid, "wood", Vector2i(21, 24), 2) and
        gather(w, pid, "stone", Vector2i(19, 24), 1),
        "worker physically delivers workshop construction materials") and ok
    var pre: bool = w.inventory.ledger_ok()
    ok = check(pre and w.inventory.held("settlement:0", "wood") == 2,
        "extracted materials conserved before construction") and ok
    ok = check(w.toolmaking._begin(w, artisan, mind, "build", {"remaining": 4}),
        "toolmaking construction started as a physical job") and ok
    for i in range(3):
        w.tick += 1
        w.toolmaking.work_step(w, artisan, mind)
    ok = check(w.occupations.facility_present(w, 0, "tool_area") and
        w.inventory.held("settlement:0", "wood") == 0 and
        int(w.inventory.consumed.get("wood", 0)) == 2,
        "actual tool area consumes wood and stone after construction labour") and ok
    ok = check(not w.occupations.enabled(w, 0, "stone_toolmaker"),
        "physical workshop alone does not grant stone-working knowledge") and ok
    ok = check(gather(w, pid, "flint", Vector2i(19, 24), 1) and
        gather(w, pid, "stone", Vector2i(19, 24), 1),
        "finite stone and flint are extracted and deposited separately") and ok
    ok = check(w.toolmaking._begin(w, artisan, mind, "experiment", {"remaining": 3}),
        "knapping research requires an artisan at the worksite") and ok
    for i in range(2):
        w.tick += 1
        w.toolmaking.work_step(w, artisan, mind)
    ok = check(w.occupations.has_capability(w, 0, "stone_working") and
        w.occupations.enabled(w, 0, "stone_toolmaker") and
        w.inventory.held("settlement:0", "knapped_flint") == 1,
        "real prototype creates physical output and teaches local stoneworking") and ok
    ok = check(gather(w, pid, "stone", Vector2i(19, 24), 1) and
        w.inventory.craft_at(w, "hammerstone", pid),
        "stone-toolmaker makes a unique physical hammerstone") and ok
    ok = check(gather(w, pid, "wood", Vector2i(21, 24), 1) and
        gather(w, pid, "plant_fibre", Vector2i(21, 24), 3),
        "cordage source shares finite forest depletion with timber") and ok
    ok = check(w.inventory.craft_at(w, "cordage", pid) and
        w.inventory.craft_at(w, "stone_axe", pid),
        "real workshop turns chain of materials into a stone axe") and ok
    var axe_serial := ""
    for serial in w.toolmaking.instances:
        if str(w.toolmaking.instances[serial]["item_id"]) == "stone_axe":
            axe_serial = str(serial)
            break
    ok = check(axe_serial != "" and w.inventory.held("settlement:0", "stone_axe") == 1,
        "unique crafted axe serial has the same custody as stack ledger") and ok
    var before: Dictionary = w.inventory.snapshot()
    ok = check(not w.inventory.transfer(w, "settlement:0", "citizen:" + str(pid),
        {"stone_axe": 2}, pid) and w.inventory.snapshot() == before,
        "cannot duplicate or withdraw two copies of a unique tool") and ok
    w.toolmaking.try_equip(w, artisan, "wood")
    ok = check(w.inventory.held("citizen:" + str(pid), "stone_axe") == 1 and
        str(w.toolmaking.equipped.get(str(pid), "")) == axe_serial and
        w.toolmaking.tool_for(w, artisan, "wood") == axe_serial,
        "citizen physically checks out and equips owned axe") and ok
    var condition: int = int(w.toolmaking.instances[axe_serial]["condition"])
    w.toolmaking.wear(w, artisan, "wood")
    ok = check(int(w.toolmaking.instances[axe_serial]["condition"]) < condition,
        "successful resource work reduces unique equipment condition") and ok
    for i in range(9):
        w.toolmaking.wear(w, artisan, "wood")
    ok = check(int(w.toolmaking.instances[axe_serial]["condition"]) == 0 and
        not w.toolmaking.equipped.has(str(pid)),
        "worn-out tool no longer grants an active work bonus") and ok
    ok = check(w.inventory.transfer(w, "citizen:" + str(pid), "settlement:0",
        {"stone_axe": 1}, pid) and
        gather(w, pid, "stone", Vector2i(19, 24), 1) and
        w.toolmaking.repair(w, pid, axe_serial),
        "repair costs real raw stone and restores workshop-held axe") and ok
    ok = check(int(w.toolmaking.instances[axe_serial]["condition"]) > 0 and
        w.inventory.ledger_ok(), "repair revives durable item without minting extra axe") and ok
    var original: Dictionary = w.snapshot()
    var json = World.from_snapshot(original)
    ok = check(json != null and json.snapshot() == original,
        "tool instances and workshop survive JSON save round trip") and ok
    var raw: Variant = SaveStore.decode(w.prepare_save_bytes())
    var compressed = World.from_snapshot(raw) if raw is Dictionary else null
    ok = check(compressed != null and compressed.snapshot() == original,
        "compressed world save retains tool holder, serial and condition") and ok
    var tampered: Dictionary = original.duplicate(true)
    tampered["toolmaking"]["instances"][axe_serial]["condition"] = 100000
    ok = check(World.from_snapshot(tampered) == null,
        "corrupted out-of-bounds tool state rejected instead of silently repaired") and ok
    ok = check(not w.inventory.craft_at(w, "bronze_axe", pid),
        "stone workshop cannot manufacture bronze technology") and ok
    if ok:
        print("TOOLMAKING_TESTS_PASSED")
    quit(0 if ok else 1)

func gather(w, pid: int, item_id: String, source: Vector2i, quantity: int) -> bool:
    if not w.inventory.extract(w, pid, item_id, source, quantity):
        return false
    return w.inventory.transfer(w, "citizen:" + str(pid), "settlement:0",
        {item_id: quantity}, pid)

func fixture():
    var w = World.new(20261120, false)
    for y in range(18, 31):
        for x in range(14, 29):
            w.set_terrain_cell(x, y, World.MEADOW)
    w.set_terrain_cell(21, 24, World.FOREST)
    w.set_terrain_cell(19, 24, World.MOUNTAIN)
    w.capitals[0] = Vector2i(20, 24)
    w.add_citizen(20, 24, 0)
    w.ai_context.begin_tick(w)
    return w

func check(condition: bool, message: String) -> bool:
    if not condition:
        push_error("FAILED: " + message)
        return false
    print("PASS: " + message)
    return true
