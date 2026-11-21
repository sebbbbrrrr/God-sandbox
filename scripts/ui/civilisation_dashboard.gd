extends CanvasLayer
class_name CivilisationDashboard
## Mobile village / town observatory. All figures come from CivilisationInsights.
## No simulation state is mutated by the inspector.
signal focus_requested(cell: Vector2i)
signal route_visibility_changed(enabled: bool)

const Insights = preload("res://scripts/ui/civilisation_insights.gd")
const DARK := Color("#142620")
const SURFACE := Color("#213831")
const RAISED := Color("#2b473c")
const GOLD := Color("#e7c88d")
const IVORY := Color("#f5eddc")
const MUTED := Color("#adbfaf")
const GOOD := Color("#83bd91")
const WARNING := Color("#d7ae72")
const DANGER := Color("#df8e81")

var world: RefCounted
var is_open := false
var show_routes := false
var selected_id := -1
var current_tab := 0
var snapshot: Dictionary = {}
var last_tick := -1
var refresh_clock := 0.0
var root: Control
var shade: ColorRect
var sheet: PanelContainer
var picker: OptionButton
var map_button: CheckButton
var tab_buttons: Array[Button] = []
var scroller: ScrollContainer
var content: VBoxContainer
var heading: Label

func setup(source: RefCounted) -> void:
    world = source
    if root != null:
        refresh(true)

func _ready() -> void:
    layer = 25
    _build()
    get_viewport().size_changed.connect(_layout)
    _layout()


func _style(color: Color, radius: int = 13, border: bool = false) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = color
    box.set_corner_radius_all(radius)
    box.set_content_margin_all(7)
    if border:
        box.set_border_width_all(1)
        box.border_color = Color("#829682", 0.48)
    return box


func _label(text: String, size: int = 13, color: Color = IVORY, wrap: bool = false) -> Label:
    var node := Label.new()
    node.text = text
    node.add_theme_color_override("font_color", color)
    node.add_theme_font_size_override("font_size", size)
    node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
    node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return node


func _button(text: String, min_width: float = 44.0) -> Button:
    var node := Button.new()
    node.text = text
    node.custom_minimum_size = Vector2(min_width, 44)
    node.add_theme_color_override("font_color", IVORY)
    node.add_theme_color_override("font_hover_color", IVORY)
    node.add_theme_font_size_override("font_size", 12)
    node.add_theme_stylebox_override("normal", _style(RAISED, 9))
    node.add_theme_stylebox_override("hover", _style(Color("#3e5e4c"), 9))
    node.add_theme_stylebox_override("pressed", _style(Color("#58715b"), 9))
    node.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
    return node


