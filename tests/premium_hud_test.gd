extends SceneTree
const HUD = preload("res://scripts/sandbox_ui.gd")
var ok := true
var assertions := 0
func _initialize() -> void:
    call_deferred("run")
func check(condition: bool, message: String) -> void:
    assertions += 1
    if not condition:
        ok = false
        push_error("FAILED: " + message)
func settle() -> void:
    for frame in range(3):
        await process_frame
func fits(inner: Rect2, outer: Rect2) -> bool:
    return outer.grow(0.5).encloses(inner)
func run() -> void:
    var hud := HUD.new()
    hud.preferences_path = ""
    root.add_child(hud)
    hud.set_reduced_motion(true)
    for dimensions in [Vector2i(320,568),Vector2i(360,780),Vector2i(400,866),Vector2i(480,850),Vector2i(866,400),Vector2i(640,360),Vector2i(1024,768),Vector2i(1280,800)]:
        root.size = dimensions
        root.content_scale_size = dimensions
        await settle()
        hud._layout()
        await settle()
        var full := Rect2(Vector2.ZERO, Vector2(dimensions))
        check(fits(hud.top_panel.get_global_rect(), full), "top bar fits %s" % dimensions)
        check(fits(hud.dock_panel.get_global_rect(), full), "dock fits %s" % dimensions)
        check(fits(hud.context_panel.get_global_rect(), full), "context fits %s" % dimensions)
        for button in hud.category_buttons:
            check(button.size.x >= 48 and button.size.y >= 48, "category touch target %s at %s" % [button.caption,dimensions])
            check(fits(button.get_global_rect(), hud.dock_panel.get_global_rect()), "category stays inside dock %s at %s" % [button.caption,dimensions])
        for category in range(5):
            hud.open_palette(false)
            hud._choose_category(category)
            await settle()
            hud._layout()
            check(hud.palette_open, "category opens tray")
            check(fits(hud.palette_panel.get_global_rect(),full), "tray fits %s category %d" % [dimensions,category])
            check(hud.palette_panel.position.y >= hud.top_panel.get_global_rect().end.y, "tray clears top bar")
            check(hud.palette_panel.get_global_rect().end.y <= hud.context_panel.position.y, "tray clears tool context")
        hud._show_settings(true)
        await settle()
        check(fits(hud.settings_panel.get_global_rect(), full), "scrollable menu fits %s" % dimensions)
        hud.close_modal()
    root.size = Vector2i(400,866)
    root.content_scale_size = root.size
    await settle()
    hud.safe_override = Rect2(0,32,400,802)
    hud._layout()
    check(hud.top_panel.position.y >= 44, "notch inset applied in canvas coordinates")
    check(hud.dock_panel.get_global_rect().end.y <= 822, "navigation inset respected")
    hud.set_active_power(2)
    hud.open_palette(false)
    hud._choose_category(0)
    check(hud.active_power == 2, "category browsing preserves equipped power")
    hud.open_palette(false)
    hud.set_hud_hidden(true)
    check(not hud.top_panel.visible and not hud.dock_panel.visible, "hide HUD removes primary surfaces")
    check(not hud.blocks_world_input(Vector2(200,200)), "hidden HUD does not leave invisible blockers")
    var restore: Control = hud.root.get_node("RestoreHUD")
    check(hud.blocks_world_input(restore.get_global_rect().get_center()), "restore target remains interactive")
    hud.handle_back()
    check(not hud.hud_hidden and hud.active_power == 2, "back restores HUD and previous tool")
    hud.show_citizen({"id":4,"hp":70,"nation":0,"x":3,"y":4})
    hud.refresh_citizen({"id":4,"hp":69,"nation":0,"x":4,"y":4})
    check(not hud.inspector_body.text.contains("\\n") and hud.inspector_body.text.contains("\n"), "live inspector uses actual newlines")
    hud.hide_inspector()
    hud.set_reduced_motion(false)
    for i in range(20):
        hud.open_palette(true)
        hud.open_palette(false)
    hud.open_palette(true)
    await create_timer(0.3).timeout
    check(hud.palette_panel.visible and hud.palette_panel.modulate.a == 1.0, "rapid reopening has no stale hide callback")
    hud.set_reduced_motion(true)
    hud.open_palette(false)
    check(not hud.palette_panel.visible, "reduced motion closes immediately")
    for button in hud.buttons:
        if is_instance_valid(button):
            check(button.custom_minimum_size.x >= 48 and button.custom_minimum_size.y >= 48, "all reusable controls have 48-unit minimum targets")
    hud.free()
    print("PREMIUM_HUD_TESTS_%s (%d assertions)" % ["PASSED" if ok else "FAILED", assertions])
    quit(0 if ok else 1)
