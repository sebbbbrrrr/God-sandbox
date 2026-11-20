extends RefCounted
# D4: viewport-independent read-only inventory presentation and safe,
# explicit player commands. UI state is not part of the world save.
const Nav = preload("res://scripts/ai/navigation.gd")
const ROW_HEIGHT := 47.0
const PANEL_MARGIN := 10.0
const PANEL_MAX_HEIGHT := 494.0
const HEADER_HEIGHT := 83.0
const FOOTER_HEIGHT := 148.0

var visible := false
var holder_id := ""
var view_kind := ""
var focus_citizen_id := 0
var selected_key := ""
var scroll := 0
var notice := ""

func open_for(world: RefCounted, holder: String, kind: String = "") -> bool:
    if world.inventory._holder(world, holder).is_empty():
        return false
    if holder.begins_with("ground:") and world.inventory.balances.get(holder, {}).is_empty():
        return false
    holder_id = holder
    view_kind = kind if kind != "" else holder.get_slice(":", 0)
    if holder.begins_with("citizen:"):
        focus_citizen_id = int(holder.get_slice(":", 1))
    selected_key = ""
    scroll = 0
    notice = ""
    visible = true
    return true

func close() -> void:
    visible = false
    selected_key = ""
    notice = ""
    scroll = 0

func actor(world: RefCounted) -> Dictionary:
    return world.inventory._person(world, focus_citizen_id) if focus_citizen_id > 0 else {}

func actor_ready(world: RefCounted) -> bool:
    var person := actor(world)
    return not person.is_empty() and int(person.get("hp", 0)) > 0

func rows_for(world: RefCounted) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    if holder_id == "" or world.inventory._holder(world, holder_id).is_empty():
        return result
    var store: Dictionary = world.inventory.balances.get(holder_id, {})
    var ids: Array = store.keys()
    ids.sort()
    for id in ids:
        var item_id := str(id)
        var quantity := int(store[id])
        if quantity <= 0:
            continue
        var definition: Dictionary = world.inventory.catalogue.item(item_id)
        if definition.is_empty():
            continue
        if world.toolmaking._managed(item_id):
            var serials: Array[String] = world.toolmaking._matching_serials(holder_id, item_id)
            for serial in serials:
                var inst: Dictionary = world.toolmaking.instances[serial]
                var maximum := maxi(1, int(inst["max_condition"]))
                result.append({"key": "serial:" + serial, "item_id": item_id,
                    "serial": serial, "quantity": 1,
                    "name": str(definition["name"]),
                    "condition": int(inst["condition"]), "max_condition": maximum,
                    "quality": int(inst.get("quality", 50)),
                    "condition_pct": int(round(100.0 * int(inst["condition"]) / float(maximum))),
                    "equipped": _equipped(world, serial),
                    "weight_kg": float(definition["physical"].get("mass_kg", 0.0))})
        else:
            result.append({"key": "stack:" + item_id, "item_id": item_id,
                "serial": "", "quantity": quantity, "name": str(definition["name"]),
                "condition": -1, "max_condition": -1, "condition_pct": -1,
                "quality": -1, "equipped": false,
                "weight_kg": float(definition["physical"].get("mass_kg", 0.0)) * quantity})
    return result

func _equipped(world: RefCounted, serial: String) -> bool:
    for id in world.toolmaking.equipped:
        if str(world.toolmaking.equipped[id]) == serial:
            return true
    return false

func item_key(world: RefCounted) -> Dictionary:
    var rows: Array[Dictionary] = rows_for(world)
    for entry in rows:
        if str(entry["key"]) == selected_key:
            return entry
    return {}

func sync(world: RefCounted) -> void:
    if not visible:
        return
    if world.inventory._holder(world, holder_id).is_empty():
        close()
        return
    var rows := rows_for(world)
    scroll = clampi(scroll, 0, maxi(0, rows.size() - 1))
    if rows.is_empty():
        selected_key = ""
        return
    for row in rows:
        if str(row["key"]) == selected_key:
            return
    selected_key = str(rows[0]["key"])

func title_for(world: RefCounted) -> String:
    match view_kind:
        "citizen":
            return "CITIZEN #%d   /   PACK" % int(holder_id.get_slice(":", 1))
        "workshop":
            return "TOOL AREA   /   WORKSHOP"
        "settlement":
            return "SETTLEMENT %d   /   STORES" % (int(holder_id.get_slice(":", 1)) + 1)
        "ground":
            return "GROUND CACHE   /   DROPS"
    return "ITEMS"

