extends SceneTree
## Premium menu contract: real Android Controls, not screenshots or mock UI.
const Game = preload("res://scripts/unified_game.gd")
var passed := true
var checks := 0

func _initialize() -> void:
    call_deferred("run")

func check(ok: bool, message: String) -> void:
    checks += 1
    if ok:
        print("PASS: " + message)
    else:
        passed = false
        push_error("FAILED: " + message)

func frame() -> void:
    for i in range(3):
        await process_frame

func run() -> void:
    root.size = Vector2i(480, 850)
    root.content_scale_size = root.size
    var game = Game.new()
    root.add_child(game)
    game.paused = true
    await frame()
    var hud = game.hud
    var sheet = game.civilisation_ui
    check(hud.civilisation_button != null and sheet != null,
        "shared premium HUD and town inspector load in real world scene")
    check(hud.civilisation_button.button_down.get_connections().size() > 0 and
        hud.civilisation_button.button_up.get_connections().size() > 0,
        "navigation button has physical press and release feedback")
    check(hud.palette_button.button_down.get_connections().size() > 0,
        "power tools also use press feedback")
    check(sheet.tab_buttons.size() == 5 and sheet.hero_values.size() == 4,
        "five tabs and four high-contrast live metrics")
    var initial_state: Dictionary = game.world.snapshot()
    hud.civilisation_pressed.emit()
    await frame()
    check(sheet.is_open and sheet.hero.visible and sheet.scroller.visible,
        "town panel has a distinct overview and scrollable body")
    check(sheet.hero_name.text != "" and sheet.hero_values[0].text != "",
        "town hero renders actual selection instead of static placeholder")
    sheet._switch_tab(2)
    check(sheet.current_tab == 2, "route tab selects promptly")
    sheet._on_map_toggled(true)
    check(game.civilisation_routes.enabled,
        "road overlay is coupled to independent route toggle")
    check(game.world.snapshot() == initial_state,
        "UI and animations never mutate authoritative simulation state")
    sheet._on_map_toggled(false)
    sheet.close()
    await frame()
    check(not sheet.is_open, "close works with menu transitions")

    for size in [Vector2i(320, 568), Vector2i(393, 852),
            Vector2i(480, 850), Vector2i(850, 480)]:
        root.size = size
        root.content_scale_size = size
        await frame()
        hud._layout()
        sheet.open_for(0)
        await frame()
        var bounds: Rect2 = sheet.sheet.get_global_rect()
        check(bounds.position.x >= -1 and bounds.position.y >= -1 and
            bounds.end.x <= size.x + 1 and bounds.end.y <= size.y + 1,
            "inspector fits safe viewport " + str(size))
        check(sheet.scroller.size.y > 35 and sheet.scroller.size.x > 100,
            "inspector scroll region remains usable " + str(size))
        sheet.close()
        await frame()
        hud.open_palette(true)
        await frame()
        var palette: Rect2 = hud.palette_panel.get_global_rect()
        if not (palette.position.y >= -1 and palette.end.y <= size.y + 1 and palette.end.x <= size.x + 1):
            print("QA_SCREEN_BOUNDS size=", size, " palette=", palette,
                " palette_min=", hud.palette_panel.get_combined_minimum_size(),
                " grid_cols=", hud.power_grid.columns, " dock=", hud.dock_panel.position)
        check(palette.position.y >= -1 and palette.end.y <= size.y + 1 and
            palette.end.x <= size.x + 1,
            "power palette remains fully on-screen " + str(size))
        hud.open_palette(false)
        await frame()
    hud._show_settings(true)
    await frame()
    check(hud.settings_panel.visible and hud.settings_panel.size.y <= root.size.y,
        "world settings are bounded in landscape")
    hud._show_settings(false)
    game._set_reduced_menu_motion(true)
    check(sheet.reduced_motion, "reduced motion propagates to all civilisation views")
    game._set_reduced_menu_motion(false)
    root.remove_child(game)
    game.free()
    print("CIVILISATION_PREMIUM_MENU_%s (%d assertions)" %
        ["PASSED" if passed else "FAILED", checks])
    quit(0 if passed else 1)
