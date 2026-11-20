extends SceneTree
const Game = preload("res://scripts/game.gd")
const World = preload("res://scripts/simulation.gd")

func _initialize() -> void:
    var ok := true
    root.size = Vector2i(480, 850) # Headless runners default to a tiny viewport.
    var game = Game.new()
    root.add_child(game)
    game.world = scene_world()
    game.camera_center = Vector2(20, 20)
    game.selected_power = -1
    var cell := Vector2i(20, 20)
    var center := game.world_origin() + (Vector2(cell) + Vector2(0.5, 0.5)) * game.tile_size()
    print("D4_VIEWPORT_DEBUG size=", game.get_viewport_rect().size,
        " center=", center, " hit=", game.screen_to_tile(center), " inside=", game.inside_world(center))
    ok = check(game.inside_world(center) and game.screen_to_tile(center) == cell,
        "tap-to-inspect maps pixel coordinates to actual citizen tile") and ok
    game.tapped(center)
    ok = check(game.inspector.visible and
        game.inspector.holder_id == "citizen:1" and
        game.inspector.focus_citizen_id == 1,
        "one-finger hand tap opens living citizen's actual inventory panel") and ok
    var bounds: Rect2 = game.inspector.geometry(
        game.get_viewport_rect().size, game.toolbar_height())["panel"]
    ok = check(bounds.end.y < game.get_viewport_rect().size.y - game.toolbar_height(),
        "inventory modal does not hide god powers or bottom toolbar") and ok
    var previous_terrain: PackedByteArray = game.world.terrain.duplicate()
    var outside: InputEventMouseButton = InputEventMouseButton.new()
    outside.button_index = MOUSE_BUTTON_LEFT
    outside.pressed = true
    outside.position = Vector2(2, 100)
    game._input(outside)
    ok = check(not game.inspector.visible and game.world.terrain == previous_terrain,
        "outside modal tap dismisses and never paints over the world") and ok
    game.selected_power = 0
    game.tapped(Vector2(game.get_viewport_rect().size.x - 65,
        game.get_viewport_rect().size.y - game.toolbar_height() + 15))
    ok = check(game.selected_power == -1 and game.inspector.visible and
        game.inspector.holder_id == "citizen:1",
        "ITEMS shortcut unequips terrain brush and reopens acting citizen's pack") and ok
    previous_terrain = game.world.terrain.duplicate()
    var popup: InputEventScreenTouch = InputEventScreenTouch.new()
    popup.index = 0
    popup.position = center
    popup.pressed = true
    game._input(popup)
    popup.pressed = false
    game._input(popup)
    ok = check(game.world.terrain == previous_terrain,
        "modal intercepts touch streams before camera gestures and terrain brush") and ok
    game.inspector.close()
    var extracted: bool = game.world.inventory.extract(game.world, 1,
        "wood", Vector2i(19, 20), 1)
    var dropped: bool = game.world.inventory.transfer(game.world,
        "citizen:1", "ground:" + str(game.world.index_of(20, 20)),
        {"wood": 1}, 1)
    ok = check(extracted and dropped, "physical dropped resources created without debug spawning") and ok
    ok = check(game.inspect_cell(cell) and game.inspector.view_kind == "ground",
        "ground-cache inspection takes priority after a citizen is selected") and ok
    game.inspector.close()
    game.selected_power = 0
    var before: PackedByteArray = game.world.terrain.duplicate()
    game.tapped(center)
    ok = check(game.world.terrain != before,
        "regular raise-land power remains active when inspector is closed") and ok
    ok = check(game.world.inventory.ledger_ok(),
        "inspection and tool visuals never mutate the physical item ledger") and ok
    root.remove_child(game)
    game.free()
    if ok:
        print("GAME_ITEM_UI_TESTS_PASSED")
    quit(0 if ok else 1)

func scene_world():
    var world = World.new(9441, false)
    for y in range(16, 25):
        for x in range(16, 25):
            world.set_terrain_cell(x, y, World.MEADOW)
    world.set_terrain_cell(19, 20, World.FOREST)
    world.capitals[0] = Vector2i(20, 20)
    world.add_citizen(20, 20, 0)
    world.ai_context.begin_tick(world)
    return world

func check(condition: bool, message: String) -> bool:
    if not condition:
        push_error("FAILED: " + message)
        return false
    print("PASS: " + message)
    return true
