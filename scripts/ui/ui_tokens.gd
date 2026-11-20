extends RefCounted
## Logical canvas units. Minimum supported canvas: 320 × 360.
## No blur, screen copies or per-frame material allocations on GL Compatibility.
const SPACE := [4, 8, 12, 16, 24, 32]
const TOUCH := 48.0
const ICON := 24.0
const TILE := 80.0
const DOCK := 68.0
const MARGIN := 12.0
const GAP := 8.0
const RADIUS := 18
const FAST := 0.10
const ENTER := 0.18
const INK := Color("#102027")
const SURFACE := Color("#152a32")
const RAISED := Color("#203a42")
const BORDER := Color("#3b555c")
const TEXT := Color("#f5efdf")
const MUTED := Color("#adc3c4")
const ACCENT := Color("#e7c784")
const TEAL := Color("#91d2bc")
const DANGER := Color("#efa18c")

static func panel(raised: bool = false, padding: int = 12) -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = RAISED if raised else SURFACE
    s.bg_color.a = 0.98
    s.border_color = BORDER
    s.set_border_width_all(1)
    s.set_corner_radius_all(RADIUS)
    s.set_content_margin_all(padding)
    s.shadow_color = Color(0.02, 0.06, 0.08, 0.26)
    s.shadow_size = 4
    s.shadow_offset = Vector2(0, 3)
    return s

static func button(selected: bool = false, pressed: bool = false, hover: bool = false) -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = Color("#4c655e") if pressed else (Color("#324d53") if hover else Color("#20363e"))
    if selected:
        s.bg_color = Color("#524d3b") if pressed else Color("#3a423b")
    s.border_color = ACCENT if selected else (Color("#587177") if hover else Color("#2e4850"))
    s.set_border_width_all(2 if selected else 1)
    s.set_corner_radius_all(12)
    s.set_content_margin_all(8)
    return s

static func label(value: String, font_size: int = 14, color: Color = TEXT) -> Label:
    var l := Label.new()
    l.text = value
    l.add_theme_font_size_override("font_size", font_size)
    l.add_theme_color_override("font_color", color)
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    l.clip_text = true
    return l

static func scroll() -> ScrollContainer:
    var s := ScrollContainer.new()
    s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    s.size_flags_vertical = Control.SIZE_EXPAND_FILL
    s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    s.follow_focus = true
    s.scroll_deadzone = 10
    return s
