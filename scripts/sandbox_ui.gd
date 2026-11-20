extends CanvasLayer
class_name GodSandboxHUD
## Presentation only. Stable power IDs and signals bridge to the game controller.
signal power_changed(power: int)
signal brush_changed(index: int)
signal pause_pressed
signal speed_pressed
signal save_pressed
signal reload_pressed
signal items_pressed
signal interaction_started

const Tokens = preload("res://scripts/ui/ui_tokens.gd")
const TouchButton = preload("res://scripts/ui/tactile_button.gd")
const InventorySheet = preload("res://scripts/ui/inventory_sheet.gd")
const POWER_NAMES := ["Raise land", "Fire", "Forest", "Bless", "Human", "Ocean"]
const POWER_ICONS := ["raise", "fire", "forest", "bless", "spawn", "ocean"]
const POWER_HINTS := ["Paint new land", "Ignite a tile", "Grow woodland", "Heal nearby life", "Place a citizen", "Paint deep water"]
const CATEGORIES := ["Terrain", "Nature", "Life", "Chaos", "World", "Menu"]
const CATEGORY_ICONS := ["raise", "forest", "spawn", "fire", "info", "settings"]
const CATEGORY_POWERS := [[0, 5], [2], [4, 3], [1], [], []]
const BRUSH_NAMES := ["Small", "Medium", "Large"]
const IVORY := Tokens.TEXT
const GOLD := Tokens.ACCENT
const MUTED := Tokens.MUTED

var active_power := -1
var active_category := 0
var active_brush := 1
var is_paused := false
var current_speed := 1
var palette_open := false
var reduced_motion := false
var haptics := true
var hud_hidden := false
var hidden_power := -1
var preferences_path := "user://interface.cfg"
var safe_override := Rect2() # Deterministic layout QA; zero uses platform safe area.
var safe_rect := Rect2()
var panel_tween: Tween
var inspector_tween: Tween
var toast_tween: Tween
var root: Control
var top_panel: PanelContainer
var dock_panel: PanelContainer
var context_panel: PanelContainer
var palette_panel: PanelContainer
var inspector_panel: PanelContainer
var modal_dim: ColorRect
var settings_panel: PanelContainer
var restore_panel: PanelContainer
var inventory_panel: PanelContainer
var status_line: Label
var caption_line: Label
var pause_button: Button
var speed_button: Button
var hide_button: Button
var palette_button: Button # Stable integration alias: Terrain category.
var hand_button: Button
var items_button: Button
var active_button: Button
var dock_brush_button: Button
var category_bar: HBoxContainer
var power_grid: GridContainer
var brush_row: HBoxContainer
var brush_buttons: Array[Button] = []
var category_buttons: Array[Button] = []
var power_buttons := {}
var inspector_title: Label
var inspector_body: Label
var motion_button: Button
var haptic_button: Button
var restore_button: Button
var inspector_content: Dictionary = {}
var buttons: Array[Button] = []
var palette_title: Label
var palette_hint: Label
var tool_content: VBoxContainer
var world_info: Label
var world_details := ""
var toast: PanelContainer
var toast_label: Label
var inventory_model: RefCounted
var world_ref: RefCounted

func _ready() -> void:
    layer = 10
    _load_preferences()
    _make_interface()
    get_viewport().size_changed.connect(_layout)
    _layout()

func _button(value: String, icon_name: String = "", width: float = 48, vertical: bool = false) -> Button:
    var b := TouchButton.new()
    b.setup(value, icon_name, vertical)
    b.custom_minimum_size.x = maxf(Tokens.TOUCH, width)
    b.reduced_motion = reduced_motion
    b.haptics = haptics
    b.tooltip_text = value if value != "" else icon_name.capitalize()
    b.button_down.connect(func() -> void:
        interaction_started.emit()
    )
    buttons.append(b)
    _set_selected(b, false)
    return b

func _set_selected(b: Button, selected: bool) -> void:
    b.set_selected(selected)

