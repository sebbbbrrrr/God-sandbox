extends Button
## Stable native hit rectangle; only the inner content compresses under a finger.
## Native release activation lets ScrollContainer cancel a tap during a swipe.
const Tokens = preload("res://scripts/ui/ui_tokens.gd")
const Icons = preload("res://scripts/ui/ui_icons.gd")
var selected := false
var reduced_motion := false
var haptics := false
var caption := ""
var symbol := ""
var stacked := false
var content: Control
var caption_label: Label
var image: TextureRect
var item_texture: Texture2D
var press_tween: Tween

func setup(value: String, icon_name: String = "", vertical: bool = false) -> Button:
    caption = value
    symbol = icon_name
    stacked = vertical
    custom_minimum_size = Vector2(Tokens.TOUCH, Tokens.TOUCH)
    mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    tooltip_text = value
    focus_mode = Control.FOCUS_ALL
    action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
    var focus := Tokens.button()
    focus.border_color = Tokens.TEAL
    focus.set_border_width_all(2)
    add_theme_stylebox_override("focus", focus)
    content = Control.new()
    content.mouse_filter = Control.MOUSE_FILTER_IGNORE
    content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(content)
    var box: BoxContainer = VBoxContainer.new() if vertical else HBoxContainer.new()
    box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    box.offset_left = 6
    box.offset_right = -6
    box.offset_top = 5
    box.offset_bottom = -5
    box.alignment = BoxContainer.ALIGNMENT_CENTER
    box.add_theme_constant_override("separation", 3 if vertical else 7)
    content.add_child(box)
    image = TextureRect.new()
    image.mouse_filter = Control.MOUSE_FILTER_IGNORE
    image.custom_minimum_size = Vector2(24, 24)
    image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    image.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    image.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    box.add_child(image)
    caption_label = Tokens.label(value, 11 if vertical else 13)
    caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    caption_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_child(caption_label)
    set_caption(value)
    set_symbol(icon_name)
    set_selected(false)
    button_down.connect(_compress)
    button_up.connect(_release)
    mouse_exited.connect(_release)
    visibility_changed.connect(_reset_motion)
    return self

func set_caption(value: String) -> void:
    caption = value
    tooltip_text = value if value != "" else tooltip_text
    caption_label.text = value
    caption_label.visible = value != ""

func set_symbol(value: String) -> void:
    symbol = value
    image.visible = value != ""
    if image.visible:
        image.texture = Icons.texture(value, Tokens.ACCENT if selected else Tokens.TEXT, 32 if stacked else 24)

func set_selected(value: bool) -> void:
    selected = value
    add_theme_stylebox_override("normal", Tokens.button(value))
    add_theme_stylebox_override("hover", Tokens.button(value, false, true))
    add_theme_stylebox_override("pressed", Tokens.button(value, true))
    var off := Tokens.button()
    off.bg_color.a = 0.5
    add_theme_stylebox_override("disabled", off)
    caption_label.add_theme_color_override("font_color", Tokens.ACCENT if value else Tokens.TEXT)
    set_symbol(symbol)
    if item_texture != null:
        image.visible = true
        image.texture = item_texture
        image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    queue_redraw()

func _compress() -> void:
    _motion(Vector2(0.94, 0.94), Tokens.FAST * 0.6)
    if haptics and OS.has_feature("android"):
        Input.vibrate_handheld(8, 0.35)

func _release() -> void:
    _motion(Vector2.ONE, Tokens.FAST)

func _reset_motion() -> void:
    if press_tween != null:
        press_tween.kill()
    if content != null:
        content.scale = Vector2.ONE

func _motion(target: Vector2, duration: float) -> void:
    if press_tween != null:
        press_tween.kill()
    content.pivot_offset = size * 0.5
    if reduced_motion or not is_visible_in_tree():
        content.scale = Vector2.ONE
        return
    press_tween = create_tween()
    press_tween.tween_property(content, "scale", target, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _draw() -> void:
    if selected:
        draw_line(Vector2(12, size.y - 4), Vector2(size.x - 12, size.y - 4), Tokens.ACCENT, 2.0, true)
