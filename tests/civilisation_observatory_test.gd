extends SceneTree
## Observatory smoke: projections are grounded in actual authorities, snapshots
## are non-mutating, and touchscreen-safe controls can open/close on Android.
const World = preload("res://scripts/simulation.gd")
const Insights = preload("res://scripts/ui/civilisation_insights.gd")
const Sheet = preload("res://scripts/ui/civilisation_dashboard.gd")
const Routes = preload("res://scripts/ui/civilisation_map_overlay.gd")
const Game = preload("res://scripts/unified_game.gd")
var passed := true

func _initialize() -> void:
    call_deferred("run")


func check(ok: bool, description: String) -> void:
    if not ok:
        passed = false
        push_error("FAILED: " + description)
    else:
        print("PASS: " + description)


func fixture():
    var world = World.new(811, false)
    for y in range(30, 43):
        for x in range(22, 69):
            world.set_terrain_cell(x, y, World.MEADOW)
    world.capitals[0] = Vector2i(30, 36)
    world.capitals[1] = Vector2i(59, 36)
    for i in range(5):
        world.add_citizen(30, 36, 0)
    for i in range(3):
        world.add_citizen(59, 36, 1)
    world.ai_context.begin_tick(world)
    world.settlements.rebuild_membership(world)
    return world


func run() -> void:
    root.size = Vector2i(480, 850)
    root.content_scale_size = Vector2i(480, 850)
    var world = fixture()
    var before := world.snapshot()
    var snapshot: Dictionary = Insights.capture(world)
    check(snapshot["settlements"].size() == 2, "legacy settlements shown before new villages form")
    check(int(snapshot["summary"]["population"]) == 8, "live residents, not simulated placeholder counts")
    check(int(snapshot["summary"]["connected"]) == 0, "unbuilt road links are not displayed as connected")
    check(world.snapshot() == before, "read-only insight collection does not mutate game save state")
    var a: Dictionary = snapshot["settlements"][0]
    check(int(a["population"]) == 5 and int(a["housing_pct"]) == 0,
        "housing shortfall is calculated from real construction capacity")
    check(not a["alerts"].is_empty(), "bottlenecks are exposed when housing is insufficient")

    var first: Dictionary = world.citizens[0]
    var last: Dictionary = world.citizens[5]
    var mind: Dictionary = world.citizen_ai_by_id[str(first["id"])]
    mind["relationships"].append({"id": int(last["id"]), "trust": 65, "rivalry": 10})
    world.regional_economy.links["0:1"] = {
        "a": 0, "b": 1, "path": [[30, 36], [31, 36], [32, 36], [59, 36]],
        "status": "building", "attempt": world.tick}
    world.regional_economy.roads[str(world.index_of(31, 36))] = {
        "nation": 0, "settlement_id": 0, "type": "trail", "built_tick": world.tick}
    snapshot = Insights.capture(world)
    check(snapshot["routes"].size() == 1 and
        int(snapshot["routes"][0]["built"]) == 1 and int(snapshot["routes"][0]["required"]) == 2,
        "road progress counts physically built intermediate tiles")
    check(int(snapshot["summary"]["connected"]) == 0,
        "partial route remains building, not trading")
    check(snapshot["social"].size() == 1 and
        int(snapshot["social"][0]["trust"]) == 65,
        "cross-town social connections are derived from personal AI memories")

    var dashboard = Sheet.new()
    dashboard.setup(world)
    root.add_child(dashboard)
    dashboard.open_for(0)
    check(dashboard.is_open and dashboard.picker.item_count == 2 and dashboard.selected_id == 0,
        "Towns sheet opens the selected settlement on a small screen")
    dashboard._switch_tab(1)
    check(dashboard.current_tab == 1, "economy tab navigates using real Control buttons")
    dashboard._on_map_toggled(true)
    check(dashboard.show_routes and not dashboard.snapshot.is_empty(),
        "map toggle uses live route snapshot")
    dashboard.close()
    check(not dashboard.is_open and dashboard.show_routes,
        "map route overlay persists independently when inspector closes")
    var fake_game := Node2D.new()
    root.add_child(fake_game)
    var overlay = Routes.new()
    overlay.configure(fake_game)
    overlay.set_snapshot(snapshot)
    overlay.set_enabled(true)
    check(overlay.enabled, "route overlay can be enabled without writing to simulation")
    overlay.free()
    root.remove_child(fake_game)
    fake_game.free()
    root.remove_child(dashboard)
    dashboard.free()

    var game = Game.new()
    root.add_child(game)
    game.paused = true
    check(game.hud.civilisation_button != null and game.civilisation_ui != null,
        "unified Android world contains Towns shortcut and complete inspector")
    game.hud.civilisation_pressed.emit()
    check(game.civilisation_ui.is_open and game.selected_power == -1,
        "opening inspector switches to Hand and blocks world powers")
    var camera := game.camera_center
    var terrain := game.world.terrain.duplicate()
    var touch := InputEventScreenTouch.new()
    touch.index = 0
    touch.pressed = true
    touch.position = Vector2(240, 330)
    game._input(touch)
    touch.pressed = false
    game._input(touch)
    check(game.camera_center == camera and game.world.terrain == terrain,
        "touches over open inspector do not pan or paint")
    game.hud.civilisation_pressed.emit()
    check(not game.civilisation_ui.is_open, "top-bar Towns control closes inspector")
    root.remove_child(game)
    game.free()
    print("CIVILISATION_OBSERVATORY_%s" % ("PASSED" if passed else "FAILED"))
    quit(0 if passed else 1)