func _set_caption(b: Button, value: String) -> void:
    b.set_caption(value)

func _panel(parent: Node, node_name: String, raised: bool = false, padding: int = 12) -> PanelContainer:
    var p := PanelContainer.new()
    p.name = node_name
    p.mouse_filter = Control.MOUSE_FILTER_STOP
    p.add_theme_stylebox_override("panel", Tokens.panel(raised, padding))
    parent.add_child(p)
    return p

func _column(parent: Node, gap: int = 8) -> VBoxContainer:
    var col := VBoxContainer.new()
    col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    col.add_theme_constant_override("separation", gap)
    parent.add_child(col)
    return col

func _heading(parent: Node, title: String, close_action: Callable) -> Label:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    parent.add_child(row)
    var text_label := Tokens.label(title, 17, Tokens.ACCENT)
    text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(text_label)
    var close := _button("", "close")
    close.tooltip_text = "Close " + title.to_lower()
    close.pressed.connect(close_action)
    row.add_child(close)
    return text_label

func _make_interface() -> void:
    root = Control.new()
    root.name = "HUDRoot"
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(root)
    top_panel = _panel(root, "StatusBar", false, 6)
    var top := HBoxContainer.new()
    top.add_theme_constant_override("separation", 4)
    top_panel.add_child(top)
    var overview := _button("", "", 80)
    overview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    overview.tooltip_text = "World information"
    var wordmark := _column(overview, 0)
    wordmark.mouse_filter = Control.MOUSE_FILTER_IGNORE
    wordmark.alignment = BoxContainer.ALIGNMENT_CENTER
    wordmark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    wordmark.offset_left = 10
    wordmark.offset_right = -6
    status_line = Tokens.label("GOD SANDBOX", 13, Tokens.ACCENT)
    caption_line = Tokens.label("Year 1 · 0 people", 11, Tokens.MUTED)
    wordmark.add_child(status_line)
    wordmark.add_child(caption_line)
    overview.pressed.connect(func() -> void: _choose_category(4))
    top.add_child(overview)
    pause_button = _button("", "pause")
    pause_button.tooltip_text = "Pause simulation"
    speed_button = _button("1×")
    speed_button.tooltip_text = "Change simulation speed"
    hide_button = _button("", "eye")
    hide_button.tooltip_text = "Hide interface"
    for b in [pause_button, speed_button, hide_button]:
        top.add_child(b)
    pause_button.pressed.connect(func() -> void: pause_pressed.emit())
    speed_button.pressed.connect(func() -> void: speed_pressed.emit())
    hide_button.pressed.connect(func() -> void: set_hud_hidden(true))

    dock_panel = _panel(root, "CategoryDock", false, 6)
    category_bar = HBoxContainer.new()
    category_bar.add_theme_constant_override("separation", 2)
    dock_panel.add_child(category_bar)
    for i in range(CATEGORIES.size()):
        var index := i
        var b := _button(CATEGORIES[i], CATEGORY_ICONS[i], 48, true)
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        b.custom_minimum_size.y = 56
        b.caption_label.add_theme_font_size_override("font_size", 10)
        category_bar.add_child(b)
        category_buttons.append(b)
        b.pressed.connect(func() -> void: _choose_category(index))
    palette_button = category_buttons[0]

    context_panel = _panel(root, "ToolContext", false, 4)
    var context := HBoxContainer.new()
    context.add_theme_constant_override("separation", 4)
    context_panel.add_child(context)
    hand_button = _button("", "hand")
    hand_button.tooltip_text = "Hand: navigate and inspect"
    hand_button.pressed.connect(func() -> void:
        _choose_power(-1)
        open_palette(false)
    )
    context.add_child(hand_button)
    active_button = _button("Explore & inspect")
    active_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    active_button.pressed.connect(func() -> void:
        if active_power >= 0:
            _choose_power(-1)
        else:
            open_palette(not palette_open)
    )
    context.add_child(active_button)
    dock_brush_button = _button("M", "brush", 64)
    dock_brush_button.pressed.connect(func() -> void:
        _choose_brush((active_brush + 1) % 3)
        notify("%s brush" % BRUSH_NAMES[active_brush])
    )
    context.add_child(dock_brush_button)

    palette_panel = _panel(root, "ToolTray", true)
    var tray_outer := _column(palette_panel)
    palette_title = _heading(tray_outer, "TERRAIN", func() -> void: open_palette(false))
    var tool_scroll := Tokens.scroll()
    tool_scroll.name = "ToolScroll"
    tray_outer.add_child(tool_scroll)
    tool_content = _column(tool_scroll)
    power_grid = GridContainer.new()
    power_grid.columns = 2
    power_grid.add_theme_constant_override("h_separation", 8)
    power_grid.add_theme_constant_override("v_separation", 8)
    tool_content.add_child(power_grid)
    world_info = Tokens.label("", 14)
    world_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    world_info.clip_text = false
    tool_content.add_child(world_info)
    brush_row = HBoxContainer.new()
    brush_row.add_theme_constant_override("separation", 6)
    tool_content.add_child(brush_row)
    for i in range(3):
        var index := i
        var b := _button(BRUSH_NAMES[i])
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        brush_buttons.append(b)
        brush_row.add_child(b)
        b.pressed.connect(func() -> void: _choose_brush(index))
    palette_hint = Tokens.label("Choose a tool to shape your world.", 12, Tokens.MUTED)
    palette_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    palette_hint.clip_text = false
    tool_content.add_child(palette_hint)
    palette_panel.hide()

    inspector_panel = _panel(root, "TerrainInspector", true)
    var inspection := _column(inspector_panel)
    inspector_title = _heading(inspection, "TERRAIN", hide_inspector)
    inspector_body = Tokens.label("", 14)
    inspector_body.clip_text = false
    inspection.add_child(inspector_body)
    inspector_panel.hide()

    modal_dim = ColorRect.new()
    modal_dim.name = "ModalBackdrop"
    modal_dim.color = Color(0.02, 0.06, 0.08, 0.64)
    modal_dim.mouse_filter = Control.MOUSE_FILTER_STOP
    root.add_child(modal_dim)
    modal_dim.hide()
    modal_dim.gui_input.connect(func(event: InputEvent) -> void:
        if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            close_modal()
            get_viewport().set_input_as_handled()
    )
    settings_panel = _panel(root, "WorldMenu", true)
    var menu_outer := _column(settings_panel)
    _heading(menu_outer, "YOUR WORLD", func() -> void: _show_settings(false))
    var menu_scroll := Tokens.scroll()
    menu_outer.add_child(menu_scroll)
    var menu := _column(menu_scroll, 10)
    var menu_caption := Tokens.label("World files & preferences", 13, Tokens.MUTED)
    menu.add_child(menu_caption)
    items_button = _button("Inventory & stores", "pack")
    menu.add_child(items_button)
    items_button.pressed.connect(func() -> void:
        _show_settings(false)
        _choose_power(-1)
        items_pressed.emit()
    )
    var save := _button("Save world", "save")
    save.name = "SaveWorld"
    menu.add_child(save)
    save.pressed.connect(func() -> void: save_pressed.emit())
    restore_button = _button("Reload saved world", "load")
    restore_button.name = "ReloadWorld"
    menu.add_child(restore_button)
    restore_button.pressed.connect(_confirm_restore)
    motion_button = _button("")
    menu.add_child(motion_button)
    motion_button.pressed.connect(func() -> void:
        set_reduced_motion(not reduced_motion)
        _save_preferences()
    )
    haptic_button = _button("")
    menu.add_child(haptic_button)
    haptic_button.pressed.connect(func() -> void:
        haptics = not haptics
        _refresh_preferences()
        _save_preferences()
    )
    var guidance := Tokens.label("Hand: drag to move, tap to inspect.\nTerrain: drag to paint.\nTwo fingers: move and zoom.", 12, Tokens.MUTED)
    guidance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    guidance.clip_text = false
    menu.add_child(guidance)
    settings_panel.hide()

    restore_panel = _panel(root, "ConfirmReload", true)
    var confirm := _column(restore_panel, 12)
    _heading(confirm, "RELOAD WORLD?", _cancel_restore)
    var message := Tokens.label("Return to your last save? Changes since that save will be lost.", 14)
    message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    message.clip_text = false
    confirm.add_child(message)
    var cancel := _button("Keep playing", "back")
    confirm.add_child(cancel)
    cancel.pressed.connect(_cancel_restore)
    var reload := _button("Reload saved world", "load")
    confirm.add_child(reload)
    reload.pressed.connect(func() -> void:
        close_modal()
        reload_pressed.emit()
    )
    restore_panel.hide()

    inventory_panel = InventorySheet.new()
    inventory_panel.name = "InventorySheet"
    root.add_child(inventory_panel)
    inventory_panel.setup(self)
    inventory_panel.hide()
    var reveal := _button("", "eye")
    reveal.name = "RestoreHUD"
    reveal.tooltip_text = "Show interface"
    root.add_child(reveal)
    reveal.pressed.connect(func() -> void: set_hud_hidden(false))
    reveal.hide()
    toast = _panel(root, "Feedback", false, 10)
    toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
    toast_label = Tokens.label("", 13, Tokens.ACCENT)
    toast.add_child(toast_label)
    toast.hide()
    _rebuild_power_buttons()
    _refresh_preferences()
    _refresh_selection()

