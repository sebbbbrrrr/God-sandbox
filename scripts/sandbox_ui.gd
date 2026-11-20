extends CanvasLayer
class_name GodSandboxHUD

## Responsive, canvas-space Android HUD. World input is owned by game.gd;
## interactive Controls consume their own taps and expose their visible bounds.
signal power_changed(power: int)
signal brush_changed(index: int)
signal pause_pressed
signal speed_pressed
signal save_pressed

const INK := Color("#172825")
const SURFACE := Color("#1b2d2b")
const SURFACE_RAISED := Color("#304640")
const BORDER := Color("#647e68")
const GOLD := Color("#e4c58b")
const IVORY := Color("#f5ecda")
const MUTED := Color("#b6c7b6")
const POWER_NAMES := ["Raise", "Fire", "Forest", "Bless", "Spawn", "Ocean"]
const POWER_ICONS := ["raise", "fire", "forest", "bless", "spawn", "ocean"]
const CATEGORIES := ["All", "World", "Life", "Nature", "Chaos"]
const CATEGORY_POWERS := [[0, 1, 2, 3, 4, 5], [0, 5], [3, 4], [0, 2], [1, 5]]
const BRUSH_NAMES := ["Small", "Medium", "Large"]
const ICON_PATHS := {
    "hand": "<path d='M8 13V5a1.5 1.5 0 0 1 3 0v6-7a1.5 1.5 0 0 1 3 0v7-5a1.5 1.5 0 0 1 3 0v6-3a1.5 1.5 0 0 1 3 0v6c0 4-2.5 7-6.5 7H11c-2.3 0-4-1-5.1-2.8L3 15a1.5 1.5 0 0 1 2.5-1.7l2.5 2.7'/>",
    "raise": "<path d='m2 19 6-9 4 5 4-10 6 14H2Z'/><path d='M16 5V2m-3 3h6'/>",
    "fire": "<path d='M12 22c-4.4 0-7-3.2-7-7.2 0-3 2.5-6 3.4-8.8.5 3.1 2.5 3.2 3.4 3.8 1.2-3 1.6-5.4 1-8 4.8 3.8 7.2 7.7 7.2 11.5 0 4.2-2.7 7.7-7 7.7Z'/><path d='M12 22c-2.1 0-3.5-1.5-3.5-3.5 0-1.8 1-3 2-4.4.3 2 2.7 2.6 3 4.3.3-1 .5-2 .4-3.1 2 1.9 2.6 3.3 2.6 4.3 0 2.1-1.4 3.4-3.5 3.4Z'/>",
    "forest": "<path d='m6 3-4 8h3l-4 7h11l-4-7h3L7 3ZM7 18v4'/><path d='m17 2-4 9h3l-3 7h10l-3-7h2l-4-9Zm1 16v4'/>",
    "bless": "<path d='m12 2 2.6 6.5L21 11l-6.4 2.5L12 20l-2.5-6.5L3 11l6.5-2.5L12 2Z'/><path d='M20 18v5m-2.5-2.5h5M4 2v4M2 4h4'/>",
    "spawn": "<circle cx='12' cy='6' r='3'/><path d='M5 22v-5c0-4 2.8-6 7-6s7 2 7 6v5M9 16v6m6-6v6'/>",
    "ocean": "<path d='M2 7c3-4 5 4 10 0s7-4 10 0M2 13c3-4 5 4 10 0s7-4 10 0M2 19c3-4 5 4 10 0s7-4 10 0'/>",
    "tools": "<rect x='3' y='4' width='7' height='7' rx='1'/><rect x='14' y='4' width='7' height='7' rx='1'/><rect x='3' y='15' width='7' height='6' rx='1'/><rect x='14' y='15' width='7' height='6' rx='1'/>",
    "pause": "<rect x='5' y='4' width='5' height='16' rx='1'/><rect x='14' y='4' width='5' height='16' rx='1'/>",
    "play": "<path d='m7 4 13 8-13 8V4Z'/>",
    "settings": "<circle cx='12' cy='12' r='3'/><path d='M10 2h4l.6 2.5 2 1.2 2.5-.7 2 3.5-1.9 1.8v3.4l1.9 1.8-2 3.5-2.5-.7-2 1.2L14 22h-4l-.6-2.5-2-1.2-2.5.7-2-3.5 1.9-1.8v-3.4L2.9 8.5l2-3.5 2.5.7 2-1.2L10 2Z'/>",
    "close": "<path d='M5 5 19 19M19 5 5 19'/>",
    "chevron": "<path d='m5 9 7 7 7-7'/>"
}