func _build() -> void:
    root = Control.new()
    root.name = "CivilisationInterface"
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(root)
    shade = ColorRect.new()
    shade.color = Color(0.015, 0.03, 0.028, 0.63)
    shade.mouse_filter = Control.MOUSE_FILTER_STOP
    shade.visible = false
    root.add_child(shade)
    shade.gui_input.connect(func(event: InputEvent) -> void:
        if event is InputEventMouseButton and event.pressed:
            close()
    )
    sheet = PanelContainer.new()
    sheet.name = "CivilisationSheet"
    sheet.add_theme_stylebox_override("panel", _style(SURFACE, 17, true))
    sheet.mouse_filter = Control.MOUSE_FILTER_STOP
    sheet.visible = false
    root.add_child(sheet)

    var layout := VBoxContainer.new()
    layout.add_theme_constant_override("separation", 8)
    sheet.add_child(layout)
    var headline := HBoxContainer.new()
    headline.add_theme_constant_override("separation", 4)
    layout.add_child(headline)
    var title := _label("CIVILISATION", 16, GOLD)
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    headline.add_child(title)
    map_button = CheckButton.new()
    map_button.text = "Routes"
    map_button.tooltip_text = "Draw real road connections and settlement markers on the world"
    map_button.custom_minimum_size = Vector2(78, 44)
    map_button.add_theme_color_override("font_color", IVORY)
    headline.add_child(map_button)
    map_button.toggled.connect(_on_map_toggled)
    var focus := _button("Locate", 58)
    focus.pressed.connect(_focus_selected)
    headline.add_child(focus)
    var dismiss := _button("X", 43)
    dismiss.pressed.connect(close)
    headline.add_child(dismiss)

    heading = _label("SELECT A SETTLEMENT", 10, MUTED)
    layout.add_child(heading)
    picker = OptionButton.new()
    picker.custom_minimum_size.y = 46
    picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    picker.add_theme_stylebox_override("normal", _style(DARK, 9, true))
    picker.add_theme_stylebox_override("hover", _style(RAISED, 9))
    picker.add_theme_color_override("font_color", IVORY)
    picker.add_theme_color_override("font_hover_color", IVORY)
    picker.add_theme_font_size_override("font_size", 13)
    picker.item_selected.connect(_on_picker)
    layout.add_child(picker)

    var tabs := HBoxContainer.new()
    tabs.add_theme_constant_override("separation", 3)
    layout.add_child(tabs)
    for name in ["Overview", "Economy", "Routes", "People", "History"]:
        var index := tab_buttons.size()
        var button := _button(name, 0)
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        button.custom_minimum_size.y = 43
        button.add_theme_font_size_override("font_size", 11)
        button.pressed.connect(func() -> void: _switch_tab(index))
        tabs.add_child(button)
        tab_buttons.append(button)

    scroller = ScrollContainer.new()
    scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroller.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroller.mouse_filter = Control.MOUSE_FILTER_STOP
    layout.add_child(scroller)
    content = VBoxContainer.new()
    content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    content.add_theme_constant_override("separation", 8)
    scroller.add_child(content)

    var caption := _label("LIVE SIMULATION  ·  readings update on world ticks", 10, MUTED)
    caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    layout.add_child(caption)


func _layout() -> void:
    if root == null:
        return
    var size := get_viewport().get_visible_rect().size
    root.size = size
    shade.position = Vector2.ZERO
    shade.size = size
    var landscape := size.x > size.y * 1.18
    if landscape:
        var width := minf(490.0, maxf(320.0, size.x * 0.54))
        sheet.position = Vector2(size.x - width - 8, 8)
        sheet.size = Vector2(width, size.y - 16)
    else:
        sheet.position = Vector2(8, minf(82.0, size.y * 0.12))
        sheet.size = Vector2(size.x - 16, size.y - sheet.position.y - 88)


func _process(delta: float) -> void:
    if world == null or not (is_open or show_routes):
        return
    refresh_clock += delta
    if refresh_clock >= 0.65 and int(world.tick) != last_tick:
        refresh_clock = 0.0
        refresh()


func refresh(force: bool = false) -> void:
    if world == null or root == null:
        return
    if not force and int(world.tick) == last_tick:
        return
    snapshot = Insights.capture(world)
    last_tick = int(world.tick)
    if selected_id < 0 or _selected().is_empty():
        var rows: Array = snapshot.get("settlements", [])
        selected_id = int(rows[0]["id"]) if not rows.is_empty() else -1
    _update_picker()
    if is_open:
        _render()
    route_visibility_changed.emit(show_routes)


func _update_picker() -> void:
    picker.clear()
    var count := 0
    for entry in snapshot.get("settlements", []):
        var row: Dictionary = entry
        var label := "%s · %s · %d residents" % [str(row["name"]),
            str(row["status"]).capitalize(), int(row["population"])]
        picker.add_item(label, int(row["id"]))
        if int(row["id"]) == selected_id:
            count = picker.item_count - 1
    if picker.item_count > 0:
        picker.select(count)


func _on_picker(index: int) -> void:
    selected_id = picker.get_item_id(index)
    _render(false)


func open_for(id: int = -1) -> void:
    if id >= 0:
        selected_id = id
    is_open = true
    shade.visible = true
    sheet.visible = true
    _layout()
    refresh(true)


func close() -> void:
    is_open = false
    shade.visible = false
    sheet.visible = false


func toggle() -> void:
    if is_open:
        close()
    else:
        open_for()


func _on_map_toggled(enabled: bool) -> void:
    show_routes = enabled
    if enabled:
        refresh(true)
    else:
        route_visibility_changed.emit(false)