func _choose_category(index: int) -> void:
    interaction_started.emit()
    if index == 5:
        _show_settings(not settings_panel.visible)
        return
    if palette_open and active_category == index:
        open_palette(false)
        return
    active_category = clampi(index, 0, 4)
    _rebuild_power_buttons()
    if palette_open:
        _refresh_selection()
        _layout()
        _transition(palette_panel, true)
    else:
        open_palette(true)

func _rebuild_power_buttons() -> void:
    for child in power_grid.get_children():
        buttons.erase(child)
        power_grid.remove_child(child)
        child.queue_free()
    power_buttons.clear()
    palette_title.text = CATEGORIES[active_category].to_upper()
    world_info.visible = active_category == 4
    world_info.text = world_details
    power_grid.visible = active_category < 4
    for power in CATEGORY_POWERS[active_category]:
        var index: int = power
        var b := _button(POWER_NAMES[index], POWER_ICONS[index], 80, true)
        b.custom_minimum_size.y = 80
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        b.tooltip_text = POWER_HINTS[index]
        power_grid.add_child(b)
        power_buttons[index] = b
        b.pressed.connect(func() -> void: _choose_power(index))
    palette_hint.text = ["Drag to paint · Two fingers to navigate", "Drag to grow · Two fingers to navigate", "Tap to place or heal · Two fingers to navigate", "Tap a tile to ignite", "Live information from this world."][active_category]
    _refresh_selection()