var active_power := -1
var active_category := 0
var active_brush := 1
var is_paused := false
var current_speed := 1
var palette_open := false
var reduced_motion := false
var panel_tween: Tween
var inspector_tween: Tween
var icon_cache := {}

var root: Control
var top_panel: PanelContainer
var dock_panel: PanelContainer
var palette_panel: PanelContainer
var inspector_panel: PanelContainer
var modal_dim: ColorRect
var settings_panel: PanelContainer
var status_line: Label
var caption_line: Label
var pause_button: Button
var speed_button: Button
var palette_button: Button
var hand_button: Button
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
var inspector_content: Dictionary = {}

func _ready() -> void:
    layer = 10
    _make_interface()
    get_viewport().size_changed.connect(_layout)
    _layout()

func _panel_style(raised: bool = false) -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    var tint := SURFACE_RAISED if raised else SURFACE
    tint.a = 0.96 if raised else 0.94
    s.bg_color = tint
    s.border_color = Color("#607c6c", 0.68)
    s.set_border_width_all(1)
    s.set_corner_radius_all(15)
    s.set_content_margin_all(10)
    s.shadow_color = Color(0.0, 0.0, 0.0, 0.28)
    s.shadow_size = 5
    s.shadow_offset = Vector2(0, 3)
    return s

func _button_style(selected: bool, hovered: bool = false) -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = GOLD if selected else (Color("#476154") if hovered else SURFACE_RAISED)
    s.set_corner_radius_all(10)
    s.set_content_margin_all(5)
    if selected:
        s.border_color = Color("#ffe4ac")
        s.set_border_width_all(1)
    return s

func _icon(name: String, dark: bool = false) -> Texture2D:
    var key := name + (":dark" if dark else ":light")
    if icon_cache.has(key):
        return icon_cache[key]
    var path: String = ICON_PATHS.get(name, ICON_PATHS["tools"])
    var stroke := "#233730" if dark else "#f5ecda"
    var svg := "<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24' fill='none' stroke='" + stroke + "' stroke-width='1.8' stroke-linecap='round' stroke-linejoin='round'>" + path + "</svg>"
    var img := Image.new()
    if img.load_svg_from_buffer(svg.to_utf8_buffer(), 1.5) != OK:
        return null
    var tex := ImageTexture.create_from_image(img)
    icon_cache[key] = tex
    return tex

func _label(value: String, font_size: int = 13, tint: Color = IVORY) -> Label:
    var l := Label.new()
    l.text = value
    l.add_theme_font_size_override("font_size", font_size)
    l.add_theme_color_override("font_color", tint)
    l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    l.clip_text = true
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return l

func _button(value: String, icon_name: String = "", width: float = 50.0) -> Button:
    var b := Button.new()
    b.text = value
    b.custom_minimum_size = Vector2(width, 48)
    b.clip_text = true
    b.alignment = HORIZONTAL_ALIGNMENT_CENTER
    b.add_theme_font_size_override("font_size", 12)
    b.add_theme_color_override("font_color", IVORY)
    b.add_theme_color_override("font_hover_color", IVORY)
    b.add_theme_color_override("font_pressed_color", IVORY)
    b.add_theme_color_override("font_focus_color", IVORY)
    b.add_theme_stylebox_override("normal", _button_style(false))
    b.add_theme_stylebox_override("hover", _button_style(false, true))
    b.add_theme_stylebox_override("pressed", _button_style(true))
    b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
    b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
    if icon_name != "":
        b.set_meta("hud_icon", icon_name)
        b.icon = _icon(icon_name)
    return b

func _set_selected(button: Button, selected: bool) -> void:
    button.add_theme_stylebox_override("normal", _button_style(selected))
    button.add_theme_stylebox_override("hover", _button_style(selected, not selected))
    button.add_theme_color_override("font_color", INK if selected else IVORY)
    button.add_theme_color_override("font_hover_color", INK if selected else IVORY)
    if button.has_meta("hud_icon"):
        button.icon = _icon(str(button.get_meta("hud_icon")), selected)

