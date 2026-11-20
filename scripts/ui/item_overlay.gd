extends RefCounted
# D4: compact modal inventory inspector, original porcelain/olive HUD styling.
# CanvasItem drawing is display-only; all commands live in item_inspector.gd.
const Art = preload("res://scripts/ui/item_pixel_art.gd")
const BACK := Color("#182a28")
const SURFACE := Color("#233b37")
const PANEL := Color("#293e38")
const BORDER := Color("#7b8e75")
const GOLD := Color("#dcc49c")
const IVORY := Color("#efe5d2")
const MUTED := Color("#afc0b2")
const GREEN := Color("#829d7e")

static func _label(canvas: CanvasItem, font: Font, message: String, pos: Vector2,
        size: int, color: Color = IVORY, width: float = -1.0) -> void:
    canvas.draw_string(font, pos, message, HORIZONTAL_ALIGNMENT_LEFT, width, size, color)

static func _rect(canvas: CanvasItem, rect: Rect2, fill: Color, outline: Color = BORDER) -> void:
    canvas.draw_rect(rect, fill)
    canvas.draw_rect(rect, outline, false, 1.0)

static func draw_chip(canvas: CanvasItem, font: Font, viewport: Vector2, toolbar: float,
        active: bool = false) -> void:
    var rect := Rect2(viewport.x - 111.0, viewport.y - toolbar + 3.0, 99.0, 24.0)
    _rect(canvas, rect, GOLD if active else Color("#344c43"))
    _label(canvas, font, "ITEMS", rect.position + Vector2(25, 17), 12,
        BACK if active else IVORY)
    Art.draw_item(canvas, "stone_axe", rect.position + Vector2(13, 12), 1.15)

static func _tab(canvas: CanvasItem, font: Font, rect: Rect2, name: String,
        active: bool, usable: bool) -> void:
    var fill := GOLD if active else Color("#314d46") if usable else Color("#293a36")
    _rect(canvas, rect, fill, GOLD if active else Color("#5f786b"))
    _label(canvas, font, name, rect.position + Vector2(10.0, 18.0), 11,
        BACK if active else IVORY if usable else Color("#7b9287"))

