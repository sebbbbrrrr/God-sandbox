extends SceneTree
const World = preload("res://scripts/simulation.gd")
const Inspector = preload("res://scripts/ui/item_inspector.gd")
const Art = preload("res://scripts/ui/item_pixel_art.gd")
const SaveStore = preload("res://scripts/ai/save_store.gd")
const VIEWPORT := Vector2(480, 850)

func _initialize() -> void:
    var ok := true
    var w = fixture()
    var who: Dictionary = w.citizens[0]
    var pid: int = int(who["id"])
    var ui = Inspector.new()
    ok = check(Art.pixel_count("stone_axe") > 15 and
        Art.pixel_count("stone_pick") > 15 and
        Art.pixel_count("unknown_catalogue_item") > 15,
        "real pixel motifs exist for equipment and unknown-item fallback") and ok
    var geometry: Dictionary = ui.geometry(VIEWPORT, 188.0)
    var rect: Rect2 = geometry["panel"]
    ok = check(rect.position.y >= 50.0 and rect.end.y < 850.0 - 188.0 and
        (geometry["close"] as Rect2).size.x >= 40.0 and
        int(geometry["rows_count"]) >= 4,
        "mobile modal stays above toolbar with visible accessible rows") and ok
    ok = check(not ui.open_for(w, "ground:12345", "ground") and not ui.visible,
        "cannot open a fictional empty ground cache") and ok
    ok = check(ui.open_for(w, "citizen:" + str(pid), "citizen") and
        ui.focus_citizen_id == pid, "selecting a living citizen establishes acting owner") and ok
    ok = check(ui.change_tab(w, "stores") and ui.focus_citizen_id == pid and
        ui.holder_id == "settlement:0",
        "pack and store tabs keep the same acting citizen") and ok
    ok = check(not ui.actions_for(w).size() > 0,
        "empty settlement has no actionable phantom inventory") and ok
    ok = check(bootstrap(w, pid), "fixture crafts two unique axes using conserved recipes") and ok
    ok = check(w.inventory.ledger_ok(), "foundation remains conserved") and ok
    var serials: Array[String] = w.toolmaking._matching_serials("settlement:0", "stone_axe")
    ok = check(serials.size() == 2, "two stone axes have independent serial numbers") and ok
    var damaged := serials[0]
    var intact := serials[1]
    w.toolmaking.instances[damaged]["condition"] = 18
    ui.sync(w)
    var rows := ui.rows_for(w)
    var damaged_row_index := -1
    for i in range(rows.size()):
        if str(rows[i]["serial"]) == damaged:
            damaged_row_index = i
            break
    ok = check(damaged_row_index >= 0, "damage history is rendered per unique physical serial") and ok
    if damaged_row_index >= 0:
        var slot: int = damaged_row_index - ui.scroll
        var area: Rect2 = geometry["rows"]
        var row_tap := area.position + Vector2(82, (float(slot) + 0.5) * ui.ROW_HEIGHT)
        ok = check(ui.tap(w, row_tap, VIEWPORT, 188.0) and
            ui.selected_key == "serial:" + damaged,
            "touch on tool row selects its exact serial") and ok
    ok = check(ui.apply_action(w, "take") and
        str(w.toolmaking.instances[damaged]["holder"]) == "citizen:" + str(pid) and
        str(w.toolmaking.instances[intact]["holder"]) == "settlement:0" and
        w.inventory.ledger_ok(),
        "TAKE moves only selected damaged axe and never duplicates intact one") and ok
    ok = check(ui.change_tab(w, "pack"), "citizen switches to physical pack") and ok
    ui.selected_key = "serial:" + damaged
    ok = check(ui.apply_action(w, "equip") and
        str(w.toolmaking.equipped.get(str(pid), "")) == damaged,
        "selected axe equips only its physical owner") and ok
    ok = check(ui.apply_action(w, "unequip") and
        not w.toolmaking.equipped.has(str(pid)),
        "UNEQUIP detaches bonus without erasing carried item") and ok
    ok = check(ui.apply_action(w, "equip") and ui.apply_action(w, "drop"),
        "DROP transfers equipped axe to actual ground tile") and ok
    var ground := "ground:" + str(w.index_of(int(who["x"]), int(who["y"])))
    ok = check(w.inventory.held(ground, "stone_axe") == 1 and
        not w.toolmaking.equipped.has(str(pid)) and
        str(w.toolmaking.instances[damaged]["holder"]) == ground,
        "ground pickup display, custody and unequip state agree") and ok
    ok = check(ui.open_for(w, ground, "ground") and
        ui.apply_action(w, "pick_up") and w.inventory.held(ground, "stone_axe") == 0,
        "an acting citizen can retrieve physically adjacent ground drop") and ok
    ok = check(ui.change_tab(w, "pack"), "person may return to pack after recovery") and ok
    ui.selected_key = "serial:" + damaged
    ok = check(ui.apply_action(w, "store") and
        str(w.toolmaking.instances[damaged]["holder"]) == "settlement:0",
        "DEPOSIT returns exact used tool to nearby settlement") and ok
    ok = check(ui.change_tab(w, "stores"), "store tab reopens new item custody") and ok
    ui.selected_key = "serial:" + damaged
    ok = check(ui.apply_action(w, "repair") and
        w.toolmaking.jobs.has(str(pid)) and
        int(w.toolmaking.instances[damaged]["condition"]) == 18,
        "QUEUE REPAIR begins physical work; it does not instantly restore item") and ok
    for i in range(3):
        w.tick += 1
        w.toolmaking.work_step(w, who, w.citizen_ai_by_id[str(pid)])
    ok = check(int(w.toolmaking.instances[damaged]["condition"]) > 18 and
        w.toolmaking.repaired_total == 1 and w.inventory.ledger_ok(),
        "qualified repair consumes raw stone after real work ticks") and ok
    ok = check(ui.apply_action(w, "take") and w.inventory.ledger_ok(),
        "repaired specific item can be withdrawn again") and ok
    ui.change_tab(w, "pack")
    ui.selected_key = "serial:" + damaged
    w.toolmaking.instances[damaged]["condition"] = 0
    ok = check(not ui.apply_action(w, "equip") and
        not w.toolmaking.equipped.has(str(pid)),
        "broken item may be inspected but cannot be equipped") and ok
    var original: Dictionary = w.snapshot()
    var restored = World.from_snapshot(original)
    ok = check(restored != null and restored.snapshot() == original,
        "D4 inspection actions preserve JSON and exact serial persistence") and ok
    var binary: Variant = SaveStore.decode(w.prepare_save_bytes())
    var loaded = World.from_snapshot(binary) if binary is Dictionary else null
    ok = check(loaded != null and loaded.snapshot() == original,
        "D4 actions remain compatible with compressed world saves") and ok
    var stored_before: Dictionary = w.inventory.snapshot()
    var outsider = World.new(777, false)
    ok = check(not outsider.inventory.transfer(outsider, "settlement:0",
        "citizen:1", {"wood": 1}, pid),
        "empty or remote holders cannot be tricked into free material transfer") and ok
    ok = check(stored_before == w.inventory.snapshot(),
        "unrelated failed operation cannot alter original world custody") and ok
    if ok:
        print("ITEM_INSPECTOR_TESTS_PASSED")
    quit(0 if ok else 1)