func subtitle_for(world: RefCounted) -> String:
    var stores: Dictionary = world.inventory.balances.get(holder_id, {})
    var units := 0
    var load := 0.0
    for id in stores:
        units += int(stores[id])
        var item: Dictionary = world.inventory.catalogue.item(str(id))
        load += float(item.get("physical", {}).get("mass_kg", 0.0)) * int(stores[id])
    var second := "Inspect only - tap a citizen to issue actions"
    if focus_citizen_id > 0:
        second = "Acting citizen #%d" % focus_citizen_id
    return "%d units  |  %.1f kg  |  %s" % [units, load, second]

func geometry(viewport: Vector2, toolbar: float = 188.0) -> Dictionary:
    var left := PANEL_MARGIN
    var top := 54.0
    var width := maxf(250.0, viewport.x - PANEL_MARGIN * 2.0)
    var height := minf(PANEL_MAX_HEIGHT, maxf(320.0, viewport.y - toolbar - top - 8.0))
    var bounds := Rect2(Vector2(left, top), Vector2(width, height))
    var rows_y := top + HEADER_HEIGHT
    var rows_height := maxf(ROW_HEIGHT * 2.0, height - HEADER_HEIGHT - FOOTER_HEIGHT)
    var visible_rows := maxi(2, int(floor(rows_height / ROW_HEIGHT)))
    var action_y := top + height - 62.0
    return {"panel": bounds, "close": Rect2(left + width - 49.0, top + 8.0, 40.0, 39.0),
        "tabs": [Rect2(left + 12.0, top + 45.0, 92.0, 29.0),
            Rect2(left + 110.0, top + 45.0, 92.0, 29.0)],
        "rows": Rect2(left + 9.0, rows_y, width - 18.0, float(visible_rows) * ROW_HEIGHT),
        "rows_count": visible_rows,
        "detail_y": rows_y + float(visible_rows) * ROW_HEIGHT + 15.0,
        "actions": Rect2(left + 9.0, action_y, width - 18.0, 43.0)}

func row_at(world: RefCounted, point: Vector2, size: Vector2, toolbar: float = 188.0) -> Dictionary:
    var g: Dictionary = geometry(size, toolbar)
    var rect: Rect2 = g["rows"]
    if not rect.has_point(point):
        return {}
    var rows := rows_for(world)
    var index := scroll + int(floor((point.y - rect.position.y) / ROW_HEIGHT))
    return rows[index] if index >= 0 and index < rows.size() else {}

func action_at(point: Vector2, size: Vector2, toolbar: float = 188.0) -> int:
    var g: Dictionary = geometry(size, toolbar)
    var rect: Rect2 = g["actions"]
    if not rect.has_point(point):
        return -1
    var width := rect.size.x / 3.0
    return clampi(int((point.x - rect.position.x) / width), 0, 2)

func scroll_by(world: RefCounted, delta_rows: int, size: Vector2, toolbar: float = 188.0) -> void:
    var rows := rows_for(world)
    var capacity := int(geometry(size, toolbar)["rows_count"])
    scroll = clampi(scroll + delta_rows, 0, maxi(0, rows.size() - capacity))

func _near(world: RefCounted, person: Dictionary, holder: String) -> bool:
    var source: Dictionary = world.inventory._holder(world, holder)
    if source.is_empty() or person.is_empty():
        return false
    return Nav.manhattan(Vector2i(int(person["x"]), int(person["y"])), source["cell"]) <= 1

func _craftsman(world: RefCounted, person: Dictionary) -> bool:
    if person.is_empty():
        return false
    var nation := int(person["nation"])
    return world.occupations.enabled(world, nation, "stone_toolmaker") and \
        world.calendar.age_years(int(person.get("birth_tick", world.tick)), world.tick) >= 13

