extends PanelContainer
## Native mobile presentation for the existing conserved physical-item model.
## All eligibility and transfer decisions remain in item_inspector.gd.
const Tokens = preload("res://scripts/ui/ui_tokens.gd")
var host: CanvasLayer
var model: RefCounted
var world: RefCounted
var title_label: Label
var summary: Label
var citizen_label: Label
var body_scroll: ScrollContainer
var list_scroll: ScrollContainer
var rows_box: VBoxContainer
var detail: Label
var notice: Label
var actions: HBoxContainer
var pack: Button
var stores: Button
var row_buttons := {}
var action_buttons := {}
var fingerprint := ""

func setup(hud: CanvasLayer) -> void:
    host = hud
    mouse_filter = Control.MOUSE_FILTER_STOP
    add_theme_stylebox_override("panel", Tokens.panel(true))
    var outer: VBoxContainer = host._column(self, 8)
    title_label = host._heading(outer, "INVENTORY", host.close_modal)
    body_scroll = Tokens.scroll()
    body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    outer.add_child(body_scroll)
    var body: VBoxContainer = host._column(body_scroll, 10)
    citizen_label = Tokens.label("", 13, Tokens.TEAL)
    citizen_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    citizen_label.clip_text = false
    body.add_child(citizen_label)
    summary = Tokens.label("", 12, Tokens.MUTED)
    summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    summary.clip_text = false
    body.add_child(summary)
    var tabs := HBoxContainer.new()
    tabs.add_theme_constant_override("separation", 8)
    body.add_child(tabs)
    pack = host._button("Pack", "pack")
    stores = host._button("Stores", "tools")
    for b in [pack, stores]:
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        tabs.add_child(b)
    pack.pressed.connect(func() -> void:
        model.change_tab(world, "pack")
        fingerprint = ""
        refresh()
    )
    stores.pressed.connect(func() -> void:
        model.change_tab(world, "stores")
        fingerprint = ""
        refresh()
    )
    list_scroll = Tokens.scroll()
    list_scroll.name = "PhysicalItems"
    list_scroll.custom_minimum_size.y = 180
    body.add_child(list_scroll)
    rows_box = host._column(list_scroll, 6)
    detail = Tokens.label("", 13)
    detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    detail.clip_text = false
    body.add_child(detail)
    actions = HBoxContainer.new()
    actions.add_theme_constant_override("separation", 6)
    body.add_child(actions)
    notice = Tokens.label("", 12, Tokens.TEAL)
    notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    notice.clip_text = false
    body.add_child(notice)
    resized.connect(func() -> void:
        list_scroll.custom_minimum_size.y = clampf(size.y * 0.34, 100, 210)
    )

func bind_model(state: RefCounted, simulation: RefCounted) -> void:
    model = state
    world = simulation
    fingerprint = ""
    body_scroll.scroll_vertical = 0
    list_scroll.scroll_vertical = 0
    refresh()

func _clear(container: Node) -> void:
    for child in container.get_children():
        if child is Button:
            host.buttons.erase(child)
        container.remove_child(child)
        child.queue_free()

func refresh() -> void:
    if model == null or world == null or not model.visible:
        return
    model.sync(world)
    var entries: Array = model.rows_for(world)
    var available: Array = model.actions_for(world)
    var person: Dictionary = model.actor(world)
    title_label.text = model.title_for(world).replace("   /   ", " · ")
    summary.text = model.subtitle_for(world).replace("  |  ", " · ")
    citizen_label.visible = not person.is_empty()
    if not person.is_empty():
        var years: int = world.calendar.age_years(int(person.get("birth_tick", world.tick)), world.tick)
        citizen_label.text = "%d years · Health %d / 100 · Civilisation %d" % [years, int(person.get("hp", 0)), int(person.get("nation", 0)) + 1]
    pack.disabled = person.is_empty()
    stores.disabled = person.is_empty() and not str(model.holder_id).begins_with("settlement:")
    host._set_selected(pack, str(model.holder_id).begins_with("citizen:"))
    host._set_selected(stores, str(model.holder_id).begins_with("settlement:"))
    # Only structural changes rebuild native rows; live condition/health updates
    # preserve scroll position, pointer capture and keyboard focus.
    var keys: Array[String] = []
    for entry in entries:
        keys.append(str(entry["key"]))
    var next := str(model.holder_id) + ":" + str(keys)
    if next != fingerprint:
        fingerprint = next
        _clear(rows_box)
        row_buttons.clear()
        if entries.is_empty():
            var empty := Tokens.label("Nothing stored here yet.\nItems appear as citizens gather and craft.", 14, Tokens.MUTED)
            empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
            empty.clip_text = false
            empty.custom_minimum_size.y = 90
            rows_box.add_child(empty)
        for entry in entries:
            var key := str(entry["key"])
            var b: Button = host._button("", "pack")
            b.custom_minimum_size.y = 60
            b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            b.caption_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            b.caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
            rows_box.add_child(b)
            row_buttons[key] = b
            b.pressed.connect(func() -> void:
                model.selected_key = key
                model.notice = ""
                refresh()
            )
    for entry in entries:
        var b: Button = row_buttons[str(entry["key"])]
        var suffix := " · Equipped" if bool(entry["equipped"]) else ""
        host._set_caption(b, "%s ×%d%s" % [str(entry["name"]), int(entry["quantity"]), suffix])
        host._set_selected(b, str(entry["key"]) == str(model.selected_key))
    var row: Dictionary = model.item_key(world)
    if row.is_empty():
        detail.text = "Select an item to see its details."
    elif str(row["serial"]) != "":
        detail.text = "%s\nCondition %d%% · Quality %d · %.1f kg\nSerial %s" % [str(row["name"]), int(row["condition_pct"]), int(row["quality"]), float(row["weight_kg"]), str(row["serial"])]
    else:
        detail.text = "%s · %d units · %.1f kg" % [str(row["name"]), int(row["quantity"]), float(row["weight_kg"])]
    var action_ids: Array[String] = []
    for action in available:
        action_ids.append(str(action["id"]))
    if str(actions.get_meta("keys", "")) != str(action_ids):
        _clear(actions)
        action_buttons.clear()
        actions.set_meta("keys", str(action_ids))
        for action in available:
            var id := str(action["id"])
            var b: Button = host._button(str(action["label"]).capitalize())
            b.custom_minimum_size.x = 68
            b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            actions.add_child(b)
            action_buttons[id] = b
            b.pressed.connect(func() -> void:
                model.apply_action(world, id)
                refresh()
            )
    for action in available:
        var b: Button = action_buttons[str(action["id"])]
        b.disabled = not bool(action["enabled"])
        b.modulate.a = 1.0 if not b.disabled else 0.45
    notice.text = str(model.notice)
    notice.visible = notice.text != ""