func _choose_power(power: int) -> void:
    var next := -1 if power == active_power else power
    if power == -1:
        next = -1
    set_active_power(next)
    power_changed.emit(next)
    open_palette(false)
    if next >= 0:
        notify(POWER_HINTS[next])

func set_active_power(power: int) -> void:
    active_power = clampi(power, -1, POWER_NAMES.size() - 1)
    _refresh_selection()
    if active_power >= 0:
        hide_inspector()
    _layout()

func _choose_brush(index: int) -> void:
    set_brush(index)
    brush_changed.emit(active_brush)

func set_brush(index: int) -> void:
    active_brush = clampi(index, 0, 2)
    _refresh_selection()
    _layout()

func _refresh_selection() -> void:
    if hand_button == null:
        return
    _set_selected(hand_button, active_power == -1)
    _set_selected(active_button, active_power >= 0)
    _set_caption(active_button, "Explore & inspect" if active_power < 0 else POWER_NAMES[active_power] + "  ×")
    dock_brush_button.visible = active_power in [0, 2, 5]
    _set_caption(dock_brush_button, ["S", "M", "L"][active_brush])
    brush_row.visible = active_category < 4 and (active_power in [0, 2, 5] or active_category in [0, 1])
    for i in range(category_buttons.size()):
        _set_selected(category_buttons[i], (palette_open and i == active_category) or (not palette_open and active_power >= 0 and active_power in CATEGORY_POWERS[i]) or (i == 5 and settings_panel != null and settings_panel.visible))
    for id in power_buttons:
        _set_selected(power_buttons[id], id == active_power)
    for i in range(brush_buttons.size()):
        _set_selected(brush_buttons[i], i == active_brush)

