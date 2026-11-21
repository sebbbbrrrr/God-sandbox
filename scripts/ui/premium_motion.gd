extends RefCounted
class_name PremiumMotion
## Low-overhead, reusable motion and tactile styling for God Sandbox menus.
## Every tween is bound to its control and dies when that control is freed.

const INK := Color("#0d1817")
const PANEL := Color("#142622")
const PANEL_RAISED := Color("#20372f")
const PANEL_HIGH := Color("#2d483b")
const GOLD := Color("#e9ca91")
const GOLD_PALE := Color("#f7e5bf")
const IVORY := Color("#f7f0e1")
const MUTED := Color("#9db4a6")
const HAIRLINE := Color("#75927d", 0.32)
const GOOD := Color("#86c49a")
const WARNING := Color("#e3b777")
const DANGER := Color("#e99186")

static func surface(raised: bool = false, radius: int = 18, accent: bool = false) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = PANEL_RAISED if raised else PANEL
    style.set_corner_radius_all(radius)
    style.set_content_margin_all(12 if raised else 10)
    style.border_color = Color(GOLD, 0.37) if accent else HAIRLINE
    style.set_border_width_all(1)
    style.anti_aliasing = true
    style.anti_aliasing_size = 0.75
    style.shadow_color = Color(0, 0, 0, 0.20)
    style.shadow_size = 5 if raised else 3
    style.shadow_offset = Vector2(0, 2)
    return style

static func tile(radius: int = 11, accent: Color = Color.TRANSPARENT) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = Color("#22382f")
    style.set_corner_radius_all(radius)
    style.set_content_margin_all(9)
    style.border_color = HAIRLINE if accent.a == 0.0 else Color(accent, 0.47)
    style.set_border_width_all(1)
    style.anti_aliasing = true
    return style

static func action(selected: bool = false, hovered: bool = false) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = Color("#e7c894") if selected else (
        Color("#355344") if hovered else Color("#243d34"))
    style.set_corner_radius_all(11)
    style.set_content_margin_all(7)
    style.border_color = Color("#f4d9a4", 0.83) if selected else HAIRLINE
    style.set_border_width_all(1)
    style.anti_aliasing = true
    style.anti_aliasing_size = 0.65
    return style

static func attach(button: BaseButton, enable_motion: Callable = Callable()) -> void:
    # No per-frame _process cost: only the actually touched button animates.
    button.button_down.connect(func() -> void:
        if enable_motion.is_valid() and not bool(enable_motion.call()):
            return
        if not is_instance_valid(button):
            return
        button.pivot_offset = button.size * 0.5
        if button.has_meta("_motion_tween"):
            var old: Tween = button.get_meta("_motion_tween")
            if old != null and old.is_running():
                old.kill()
        var tween := button.create_tween()
        tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
        tween.tween_property(button, "scale", Vector2(0.955, 0.955), 0.075)
        button.set_meta("_motion_tween", tween)
    )
    button.button_up.connect(func() -> void:
        if not is_instance_valid(button):
            return
        if button.has_meta("_motion_tween"):
            var old: Tween = button.get_meta("_motion_tween")
            if old != null and old.is_running():
                old.kill()
        if enable_motion.is_valid() and not bool(enable_motion.call()):
            button.scale = Vector2.ONE
            return
        var tween := button.create_tween()
        tween.tween_property(button, "scale", Vector2(1.015, 1.015), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
        tween.tween_property(button, "scale", Vector2.ONE, 0.13).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
        button.set_meta("_motion_tween", tween)
    )
    button.mouse_exited.connect(func() -> void:
        if not button.button_pressed:
            button.scale = Vector2.ONE
    )