func fixture():
    var w = World.new(22026, false)
    for y in range(14, 28):
        for x in range(14, 28):
            w.set_terrain_cell(x, y, World.MEADOW)
    w.set_terrain_cell(19, 20, World.FOREST)
    w.set_terrain_cell(20, 19, World.FOREST)
    w.set_terrain_cell(21, 20, World.MOUNTAIN)
    w.set_terrain_cell(20, 20, World.TOWN)
    w.capitals[0] = Vector2i(20, 20)
    w.add_citizen(20, 20, 0)
    w.ai_context.begin_tick(w)
    w.construction.houses.append({"id": 77, "type": "tool_area",
        "nation": 0, "capacity": 0, "x": 20, "y": 20, "built_tick": 0})
    w.occupations.grant_capability(w, 0, "stone_working", "experiment")
    return w

func harvest(w, pid: int, item_id: String, source: Vector2i, count: int) -> bool:
    return w.inventory.extract(w, pid, item_id, source, count) and \
        w.inventory.transfer(w, "citizen:" + str(pid), "settlement:0", {item_id: count}, pid)

func bootstrap(w, pid: int) -> bool:
    if not harvest(w, pid, "stone", Vector2i(21, 20), 2) or \
            not harvest(w, pid, "flint", Vector2i(21, 20), 2) or \
            not harvest(w, pid, "wood", Vector2i(19, 20), 2) or \
            not harvest(w, pid, "plant_fibre", Vector2i(20, 19), 3) or \
            not harvest(w, pid, "plant_fibre", Vector2i(20, 19), 3):
        return false
    if not w.inventory.craft_at(w, "hammerstone", pid):
        return false
    for i in range(2):
        if not w.inventory.craft_at(w, "knapped_flint", pid) or \
                not w.inventory.craft_at(w, "cordage", pid) or \
                not w.inventory.craft_at(w, "stone_axe", pid):
            return false
    return true

func check(condition: bool, message: String) -> bool:
    if not condition:
        push_error("FAILED: " + message)
        return false
    print("PASS: " + message)
    return true