func update_stats(year: int, population: int, paused: bool, speed: int) -> void:
    caption_line.text = "Year %d · %d people" % [year, population]
    if is_paused != paused:
        is_paused = paused
        pause_button.set_symbol("play" if paused else "pause")
        pause_button.tooltip_text = "Resume simulation" if paused else "Pause simulation"
        _set_selected(pause_button, paused)
    if current_speed != speed:
        current_speed = speed
        _set_caption(speed_button, "%d×" % speed)
        _set_selected(speed_button, speed > 1)

func set_world_details(details: String) -> void:
    if world_details != details:
        world_details = details
        world_info.text = details

func open_palette(show: bool) -> void:
    if palette_open == show:
        return
    palette_open = show
    interaction_started.emit()
    if show:
        hide_inspector()
        if active_category >= 5:
            active_category = 0
            _rebuild_power_buttons()
    _refresh_selection()
    _layout()
    _transition(palette_panel, show)

func _transition(panel: Control, show: bool) -> void:
    if panel_tween != null:
        panel_tween.kill()
    # Keep hit geometry fixed throughout motion; animate opacity only.
    # No stale callback can hide a newly reopened tray.
    if reduced_motion or not show:
        panel.visible = show
        panel.modulate.a = 1.0
        return
    panel.show()
    panel.modulate.a = 0.0
    panel_tween = create_tween()
    panel_tween.tween_property(panel, "modulate:a", 1.0, Tokens.ENTER).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _show_settings(show: bool) -> void:
    interaction_started.emit()
    if show:
        open_palette(false)
        hide_inspector()
        close_inventory()
    settings_panel.visible = show
    modal_dim.visible = show
    restore_panel.hide()
    _refresh_selection()
    _layout()
    _transition(settings_panel, show)

func _confirm_restore() -> void:
    settings_panel.hide()
    restore_panel.show()
    modal_dim.show()
    _layout()

func _cancel_restore() -> void:
    restore_panel.hide()
    settings_panel.show()
    _layout()

func close_modal() -> void:
    interaction_started.emit()
    close_inventory()
    settings_panel.hide()
    restore_panel.hide()
    modal_dim.hide()
    _refresh_selection()

func open_inventory(model: RefCounted, world: RefCounted) -> void:
    if inventory_model == model:
        inventory_model = null
    close_modal()
    open_palette(false)
    hide_inspector()
    inventory_model = model
    world_ref = world
    inventory_panel.bind_model(model, world)
    modal_dim.show()
    inventory_panel.show()
    _layout()
    _transition(inventory_panel, true)

func close_inventory() -> void:
    if inventory_model != null:
        inventory_model.close()
    if inventory_panel != null:
        inventory_panel.hide()
    inventory_model = null
    world_ref = null

func sync_inventory() -> void:
    if inventory_model == null:
        return
    if not inventory_model.visible:
        close_inventory()
        modal_dim.hide()
    else:
        inventory_panel.refresh()

