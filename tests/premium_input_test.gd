extends SceneTree
class TestGame extends "res://scripts/unified_game.gd":
    func load_world() -> SandboxSimulation:
        return Simulation.new(424242)
    func save_world() -> void:
        pass
var game: Node2D
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
func click(button: Button) -> void:
    var point := button.get_global_rect().get_center()
    var move := InputEventMouseMotion.new()
    move.position = point
    root.push_input(move, true)
    var event := InputEventMouseButton.new()
    event.position = point
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = true
    root.push_input(event, true)
    event = event.duplicate()
    event.pressed = false
    root.push_input(event, true)
    await settle()
func touch(id: int, point: Vector2, pressed: bool, canceled: bool = false) -> void:
    var event := InputEventScreenTouch.new()
    event.index = id
    event.position = point
    event.pressed = pressed
    event.canceled = canceled
    game._input(event)
func drag(id: int, point: Vector2) -> void:
    var event := InputEventScreenDrag.new()
    event.index = id
    event.position = point
    game._input(event)
func run() -> void:
    root.size = Vector2i(400,866)
    root.content_scale_size = root.size
    game = TestGame.new()
    root.add_child(game)
    game.paused = true
    game.hud.set_reduced_motion(true)
    await settle()
    await click(game.hud.category_buttons[0])
    check(game.hud.palette_open and game.hud.active_category == 0, "native GUI opens Terrain category")
    await click(game.hud.power_buttons[0])
    check(game.selected_power == 0 and not game.hud.palette_open, "native GUI equips Raise and dismisses tray")
    await click(game.hud.active_button)
    check(game.selected_power == -1, "native active tool chip unequips power")
    for category in range(4):
        await click(game.hud.category_buttons[category])
        check(game.hud.palette_open and game.hud.active_category == category, "native category tap %d" % category)
        var id: int = game.hud.CATEGORY_POWERS[category][0]
        await click(game.hud.power_buttons[id])
        check(game.selected_power == id, "native tool selection %d" % id)
    await click(game.hud.pause_button)
    check(not game.paused, "native pause button resumes game")
    await click(game.hud.pause_button)
    await click(game.hud.speed_button)
    check(game.simulation_speed == 2, "native speed button changes runtime")
    game.paused = true
    game._set_power(2)
    var before: PackedByteArray = game.world.terrain.duplicate()
    var camera: Vector2 = game.camera_center
    var world_point := Vector2(160,330)
    var ui_point: Vector2 = game.hud.category_buttons[0].get_global_rect().get_center()
    touch(0,ui_point,true)
    touch(1,world_point,true)
    drag(1,world_point+Vector2(50,40))
    touch(1,world_point,false)
    touch(0,ui_point,false)
    check(game.world.terrain == before and game.camera_center == camera, "UI-origin finger cannot paint or join world pinch")
    touch(0,world_point,true)
    touch(1,ui_point,true)
    drag(0,world_point+Vector2(50,40))
    touch(1,ui_point,false)
    touch(0,world_point,false)
    check(game.world.terrain == before and game.camera_center == camera, "touching UI cancels an existing world gesture")
    touch(0,world_point,true)
    game.hud._show_settings(true)
    touch(0,world_point,false)
    check(game.world.terrain == before, "modal opening cancels a held brush")
    game.hud.close_modal()
    var cell: Vector2i = game.screen_to_tile(world_point)
    game.world.set_terrain_cell(cell.x,cell.y,game.world.MEADOW)
    game._set_power(4)
    var people: int = game.world.citizens.size()
    touch(0,world_point,true)
    drag(0,world_point+Vector2(1,1))
    touch(0,world_point+Vector2(1,1),false)
    check(game.world.citizens.size() == people+1, "finger jitter preserves a deliberate tap")
    people = game.world.citizens.size()
    touch(0,world_point,true)
    touch(0,world_point,false,true)
    check(game.world.citizens.size() == people, "Android cancelled touch never activates a power")
    game._set_power(-1)
    game.hud.set_active_power(-1)
    await click(game.hud.hide_button)
    check(game.hud.hud_hidden, "native hide button enters world-only mode")
    await click(game.hud.root.get_node("RestoreHUD"))
    check(not game.hud.hud_hidden, "native restore button restores controls")
    await click(game.hud.category_buttons[5])
    check(game.hud.settings_panel.visible, "native Menu category opens utilities")
    await click(game.hud.items_button)
    check(game.inspector.visible and game.hud.inventory_panel.visible, "native inventory button opens real stockpile model")
    camera = game.camera_center
    touch(0,Vector2(200,400),true)
    drag(0,Vector2(200,200))
    touch(0,Vector2(200,200),false)
    check(game.camera_center == camera, "inventory modal isolates camera gestures")
    game.inspector.close()
    game.hud.sync_inventory()
    check(not game.hud.modal_dim.visible, "model close removes native modal blocker")
    check(game.world.inventory.ledger_ok(), "interface actions retain physical resource conservation")
    # Exercise the actual row and command Controls against conserved materials.
    var w = preload("res://tests/ui_inventory_fixture.gd").make_world()
    check(w != null, "real material fixture crafted unique tools")
    game.world_renderer.free()
    game.world = w
    game.world_renderer = game.Renderer.new()
    game.world_renderer.setup(w)
    game.add_child(game.world_renderer)
    game.inspector.open_for(w,"citizen:1","citizen")
    game.inspector.change_tab(w,"stores")
    game.hud.open_inventory(game.inspector,w)
    await settle()
    var serials: Array = w.toolmaking._matching_serials("settlement:0","stone_axe")
    var serial: String = serials[0]
    var sheet: PanelContainer = game.hud.inventory_panel
    check(sheet.summary.size.y >= 16 and sheet.summary.text != "", "live inventory summary has readable height")
    check(sheet.citizen_label.size.y >= 16, "live biological age has readable height")
    await click(sheet.row_buttons["serial:"+serial])
    check(sheet.detail.size.y >= 40, "serial and condition details have readable multiline height")
    await click(sheet.action_buttons["take"])
    check(str(w.toolmaking.instances[serial]["holder"]) == "citizen:1", "native Take command moves exact selected tool")
    await click(sheet.pack)
    await click(sheet.action_buttons["equip"])
    check(str(w.toolmaking.equipped.get("1","")) == serial, "native Equip command applies physical ownership")
    await click(sheet.action_buttons["drop"])
    check(str(w.toolmaking.instances[serial]["holder"]).begins_with("ground:") and not w.toolmaking.equipped.has("1"), "native Drop command transfers custody and unequips")
    check(w.inventory.ledger_ok(), "native inventory command journey conserves materials")
    game.free()
    print("PREMIUM_INPUT_TESTS_%s (%d assertions)" % ["PASSED" if ok else "FAILED",assertions])
    quit(0 if ok else 1)