func _focus_selected() -> void:
    var row := _selected()
    if row.is_empty():
        return
    focus_requested.emit(Vector2i(int(row["x"]), int(row["y"])))
    close()


func _selected() -> Dictionary:
    for entry in snapshot.get("settlements", []):
        if int(entry["id"]) == selected_id:
            return entry
    return {}


func _switch_tab(tab: int) -> void:
    current_tab = tab
    _render(false)
    scroller.scroll_vertical = 0


func _clear_content() -> void:
    for child in content.get_children():
        content.remove_child(child)
        child.queue_free()


func _section(title: String) -> void:
    var label := _label(title.to_upper(), 11, GOLD)
    content.add_child(label)


func _text(value: String, color: Color = MUTED) -> void:
    content.add_child(_label(value, 12, color, true))


func _stat(name: String, value: String) -> void:
    var line := HBoxContainer.new()
    line.add_theme_constant_override("separation", 8)
    var left := _label(name, 12, MUTED)
    var right := _label(value, 13, IVORY)
    right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    line.add_child(left)
    line.add_child(right)
    content.add_child(line)


func _bar(name: String, value: int, description: String = "", inverse: bool = false) -> void:
    var top := HBoxContainer.new()
    top.add_child(_label(name, 12, IVORY))
    var amount := _label("%d%%" % value if value >= 0 else "Not assessed", 12, GOLD)
    amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    top.add_child(amount)
    content.add_child(top)
    var bar := ProgressBar.new()
    bar.min_value = 0
    bar.max_value = 100
    bar.value = clampi(value, 0, 100)
    bar.show_percentage = false
    bar.custom_minimum_size.y = 12
    var tint := MUTED if value < 0 else (DANGER if value >= 70 else (WARNING if value >= 40 else GOOD)) if inverse else (GOOD if value >= 70 else (WARNING if value >= 40 else DANGER))
    bar.add_theme_stylebox_override("background", _style(DARK, 5))
    bar.add_theme_stylebox_override("fill", _style(tint, 5))
    content.add_child(bar)
    if description != "":
        _text(description)


func _notice(text: String, color: Color = WARNING) -> void:
    var p := PanelContainer.new()
    p.add_theme_stylebox_override("panel", _style(Color("#2c3b34"), 8, true))
    p.add_child(_label(text, 12, color, true))
    content.add_child(p)


func _goto_button(id: int, title: String) -> void:
    var button := _button(title)
    button.pressed.connect(func() -> void:
        selected_id = id
        current_tab = 0
        _update_picker()
        _render(false)
        scroller.scroll_vertical = 0
    )
    content.add_child(button)


func _render(keep_scroll: bool = true) -> void:
    if not is_open:
        return
    var retained := scroller.scroll_vertical
    _clear_content()
    for i in range(tab_buttons.size()):
        var button := tab_buttons[i]
        button.add_theme_stylebox_override("normal",
            _style(GOLD if i == current_tab else RAISED, 9))
        button.add_theme_color_override("font_color", DARK if i == current_tab else IVORY)
    var row := _selected()
    if row.is_empty():
        _text("No settlement records in this world.")
        return
    heading.text = "NATION %d  ·  SETTLEMENT #%d  ·  %s" % [
        int(row["nation"]) + 1, int(row["id"]), str(row["specialisation"]).capitalize()]
    match current_tab:
        0: _overview(row)
        1: _economy(row)
        2: _routes(row)
        3: _people(row)
        4: _history(row)
    if keep_scroll:
        scroller.set_deferred("scroll_vertical", retained)