func handle_back() -> bool:
    if restore_panel.visible:
        _cancel_restore()
    elif modal_dim.visible:
        close_modal()
    elif palette_open:
        open_palette(false)
    elif inspector_panel.visible:
        hide_inspector()
    elif hud_hidden:
        set_hud_hidden(false)
    elif active_power >= 0:
        _choose_power(-1)
    else:
        _show_settings(true)
    return true

func set_hud_hidden(hidden: bool) -> void:
    if hud_hidden == hidden:
        return
    interaction_started.emit()
    hud_hidden = hidden
    open_palette(false)
    hide_inspector()
    close_modal()
    if hidden:
        hidden_power = active_power
        power_changed.emit(-1)
    else:
        power_changed.emit(hidden_power)
        set_active_power(hidden_power)
    top_panel.visible = not hidden
    dock_panel.visible = not hidden
    context_panel.visible = not hidden
    root.get_node("RestoreHUD").visible = hidden
    toast.hide()
    _layout()

func show_citizen(person: Dictionary) -> void:
    inspector_content = person.duplicate()
    inspector_title.text = "CITIZEN #%d" % int(person.get("id", 0))
    inspector_body.text = _citizen_text(person)
    _reveal_inspector()

func _citizen_text(person: Dictionary) -> String:
    return "Civilisation %d · Health %d / 100\nPosition %d, %d" % [int(person.get("nation", 0)) + 1, int(person.get("hp", 100)), int(person.get("x", 0)), int(person.get("y", 0))]

func refresh_citizen(person: Dictionary) -> void:
    if inspector_panel.visible and int(person.get("id", -1)) == int(inspector_content.get("id", -2)):
        inspector_content = person.duplicate()
        inspector_body.text = _citizen_text(person)

func show_terrain(cell: Vector2i, kind: String, elevation: int) -> void:
    inspector_content.clear()
    inspector_title.text = kind.to_upper()
    inspector_body.text = "Elevation %d · Tile %d, %d\nChoose a tool to reshape this place." % [elevation, cell.x, cell.y]
    _reveal_inspector()

func _reveal_inspector() -> void:
    open_palette(false)
    inspector_panel.show()
    _layout()
    _transition(inspector_panel, true)

func hide_inspector() -> void:
    if inspector_panel != null:
        inspector_panel.hide()
    inspector_content.clear()

func notify(message: String, error: bool = false) -> void:
    if toast == null or hud_hidden:
        return
    if toast_tween != null:
        toast_tween.kill()
    toast_label.text = message
    toast_label.add_theme_color_override("font_color", Tokens.DANGER if error else Tokens.ACCENT)
    toast.show()
    toast.modulate.a = 1.0
    _layout()
    toast_tween = create_tween()
    toast_tween.tween_interval(2.2)
    if not reduced_motion:
        toast_tween.tween_property(toast, "modulate:a", 0.0, Tokens.ENTER)
    toast_tween.tween_callback(toast.hide)

func set_reduced_motion(value: bool) -> void:
    reduced_motion = value
    if panel_tween != null:
        panel_tween.kill()
    for panel in [palette_panel, inspector_panel, settings_panel, inventory_panel]:
        if panel != null:
            panel.modulate.a = 1.0
    _refresh_preferences()

func _refresh_preferences() -> void:
    for b in buttons:
        if is_instance_valid(b):
            b.reduced_motion = reduced_motion
            b.haptics = haptics
            b._reset_motion()
    if motion_button != null:
        _set_caption(motion_button, "Motion: Reduced" if reduced_motion else "Motion: Full")
        _set_caption(haptic_button, "Touch feedback: On" if haptics else "Touch feedback: Off")

func _load_preferences() -> void:
    var config := ConfigFile.new()
    if preferences_path != "" and config.load(preferences_path) == OK:
        reduced_motion = bool(config.get_value("interface", "reduced_motion", false))
        haptics = bool(config.get_value("interface", "haptics", true))

func _save_preferences() -> void:
    if preferences_path == "":
        return
    var config := ConfigFile.new()
    config.set_value("interface", "reduced_motion", reduced_motion)
    config.set_value("interface", "haptics", haptics)
    if config.save(preferences_path) != OK:
        notify("Could not save interface preferences", true)