func actions_for(world: RefCounted) -> Array[Dictionary]:
    var actions: Array[Dictionary] = []
    var row := item_key(world)
    if row.is_empty():
        return actions
    var person := actor(world)
    var ready := actor_ready(world)
    var holder := holder_id
    var item_id := str(row["item_id"])
    var serial := str(row["serial"])
    var is_tool: bool = serial != "" and world.toolmaking.instances.has(serial)
    if holder.begins_with("citizen:"):
        var owner_id := int(holder.get_slice(":", 1))
        var owner_ok := ready and int(person["id"]) == owner_id
        if is_tool:
            var equipped := str(world.toolmaking.equipped.get(str(owner_id), "")) == serial
            actions.append({"id": "unequip" if equipped else "equip",
                "label": "UNEQUIP" if equipped else "EQUIP",
                "enabled": owner_ok and (equipped or int(row["condition"]) > 0)})
        var tile := Vector2i(int(person.get("x", -1)), int(person.get("y", -1))) if owner_ok else Vector2i(-1, -1)
        actions.append({"id": "drop", "label": "DROP",
            "enabled": owner_ok and world.index_of(tile.x, tile.y) >= 0 and \
                world.at(tile.x, tile.y) not in [world.OCEAN, world.ASH]})
        actions.append({"id": "store", "label": "DEPOSIT",
            "enabled": owner_ok and _near(world, person,
                "settlement:" + str(person["nation"]))})
    elif holder.begins_with("settlement:"):
        var nation := int(holder.get_slice(":", 1))
        var eligible := ready and int(person["nation"]) == nation and _near(world, person, holder)
        actions.append({"id": "take", "label": "TAKE",
            "enabled": eligible and not (is_tool and int(row["condition"]) <= 0)})
        if is_tool:
            var repair_mat := str(world.toolmaking.REPAIR_INPUTS.get(item_id, ""))
            var can_repair: bool = eligible and _craftsman(world, person) and \
                int(row["condition"]) < int(row["max_condition"]) and \
                world.inventory.held(holder, repair_mat) > 0 and \
                not world.toolmaking.jobs.has(str(person["id"])) and \
                not world.construction.jobs.has(str(person["id"])) and \
                not world.food.jobs.has(str(person["id"]))
            actions.append({"id": "repair", "label": "QUEUE REPAIR",
                "enabled": can_repair})
    elif holder.begins_with("ground:"):
        actions.append({"id": "pick_up", "label": "PICK UP",
            "enabled": ready and _near(world, person, holder) and \
                world.at(int(person["x"]), int(person["y"])) not in [world.OCEAN, world.ASH]})
    return actions

func _transfer_selected(world: RefCounted, source: String, target: String) -> bool:
    var row := item_key(world)
    if row.is_empty() or focus_citizen_id <= 0:
        return false
    var serial := str(row["serial"])
    return world.inventory.transfer(world, source, target,
        {str(row["item_id"]): 1}, focus_citizen_id, serial)

func apply_action(world: RefCounted, key: String) -> bool:
    sync(world)
    var allowed := false
    for action in actions_for(world):
        if str(action["id"]) == key and bool(action["enabled"]):
            allowed = true
            break
    if not allowed:
        notice = "Action unavailable at this location"
        return false
    var row := item_key(world)
    var success := false
    var person := actor(world)
    match key:
        "equip":
            success = world.toolmaking.equip_owned(world, focus_citizen_id, str(row["serial"]))
        "unequip":
            success = world.toolmaking.unequip_owned(world, focus_citizen_id, str(row["serial"]))
        "drop":
            var index: int = world.index_of(int(person["x"]), int(person["y"]))
            success = _transfer_selected(world, holder_id, "ground:" + str(index))
        "store":
            success = _transfer_selected(world, holder_id,
                "settlement:" + str(person["nation"]))
        "take":
            success = _transfer_selected(world, holder_id,
                "citizen:" + str(focus_citizen_id))
        "pick_up":
            success = _transfer_selected(world, holder_id,
                "citizen:" + str(focus_citizen_id))
        "repair":
            success = world.toolmaking.request_repair(world, focus_citizen_id, str(row["serial"]))
    notice = "Command accepted" if success else "Blocked by distance, capacity or skill"
    sync(world)
    return success

func change_tab(world: RefCounted, tab: String) -> bool:
    if tab == "pack":
        if focus_citizen_id <= 0 or actor(world).is_empty():
            return false
        return open_for(world, "citizen:" + str(focus_citizen_id), "citizen")
    if tab == "stores":
        var nation := -1
        if not actor(world).is_empty():
            nation = int(actor(world)["nation"])
        elif holder_id.begins_with("settlement:"):
            nation = int(holder_id.get_slice(":", 1))
        if nation not in [0, 1]:
            return false
        var focus := focus_citizen_id
        if not open_for(world, "settlement:" + str(nation), "settlement"):
            return false
        focus_citizen_id = focus
        return true
    return false

func tap(world: RefCounted, point: Vector2, viewport: Vector2, toolbar: float = 188.0) -> bool:
    if not visible:
        return false
    var g: Dictionary = geometry(viewport, toolbar)
    if not (g["panel"] as Rect2).has_point(point):
        close()
        return true
    if (g["close"] as Rect2).has_point(point):
        close()
        return true
    var tabs: Array = g["tabs"]
    if (tabs[0] as Rect2).has_point(point):
        change_tab(world, "pack")
        return true
    if (tabs[1] as Rect2).has_point(point):
        change_tab(world, "stores")
        return true
    var selected := row_at(world, point, viewport, toolbar)
    if not selected.is_empty():
        selected_key = str(selected["key"])
        notice = ""
        return true
    var action_index := action_at(point, viewport, toolbar)
    if action_index >= 0:
        var actions := actions_for(world)
        if action_index < actions.size():
            apply_action(world, str(actions[action_index]["id"]))
        return true
    return true