func _overview(row: Dictionary) -> void:
    var world_info: Dictionary = snapshot.get("summary", {})
    _section("Whole world")
    _stat("Settlements / active", "%d / %d" % [
        int(world_info.get("total", 0)), int(world_info.get("active", 0))])
    _stat("Residents / active construction", "%d / %d" % [
        int(world_info.get("population", 0)), int(world_info.get("projects", 0))])
    _stat("Connected / blocked routes", "%d / %d" % [
        int(world_info.get("connected", 0)), int(world_info.get("blocked", 0))])
    _section("%s · %s" % [str(row["name"]), str(row["status"]).capitalize()])
    _stat("Population", str(row["population"]))
    _stat("Specialisation", str(row["specialisation"]).capitalize())
    _stat("Position", "%d, %d" % [int(row["x"]), int(row["y"])])
    _bar("Planner prosperity", int(row["prosperity"]) if row["prosperity_assessed"] else -1,
        "The simulation's existing planning score, not economic GDP.")
    _bar("Housing coverage", int(row["housing_pct"]),
        "%d resident places for %d people" % [int(row["housing"]), int(row["population"])])
    _bar("Depot food buffer", int(row["food_pct"]),
        "Benchmark: 3 depot food units per resident; excludes household pantries.")
    _bar("Resident health", int(row["health_pct"]),
        "Mean live citizen health, not an estimate of happiness.")
    _section("Bottlenecks")
    for issue in row["alerts"]:
        _notice(str(issue), DANGER if str(issue).contains("struggling") or str(issue).contains("hazards") else WARNING)
    _section("Working well")
    if row["strengths"].is_empty():
        _text("No strength currently meets the display thresholds.")
    for strength in row["strengths"]:
        _notice(str(strength), GOOD)


func _economy(row: Dictionary) -> void:
    _section("Resources & production")
    _stat("Depot food", "%d units" % int(row["food"]))
    _stat("Wood stock", str(row["materials"].get("wood", 0)))
    _stat("Stone stock", str(row["materials"].get("stone", 0)))
    var others: Array = row["materials"].keys()
    others.sort()
    for good in others:
        if str(good) not in ["wood", "stone"] and int(row["materials"][good]) > 0:
            _stat(str(good).capitalize(), str(row["materials"][good]))
    _stat("Active farms", str(row["farms"]))
    _stat("Standing buildings", str(row["buildings"]))
    _section("Current jobs")
    _stat("Unique assigned workers", str(row["active_workers"]))
    var jobs: Dictionary = row["jobs"]
    var keys: Array = jobs.keys()
    keys.sort()
    if keys.is_empty():
        _text("No work assignments running at this tick.")
    for name in keys:
        _stat(str(name), str(jobs[name]))
    _section("Construction queue")
    if row["projects"].is_empty():
        _text("No building projects currently queued.")
    for project in row["projects"]:
        _notice("%s  ·  #%d%s" % [str(project["definition"]).replace("_", " ").capitalize(),
            int(project["id"]), "  ·  PAUSED" if project["paused"] else ""],
            DANGER if project["paused"] else IVORY)
        _stat("Labour completed / remaining", "%d / %d" % [
            int(project["progress"]), int(project["remaining_labour"])])
        if not project["pending"].is_empty():
            for good in project["pending"]:
                _stat("%s still to deliver" % str(good).capitalize(), str(project["pending"][good]))
        if str(project["reason"]) != "":
            _text("Hold reason: %s" % str(project["reason"]))
    _section("Regional conditions")
    var plan: Dictionary = row["plan"]
    if plan.is_empty():
        _text("No local planner survey has been completed yet.")
    else:
        _stat("Carrying-capacity estimate", str(plan.get("carrying_capacity", "—")))
        _stat("Housing demand (planner)", str(plan.get("housing_demand", "—")))
        var resources: Dictionary = plan.get("resources", {})
        for item in ["land", "wood", "stone", "food", "hazards"]:
            _stat("Local surveyed %s" % item, str(resources.get(item, "—")))
        _text("These resource measurements are the planner's most recent survey, not depot stocks.")