func platform_safe_rect() -> Rect2:
    var viewport_size := get_viewport().get_visible_rect().size
    var full := Rect2(Vector2.ZERO, viewport_size)
    if safe_override.has_area():
        return full.intersection(safe_override)
    if OS.get_name() != "Android":
        return full
    # Safe area is in physical screen coordinates; GUI is in logical canvas units.
    var physical := Rect2(DisplayServer.get_display_safe_area())
    if not physical.has_area():
        return full
    var inverse := get_viewport().get_screen_transform().affine_inverse()
    return full.intersection(Rect2(inverse * physical.position, inverse.basis_xform(physical.size)))

func _layout() -> void:
    if root == null:
        return
    var viewport_size := get_viewport().get_visible_rect().size
    root.size = viewport_size
    safe_rect = platform_safe_rect().grow(-8.0 if viewport_size.x <= 360 else -Tokens.MARGIN)
    category_bar.add_theme_constant_override("separation", 0 if safe_rect.size.x < 320 else 2)
    var width := minf(safe_rect.size.x, 600.0)
    var x := safe_rect.position.x + (safe_rect.size.x - width) * 0.5
    top_panel.position = Vector2(x, safe_rect.position.y)
    top_panel.size = Vector2(width, 60)
    dock_panel.size = Vector2(width, 68)
    dock_panel.position = Vector2(x, safe_rect.end.y - 68)
    context_panel.size = Vector2(width, 56)
    context_panel.position = Vector2(x, dock_panel.position.y - 64)
    var available := maxf(48, context_panel.position.y - top_panel.get_global_rect().end.y - 16)
    var tool_height := 48 + 80 + 16 + 36 + 24
    if brush_row.visible:
        tool_height += 56
    if active_category == 4:
        tool_height = 280
    var tray_width := minf(width, 420.0)
    palette_panel.size = Vector2(tray_width, minf(tool_height, available))
    palette_panel.position = Vector2(x + width - tray_width, context_panel.position.y - palette_panel.size.y - 8)
    inspector_panel.size = Vector2(minf(width, 340), 128)
    inspector_panel.position = Vector2(x + width - inspector_panel.size.x, top_panel.position.y + 68)
    modal_dim.position = Vector2.ZERO
    modal_dim.size = viewport_size
    settings_panel.size = Vector2(minf(width, 360), minf(safe_rect.size.y, 490))
    settings_panel.position = safe_rect.get_center() - settings_panel.size * 0.5
    restore_panel.size = Vector2(minf(width, 360), minf(safe_rect.size.y, 256))
    restore_panel.position = safe_rect.get_center() - restore_panel.size * 0.5
    var inventory_height := 440.0
    if inventory_model != null and world_ref != null and not inventory_model.rows_for(world_ref).is_empty():
        inventory_height = 600.0
    inventory_panel.size = Vector2(minf(width, 480), minf(safe_rect.size.y, inventory_height))
    inventory_panel.position = safe_rect.get_center() - inventory_panel.size * 0.5
    var reveal: Control = root.get_node("RestoreHUD")
    reveal.position = safe_rect.end - Vector2(48, 48)
    reveal.size = Vector2(48, 48)
    toast.size = Vector2(minf(width, 360), 42)
    toast.position = Vector2(safe_rect.get_center().x - toast.size.x * 0.5, top_panel.position.y + 68)

func blocks_world_input(point: Vector2) -> bool:
    if modal_dim.visible:
        return true
    # The same visible Control rectangles serve rendering, GUI and world routing.
    for control in [top_panel, dock_panel, context_panel, palette_panel, inspector_panel, root.get_node("RestoreHUD")]:
        if control.is_visible_in_tree() and control.get_global_rect().has_point(point):
            return true
    return not Rect2(Vector2.ZERO, root.size).has_point(point)