func _animate_press(button: Button) -> void:
    if reduced_motion:
        return
    button.pivot_offset = button.size * 0.5
    var t := create_tween()
    t.tween_property(button, "scale", Vector2(0.94, 0.94), 0.07)
    t.tween_property(button, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _make_interface() -> void:
    root = Control.new()
    root.name = "HUDRoot"
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(root)

    top_panel = PanelContainer.new()
    top_panel.name = "StatusBar"
    top_panel.add_theme_stylebox_override("panel", _panel_style())
    top_panel.mouse_filter = Control.MOUSE_FILTER_STOP
    root.add_child(top_panel)
    var top_row := HBoxContainer.new()
    top_row.add_theme_constant_override("separation", 6)
    top_panel.add_child(top_row)
    var status := VBoxContainer.new()
    status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    status.add_theme_constant_override("separation", 0)
    top_row.add_child(status)
    status_line = _label("GOD SANDBOX", 14, GOLD)
    caption_line = _label("Year 1  ·  0 souls", 10, MUTED)
    status.add_child(status_line)
    status.add_child(caption_line)
    pause_button = _button("", "pause", 42)
    speed_button = _button("1×", "", 44)
    var settings_button := _button("", "settings", 42)
    for b in [pause_button, speed_button, settings_button]:
        b.custom_minimum_size.y = 42
        top_row.add_child(b)
    pause_button.pressed.connect(func() -> void:
        _animate_press(pause_button)
        pause_pressed.emit()
    )
    speed_button.pressed.connect(func() -> void:
        _animate_press(speed_button)
        speed_pressed.emit()
    )
    settings_button.pressed.connect(func() -> void:
        _animate_press(settings_button)
        _show_settings(true)
    )

    dock_panel = PanelContainer.new()
    dock_panel.name = "ToolDock"
    dock_panel.add_theme_stylebox_override("panel", _panel_style())
    dock_panel.mouse_filter = Control.MOUSE_FILTER_STOP
    root.add_child(dock_panel)
    var dock_row := HBoxContainer.new()
    dock_row.add_theme_constant_override("separation", 6)
    dock_panel.add_child(dock_row)
    hand_button = _button("Hand", "hand", 74)
    palette_button = _button("Powers", "tools", 88)
    active_button = _button("Explore", "", 60)
    active_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    dock_brush_button = _button("M", "", 43)
    for b in [hand_button, palette_button, active_button, dock_brush_button]:
        b.custom_minimum_size.y = 50
        dock_row.add_child(b)
    hand_button.pressed.connect(func() -> void:
        _animate_press(hand_button)
        _choose_power(-1)
        open_palette(false)
    )
    palette_button.pressed.connect(func() -> void:
        _animate_press(palette_button)
        open_palette(not palette_open)
    )
    active_button.pressed.connect(func() -> void:
        _animate_press(active_button)
        if active_power != -1:
            _choose_power(-1)
        else:
            open_palette(true)
    )
    dock_brush_button.pressed.connect(func() -> void:
        _animate_press(dock_brush_button)
        _choose_brush((active_brush + 1) % BRUSH_NAMES.size())
    )

    palette_panel = PanelContainer.new()
    palette_panel.name = "PowerPalette"
    palette_panel.add_theme_stylebox_override("panel", _panel_style(true))
    palette_panel.mouse_filter = Control.MOUSE_FILTER_STOP
    root.add_child(palette_panel)
    var palette_vbox := VBoxContainer.new()
    palette_vbox.add_theme_constant_override("separation", 7)
    palette_panel.add_child(palette_vbox)
    var heading := HBoxContainer.new()
    heading.add_theme_constant_override("separation", 8)
    palette_vbox.add_child(heading)
    var palette_title := _label("GOD POWERS", 14, GOLD)
    palette_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    heading.add_child(palette_title)
    var close_palette := _button("", "close", 34)
    close_palette.custom_minimum_size.y = 30
    heading.add_child(close_palette)
    close_palette.pressed.connect(func() -> void:
        _animate_press(close_palette)
        open_palette(false)
    )

    var category_scroll := ScrollContainer.new()
    category_scroll.name = "CategoryScroll"
    category_scroll.custom_minimum_size.y = 38
    category_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    category_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    category_scroll.follow_focus = true
    palette_vbox.add_child(category_scroll)
    category_bar = HBoxContainer.new()
    category_bar.add_theme_constant_override("separation", 5)
    category_scroll.add_child(category_bar)
    for i in range(CATEGORIES.size()):
        var index := i
        var tab := _button(CATEGORIES[i], "", 74)
        tab.custom_minimum_size.y = 36
        tab.add_theme_font_size_override("font_size", 11)
        category_bar.add_child(tab)
        category_buttons.append(tab)
        tab.pressed.connect(func() -> void:
            _animate_press(tab)
            _choose_category(index)
        )

    power_grid = GridContainer.new()
    power_grid.columns = 3
    power_grid.add_theme_constant_override("h_separation", 6)
    power_grid.add_theme_constant_override("v_separation", 6)
    palette_vbox.add_child(power_grid)

    brush_row = HBoxContainer.new()
    brush_row.add_theme_constant_override("separation", 6)
    palette_vbox.add_child(brush_row)
    var brush_title := _label("Brush", 12, MUTED)
    brush_title.custom_minimum_size.x = 52
    brush_row.add_child(brush_title)
    for i in range(BRUSH_NAMES.size()):
        var index := i
        var b := _button(BRUSH_NAMES[i], "", 65)
        b.custom_minimum_size.y = 34
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        brush_row.add_child(b)
        brush_buttons.append(b)
        b.pressed.connect(func() -> void:
            _animate_press(b)
            _choose_brush(index)
        )

    var hint := _label("Tap an equipped power again to return to Hand.", 11, MUTED)
    palette_vbox.add_child(hint)
    palette_panel.visible = false

    inspector_panel = PanelContainer.new()
    inspector_panel.name = "Inspector"
    inspector_panel.add_theme_stylebox_override("panel", _panel_style(true))
    inspector_panel.mouse_filter = Control.MOUSE_FILTER_STOP
    root.add_child(inspector_panel)
    var inspect_col := VBoxContainer.new()
    inspect_col.add_theme_constant_override("separation", 8)
    inspector_panel.add_child(inspect_col)
    var inspect_header := HBoxContainer.new()
    inspect_col.add_child(inspect_header)
    inspector_title = _label("INSPECT", 15, GOLD)
    inspector_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    inspect_header.add_child(inspector_title)
    var close_inspector := _button("", "close", 34)
    close_inspector.custom_minimum_size.y = 32
    inspect_header.add_child(close_inspector)
    close_inspector.pressed.connect(func() -> void:
        _animate_press(close_inspector)
        hide_inspector()
    )
    inspector_body = _label("", 13, IVORY)
    inspector_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    inspector_body.clip_text = false
    inspector_body.custom_minimum_size.y = 116
    inspect_col.add_child(inspector_body)
    inspector_panel.visible = false

    modal_dim = ColorRect.new()
    modal_dim.name = "ModalDim"
    modal_dim.color = Color(0, 0, 0, 0.44)
    modal_dim.mouse_filter = Control.MOUSE_FILTER_STOP
    modal_dim.visible = false
    root.add_child(modal_dim)
    settings_panel = PanelContainer.new()
    settings_panel.name = "Settings"
    settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP
    settings_panel.add_theme_stylebox_override("panel", _panel_style(true))
    root.add_child(settings_panel)
    var settings_col := VBoxContainer.new()
    settings_col.add_theme_constant_override("separation", 12)
    settings_panel.add_child(settings_col)
    var settings_head := HBoxContainer.new()
    settings_col.add_child(settings_head)
    var settings_title := _label("SETTINGS", 17, GOLD)
    settings_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    settings_head.add_child(settings_title)
    var settings_close := _button("", "close", 38)
    settings_close.custom_minimum_size.y = 38
    settings_head.add_child(settings_close)
    settings_close.pressed.connect(func() -> void:
        _animate_press(settings_close)
        _show_settings(false)
    )
    settings_col.add_child(_label("Your world is autosaved while you play.", 12, MUTED))
    var save_button := _button("Save world now", "", 120)
    save_button.custom_minimum_size.y = 50
    settings_col.add_child(save_button)
    save_button.pressed.connect(func() -> void:
        _animate_press(save_button)
        save_pressed.emit()
        save_button.text = "World saved"
    )
    motion_button = _button("Animations: On", "", 120)
    motion_button.custom_minimum_size.y = 50
    settings_col.add_child(motion_button)
    motion_button.pressed.connect(func() -> void:
        reduced_motion = not reduced_motion
        motion_button.text = "Animations: Off" if reduced_motion else "Animations: On"
    )
    settings_col.add_child(_label("Hand: drag to move. Painting: drag to draw.", 12, MUTED))
    settings_col.add_child(_label("Two fingers: move and zoom while editing.", 12, MUTED))
    settings_panel.visible = false
    _rebuild_power_buttons()
    _refresh_selection()

func _choose_category(index: int) -> void:
    active_category = clampi(index, 0, CATEGORIES.size() - 1)
    _rebuild_power_buttons()
    _refresh_selection()
    _layout()
    if not reduced_motion:
        power_grid.modulate.a = 0.42
        var fade := create_tween()
        fade.tween_property(power_grid, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _rebuild_power_buttons() -> void:
    for child in power_grid.get_children():
        power_grid.remove_child(child)
        child.queue_free()
    power_buttons.clear()
    for power in CATEGORY_POWERS[active_category]:
        var index: int = power
        var b := _button(POWER_NAMES[index], POWER_ICONS[index], 90)
        b.custom_minimum_size.y = 49
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        power_grid.add_child(b)
        power_buttons[index] = b
        b.pressed.connect(func() -> void:
            _animate_press(b)
            _choose_power(index)
        )

func _choose_power(power: int) -> void:
    var next_power := -1 if power == active_power else power
    if power == -1:
        next_power = -1
    set_active_power(next_power)
    power_changed.emit(next_power)

func set_active_power(power: int) -> void:
    active_power = clampi(power, -1, POWER_NAMES.size() - 1)
    _refresh_selection()
    if active_power != -1:
        hide_inspector()
    _layout()

func _choose_brush(index: int) -> void:
    set_brush(index)
    brush_changed.emit(active_brush)

func set_brush(index: int) -> void:
    active_brush = clampi(index, 0, BRUSH_NAMES.size() - 1)
    _refresh_selection()

func _refresh_selection() -> void:
    _set_selected(hand_button, active_power == -1)
    _set_selected(palette_button, palette_open)
    _set_selected(active_button, active_power != -1)
    active_button.text = "Explore" if active_power == -1 else POWER_NAMES[active_power]
    if active_power >= 0:
        active_button.set_meta("hud_icon", POWER_ICONS[active_power])
        active_button.icon = _icon(POWER_ICONS[active_power], true)
    else:
        if active_button.has_meta("hud_icon"):
            active_button.remove_meta("hud_icon")
        active_button.icon = null
    dock_brush_button.visible = active_power == 0 or active_power == 2 or active_power == 5
    dock_brush_button.text = ["S", "M", "L"][active_brush]
    brush_row.visible = dock_brush_button.visible
    for i in range(category_buttons.size()):
        _set_selected(category_buttons[i], i == active_category)
    for id in power_buttons:
        _set_selected(power_buttons[id], id == active_power)
    for i in range(brush_buttons.size()):
        _set_selected(brush_buttons[i], i == active_brush)

func update_stats(year: int, population: int, paused: bool, speed: int) -> void:
    var new_caption := "Year %d  ·  %d souls" % [year, population]
    if caption_line.text != new_caption:
        caption_line.text = new_caption
    if is_paused != paused:
        is_paused = paused
        pause_button.set_meta("hud_icon", "play" if paused else "pause")
        pause_button.icon = _icon("play" if paused else "pause")
    if current_speed != speed:
        current_speed = speed
        speed_button.text = "%d×" % speed

func open_palette(show: bool) -> void:
    if palette_open == show:
        return
    palette_open = show
    if show:
        hide_inspector()
    _refresh_selection()
    _layout()
    if panel_tween != null and panel_tween.is_running():
        panel_tween.kill()
    var target_y := _palette_y()
    if reduced_motion:
        palette_panel.visible = show
        palette_panel.position.y = target_y if show else dock_panel.position.y + 8
        palette_panel.modulate.a = 1.0 if show else 0.0
        return
    if show:
        palette_panel.visible = true
        palette_panel.position.y = dock_panel.position.y + 6
        palette_panel.modulate.a = 0.0
    panel_tween = create_tween().set_parallel(true)
    panel_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    panel_tween.tween_property(palette_panel, "position:y", target_y if show else dock_panel.position.y + 8, 0.22)
    panel_tween.tween_property(palette_panel, "modulate:a", 1.0 if show else 0.0, 0.18)
    if not show:
        panel_tween.chain().tween_callback(func() -> void:
            if not palette_open:
                palette_panel.visible = false
        )

func _palette_y() -> float:
    var viewport_size := get_viewport().get_visible_rect().size
    if viewport_size.x > viewport_size.y * 1.2:
        return maxf(78.0, (viewport_size.y - palette_panel.size.y) * 0.45)
    return dock_panel.position.y - palette_panel.size.y - 9

func _show_settings(show: bool) -> void:
    if show:
        open_palette(false)
        hide_inspector()
    modal_dim.visible = show
    settings_panel.visible = show
    _layout()
    if show and not reduced_motion:
        settings_panel.pivot_offset = settings_panel.size * 0.5
        settings_panel.scale = Vector2(0.94, 0.94)
        settings_panel.modulate.a = 0.0
        var t := create_tween().set_parallel(true)
        t.tween_property(settings_panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
        t.tween_property(settings_panel, "modulate:a", 1.0, 0.16)
    else:
        settings_panel.scale = Vector2.ONE
        settings_panel.modulate.a = 1.0

func show_citizen(person: Dictionary) -> void:
    inspector_content = person.duplicate()
    inspector_title.text = "CITIZEN #%d" % int(person.get("id", 0))
    inspector_body.text = "Civilisation: %d\nHealth: %d / 100\nAge: %d\nPosition: %d, %d" % [
        int(person.get("nation", 0)) + 1, int(person.get("hp", 100)),
        int(person.get("age", 0)), int(person.get("x", 0)), int(person.get("y", 0))
    ]
    _reveal_inspector()

func refresh_citizen(person: Dictionary) -> void:
    if not inspector_panel.visible or inspector_content.is_empty():
        return
    if int(person.get("id", -1)) != int(inspector_content.get("id", -2)):
        return
    inspector_content = person.duplicate()
    var new_details := "Civilisation: %d\\nHealth: %d / 100\\nAge: %d\\nPosition: %d, %d" % [
        int(person.get("nation", 0)) + 1, int(person.get("hp", 100)),
        int(person.get("age", 0)), int(person.get("x", 0)), int(person.get("y", 0))
    ]
    if inspector_body.text != new_details:
        inspector_body.text = new_details

func show_terrain(cell: Vector2i, kind: String, elevation: int) -> void:
    inspector_content.clear()
    inspector_title.text = kind.to_upper()
    inspector_body.text = "Terrain: %s\nElevation: %d\nPosition: %d, %d\n\nSelect a power to modify this tile." % [kind, elevation, cell.x, cell.y]
    _reveal_inspector()

func _reveal_inspector() -> void:
    open_palette(false)
    if inspector_tween != null and inspector_tween.is_running():
        inspector_tween.kill()
    inspector_panel.visible = true
    _layout()
    if reduced_motion:
        inspector_panel.modulate.a = 1.0
        return
    inspector_panel.modulate.a = 0.0
    var y := inspector_panel.position.y
    inspector_panel.position.y = y + 12
    inspector_tween = create_tween().set_parallel(true)
    inspector_tween.tween_property(inspector_panel, "position:y", y, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    inspector_tween.tween_property(inspector_panel, "modulate:a", 1.0, 0.18)

func hide_inspector() -> void:
    if inspector_tween != null and inspector_tween.is_running():
        inspector_tween.kill()
    inspector_panel.visible = false
    inspector_content.clear()

func _layout() -> void:
    if root == null:
        return
    var size_view := get_viewport().get_visible_rect().size
    root.size = size_view
    var width := minf(size_view.x - 20.0, 600.0)
    var x := (size_view.x - width) * 0.5
    top_panel.position = Vector2(x, 10)
    top_panel.size = Vector2(width, 62)
    dock_panel.size = Vector2(width, 72)
    dock_panel.position = Vector2(x, size_view.y - 82)
    var is_landscape := size_view.x > size_view.y * 1.2
    var palette_width := minf(370.0, size_view.x * 0.48) if is_landscape else width
    var palette_x := size_view.x - palette_width - 12.0 if is_landscape else x
    palette_panel.size = Vector2(palette_width, palette_panel.get_combined_minimum_size().y)
    if panel_tween == null or not panel_tween.is_running():
        palette_panel.position = Vector2(palette_x, _palette_y() if palette_open else dock_panel.position.y + 8)
    else:
        palette_panel.position.x = palette_x
    inspector_panel.size = Vector2(minf(size_view.x - 22, 290), inspector_panel.get_combined_minimum_size().y)
    inspector_panel.position = Vector2(size_view.x - inspector_panel.size.x - 11, top_panel.position.y + 73)
    modal_dim.position = Vector2.ZERO
    modal_dim.size = size_view
    settings_panel.size = Vector2(minf(size_view.x - 30, 360), settings_panel.get_combined_minimum_size().y)
    settings_panel.position = (size_view - settings_panel.size) * 0.5

func blocks_world_input(point: Vector2) -> bool:
    if modal_dim.visible:
        return true
    if top_panel.get_global_rect().has_point(point) or dock_panel.get_global_rect().has_point(point):
        return true
    if palette_panel.visible and palette_panel.get_global_rect().has_point(point):
        return true
    if inspector_panel.visible and inspector_panel.get_global_rect().has_point(point):
        return true
    return false