static func draw_panel(canvas: CanvasItem, font: Font, world: RefCounted,
        inspector: RefCounted, viewport: Vector2, toolbar: float = 188.0) -> void:
    if not inspector.visible:
        return
    inspector.sync(world)
    if not inspector.visible:
        return
    var g: Dictionary = inspector.geometry(viewport, toolbar)
    var bounds: Rect2 = g["panel"]
    canvas.draw_rect(Rect2(0.0, 50.0, viewport.x,
        viewport.y - toolbar - 50.0), Color(0.04, 0.09, 0.08, 0.56))
    canvas.draw_rect(Rect2(bounds.position + Vector2(3, 5),
        bounds.size), Color(0.03, 0.06, 0.05, 0.56))
    _rect(canvas, bounds, BACK, Color("#819d88"))
    canvas.draw_rect(Rect2(bounds.position, Vector2(bounds.size.x, 39)), SURFACE)
    canvas.draw_rect(Rect2(bounds.position.x + 1, bounds.position.y + 39,
        bounds.size.x - 2, 1.0), GOLD)
    _label(canvas, font, inspector.title_for(world),
        bounds.position + Vector2(13, 26), 15, IVORY, bounds.size.x - 62)
    var close: Rect2 = g["close"]
    _rect(canvas, close, Color("#405549"))
    _label(canvas, font, "X", close.position + Vector2(13, 27), 18, GOLD)
    var tabs: Array = g["tabs"]
    _tab(canvas, font, tabs[0], "PACK", inspector.view_kind == "citizen",
        inspector.focus_citizen_id > 0)
    _tab(canvas, font, tabs[1], "STORES",
        inspector.holder_id.begins_with("settlement:"), true)
    var rows: Array[Dictionary] = inspector.rows_for(world)
    var area: Rect2 = g["rows"]
    var row_capacity: int = int(g["rows_count"])
    for slot in range(row_capacity):
        var y: float = area.position.y + float(slot) * inspector.ROW_HEIGHT
        var rect := Rect2(area.position + Vector2(0, float(slot) * inspector.ROW_HEIGHT),
            Vector2(area.size.x, inspector.ROW_HEIGHT - 2))
        var index: int = inspector.scroll + slot
        var selected: bool = index < rows.size() and str(rows[index]["key"]) == inspector.selected_key
        _rect(canvas, rect, Color("#405c4e") if selected else
            Color("#293f39") if posmod(slot, 2) == 0 else Color("#263a34"),
            GOLD if selected else Color("#3f5b4e"))
        if index >= rows.size():
            continue
        var entry: Dictionary = rows[index]
        Art.draw_item(canvas, str(entry["item_id"]),
            rect.position + Vector2(24, 23), 2.3)
        var name := str(entry["name"])
        if name.length() > 19:
            name = name.substr(0, 18) + "…"
        _label(canvas, font, name, rect.position + Vector2(46, 18), 12,
            IVORY, rect.size.x - 105)
        var suffix := "x%d" % int(entry["quantity"])
        if str(entry["serial"]) != "":
            suffix = "#%s" % str(entry["serial"])
        _label(canvas, font, suffix, rect.position + Vector2(rect.size.x - 65, 20),
            11, GOLD)
        var second := "Stored cargo  |  %.1f kg" % float(entry["weight_kg"])
        if str(entry["serial"]) != "":
            second = "%d%% condition  |  Q%d" % [
                int(entry["condition_pct"]), int(entry["quality"])]
            if bool(entry["equipped"]):
                second += "  |  HELD"
        _label(canvas, font, second, rect.position + Vector2(46, 36), 10, MUTED,
            rect.size.x - 55)
        if str(entry["serial"]) != "":
            var fill := clampf(float(entry["condition_pct"]) / 100.0, 0.0, 1.0)
            canvas.draw_rect(Rect2(rect.position + Vector2(3, 3),
                Vector2(3.0, rect.size.y - 6.0)), Color("#1f2e29"))
            canvas.draw_rect(Rect2(rect.position + Vector2(3, 3 + (rect.size.y - 6.0) * (1.0 - fill)),
                Vector2(3.0, (rect.size.y - 6.0) * fill)),
                Art.condition_color(int(entry["condition_pct"])))
    if rows.is_empty():
        _label(canvas, font, "No physical items held here.",
            area.position + Vector2(12, 34), 13, MUTED)
    elif rows.size() > row_capacity:
        _label(canvas, font, "%d - %d of %d  /  swipe" % [
            inspector.scroll + 1, mini(rows.size(), inspector.scroll + row_capacity),
            rows.size()], Vector2(area.position.x + 2, area.end.y + 12), 10, MUTED)
    var selected_row: Dictionary = inspector.item_key(world)
    var detail_y: float = float(g["detail_y"])
    if not selected_row.is_empty():
        var item_id := str(selected_row["item_id"])
        var definition: Dictionary = world.inventory.catalogue.item(item_id)
        _label(canvas, font, str(definition.get("name", item_id)).to_upper(),
            Vector2(bounds.position.x + 13, detail_y + 3), 13, GOLD,
            bounds.size.x - 24)
        var detail := "Units: %d  |  %.1f kg  |  Era %d" % [
            int(selected_row["quantity"]), float(selected_row["weight_kg"]),
            int(definition.get("first_era", 1))]
        if str(selected_row["serial"]) != "":
            detail = "Serial #%s  |  Condition %d/%d" % [
                str(selected_row["serial"]), int(selected_row["condition"]),
                int(selected_row["max_condition"])]
        _label(canvas, font, detail, Vector2(bounds.position.x + 13, detail_y + 23),
            11, MUTED, bounds.size.x - 24)
    var status := str(inspector.notice)
    if status == "":
        status = inspector.subtitle_for(world)
    if status.length() > 63:
        status = status.substr(0, 62) + "…"
    _label(canvas, font, status,
        Vector2(bounds.position.x + 13, bounds.end.y - 75.0), 10, GOLD,
        bounds.size.x - 24)
    var actions: Array[Dictionary] = inspector.actions_for(world)
    var action_rect: Rect2 = g["actions"]
    var button_w := action_rect.size.x / 3.0
    for i in range(3):
        var b := Rect2(action_rect.position + Vector2(button_w * i + 1, 1),
            Vector2(button_w - 4, action_rect.size.y - 2))
        var has_action := i < actions.size()
        var usable := has_action and bool(actions[i]["enabled"])
        var fill := Color("#718e76") if usable else Color("#2a403a")
        _rect(canvas, b, fill, GOLD if usable else Color("#486157"))
        if has_action:
            var text_value := str(actions[i]["label"])
            if text_value.length() > 14:
                text_value = text_value.substr(0, 14)
            var text_w: float = float(text_value.length()) * 6.2
            _label(canvas, font, text_value, b.position + Vector2(
                maxf(7.0, (b.size.x - text_w) * 0.5), 26), 11,
                IVORY if usable else Color("#70897d"))