func _routes(row: Dictionary) -> void:
    _section("Road and trading network")
    _stat("Built / building / blocked links", "%d / %d / %d" % [
        int(row["active_links"]), int(row["building_links"]), int(row["blocked_links"])])
    _stat("Pending local road tiles", str(row["road_queue"]))
    _stat("Active merchant journeys", str(row["traders"]))
    _text("Map: solid green = connected roads, dotted amber = planned, green dots = built segments, dotted red = blocked attempt. Citizens physically carry goods; an unbuilt route does not represent trade.")
    var found := 0
    for route in snapshot.get("routes", []):
        if selected_id not in [int(route["a"]), int(route["b"])]:
            continue
        found += 1
        var other := int(route["b"]) if int(route["a"]) == selected_id else int(route["a"])
        var name := _settlement_name(other)
        _notice("%s  ·  %s" % [name, str(route["status"]).capitalize()],
            GOOD if str(route["status"]) == "connected" else WARNING)
        _stat("Road cells built / needed", "%d / %d" % [
            int(route["built"]), int(route["required"])])
        if int(route["required"]) > 0:
            _bar("Construction progress", clampi(roundi(100.0 * float(route["built"]) /
                float(route["required"])), 0, 100))
        _goto_button(other, "View " + name)
    if found == 0:
        _text("No planned link touches this settlement yet.")
    _section("Physical trade history")
    _stat("All completed barters", str(snapshot["summary"].get("completed_trades", 0)))
    _stat("All completed food-relief deliveries", str(snapshot["summary"].get("relief", 0)))
    var recent := 0
    for trade in snapshot.get("trades", []):
        if selected_id not in [int(trade.get("from", -1)), int(trade.get("to", -1))]:
            continue
        recent += 1
        _text("Tick %d · %s → %s · sent %s / received %s" % [int(trade.get("tick", 0)),
            _settlement_name(int(trade["from"])), _settlement_name(int(trade["to"])),
            str(trade.get("export", "?")), str(trade.get("import", "?"))])
    if recent == 0:
        _text("No recent recorded deliveries involving this settlement.")
    _section("Observed social connections")
    var social_count := 0
    for tie in snapshot.get("social", []):
        if selected_id not in [int(tie["a"]), int(tie["b"])]:
            continue
        social_count += 1
        var other := int(tie["b"]) if int(tie["a"]) == selected_id else int(tie["a"])
        _stat(_settlement_name(other), "%d personal ties · %d%% avg trust" % [
            int(tie["ties"]), int(tie["trust"])])
    if social_count == 0:
        _text("No cross-settlement personal relationships observed.")
    _text("Social ties are individual AI memories, not formal diplomatic alliances.")


func _settlement_name(id: int) -> String:
    for entry in snapshot.get("settlements", []):
        if int(entry["id"]) == id:
            return str(entry["name"])
    return "Settlement #%d" % id


func _people(row: Dictionary) -> void:
    _section("Population & society")
    _stat("Residents", str(row["population"]))
    _stat("Households", str(row["families"]))
    _stat("Active workers", str(row["active_workers"]))
    _bar("Resident health", int(row["health_pct"]))
    _bar("Average hunger", int(row["hunger_pct"]),
        "Higher hunger means worse nutrition; this bar is a burden, not a success score.", true)
    _stat("Settlement stress", "%d ticks" % int(row["stress"]))
    _stat("Safety assessment", "Safe" if int(row["security"]) == 100 else (
        "Hazards detected" if int(row["security"]) == 0 else "Not yet assessed"))
    _section("Local social network")
    _stat("Distinct observed relationships", str(row["ties"]))
    _stat("Ties with other towns", str(row["cross_ties"]))
    if int(row["ties"]) > 0:
        _bar("Mean observed trust", int(row["trust"]))
        _bar("Mean observed rivalry", int(row["rivalry"]),
            "Higher rivalry means stronger reported tensions, not better performance.", true)
    else:
        _text("Citizens have not recorded enough personal encounters yet.")
    _section("Development")
    _stat("Current speciality", str(row["specialisation"]).capitalize())
    _stat("Founded at tick", str(row["founded_tick"]))
    _text("Political affiliation is nation %d. Individual trust does not automatically represent a treaty, war, or an alliance." %
        (int(row["nation"]) + 1))


func _history(row: Dictionary) -> void:
    _section("Settlement history")
    var events: Array = row["history"]
    if events.is_empty():
        _text("No settlement milestones recorded yet.")
    for i in range(events.size() - 1, maxi(-1, events.size() - 25), -1):
        var event: Dictionary = events[i]
        _stat("Tick %d" % int(event.get("tick", 0)),
            str(event.get("kind", "")).replace("_", " ").capitalize())
    _section("Measurement notes")
    _text("All readings are current data or explicitly labelled derived ratios. The backend currently does not store historical population, happiness, productivity or GDP time series, so this interface does not fabricate growth charts.")


