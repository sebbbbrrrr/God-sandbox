extends SceneTree
# Reproduces the Huawei P30 2-finger drift seen in IMG_9507.mp4:
# the pixel-world camera and old bottom-toolbar camera used different centres.
const Game = preload("res://scripts/unified_game.gd")
var success := true

func _initialize() -> void:
    call_deferred("run")

func check(condition: bool, description: String) -> void:
    if not condition:
        success = false
        push_error("FAILED: " + description)
    else:
        print("PASS: " + description)

func world_under(game: Node2D, at: Vector2) -> Vector2:
    return game.camera_center + (at - game.camera_view_center()) / game.tile_size()

func visual_under(game: Node2D, at: Vector2) -> Vector2:
    return (at - game.world_origin()) / game.tile_size()

func touch(game: Node2D, index: int, at: Vector2, down: bool) -> void:
    var e := InputEventScreenTouch.new()
    e.index = index
    e.position = at
    e.pressed = down
    game._input(e)

func drag(game: Node2D, index: int, at: Vector2) -> void:
    var e := InputEventScreenDrag.new()
    e.index = index
    e.position = at
    game._input(e)

func mouse_wheel(game: Node2D, at: Vector2, upwards: bool) -> void:
    var e := InputEventMouseButton.new()
    e.position = at
    e.button_index = MOUSE_BUTTON_WHEEL_UP if upwards else MOUSE_BUTTON_WHEEL_DOWN
    e.pressed = true
    game._input(e)

func assert_pivot(game: Node2D, previous_screen: Vector2, next_screen: Vector2,
        action: Callable, description: String) -> void:
    var initial: Vector2 = world_under(game, previous_screen)
    action.call()
    var after: Vector2 = world_under(game, next_screen)
    check(after.distance_to(initial) < 0.001,
        description + " — no world-coordinate drift")
    check(visual_under(game, next_screen).distance_to(initial) * game.tile_size() < 1.2,
        description + " — rendered atlas stays under fingertips")

func run() -> void:
    root.size = Vector2i(480, 850)
    root.content_scale_size = Vector2i(480, 850)
    var game = Game.new()
    root.add_child(game)
    game.paused = true
    game.zoom = 1.0
    game.camera_center = Vector2(48.0, 64.0)
    game.selected_power = 0 # equipped Raise brush must never paint during pinch
    check(game.camera_view_center().distance_to(game.ui_size() * 0.5) < 0.01,
        "unified HUD and renderer share full screen centre, not old 188px toolbar offset")
    var start_a := Vector2(145.0, 350.0)
    var start_b := Vector2(290.0, 450.0)
    touch(game, 0, start_a, true)
    touch(game, 1, start_b, true)
    var center := (start_a + start_b) * 0.5
    var end_a := Vector2(98.0, 327.0)
    var end_b := Vector2(350.0, 500.0)
    var half_center := (end_a + start_b) * 0.5
    var terrain_before: PackedByteArray = game.world.terrain.duplicate()
    assert_pivot(game, center, half_center,
        func(): drag(game, 0, end_a),
        "first finger spreading while second is stationary")
    var end_center := (end_a + end_b) * 0.5
    assert_pivot(game, half_center, end_center,
        func(): drag(game, 1, end_b),
        "second finger spreading at off-centre coordinates")
    check(game.zoom > 1.5 and game.zoom < 2.0,
        "pinch increases magnification without relocating target")
    check(game.world.terrain == terrain_before, "pinch does not paint even if brush equipped")
    var moved_a := end_a + Vector2(20, -17)
    var moved_b := end_b + Vector2(20, -17)
    var moved_half := (moved_a + end_b) * 0.5
    assert_pivot(game, end_center, moved_half,
        func(): drag(game, 0, moved_a),
        "centroid pan from first finger keeps original world anchor")
    var moved_center := (moved_a + moved_b) * 0.5
    assert_pivot(game, moved_half, moved_center,
        func(): drag(game, 1, moved_b),
        "centroid pan from second finger keeps original world anchor")
    var initial_world: Vector2 = world_under(game, moved_center)
    var zoomed_distance: float = game.zoom
    var tiny_a := moved_a + Vector2(37, 22)
    var tiny_b := moved_b + Vector2(-37, -22)
    drag(game, 0, tiny_a)
    drag(game, 1, tiny_b)
    check(game.zoom < zoomed_distance,
        "pinching inward smoothly reverses zoom")
    var now_center := (tiny_a + tiny_b) * 0.5
    check(world_under(game, now_center).distance_to(initial_world) < 0.001,
        "zoom-in followed by zoom-out does not drift toward ocean")
    touch(game, 0, tiny_a, false)
    touch(game, 1, tiny_b, false)
    check(game.touches.is_empty() and not game.multi_touch,
        "pinch ends without leaving an active pan or brush gesture")
    game.selected_power = -1
    var click := Vector2(114, 276)
    assert_pivot(game, click, click,
        func(): mouse_wheel(game, click, true),
        "desktop mouse-wheel zoom follows pointer")
    assert_pivot(game, click, click,
        func(): mouse_wheel(game, click, false),
        "mouse-wheel zoom-out follows the same pointer")
    game.zoom = 3.9
    var far_a := Vector2(134, 390)
    var far_b := Vector2(270, 445)
    touch(game, 0, far_a, true)
    touch(game, 1, far_b, true)
    var anchor_before: Vector2 = world_under(game, (far_a + far_b) * 0.5)
    drag(game, 0, Vector2(70, 360))
    drag(game, 1, Vector2(320, 480))
    var anchor_after: Vector2 = world_under(game, (Vector2(70, 360) + Vector2(320, 480)) * 0.5)
    check(is_equal_approx(game.zoom, 4.0) and
        anchor_before.distance_to(anchor_after) < 0.001,
        "maximum zoom clamp does not snap camera to a different world location")
    touch(game, 0, Vector2(70, 360), false)
    touch(game, 1, Vector2(320, 480), false)
    root.remove_child(game)
    game.free()
    if success:
        print("PINCH_ZOOM_ANCHOR_TESTS_PASSED")
    quit(0 if success else 1)
