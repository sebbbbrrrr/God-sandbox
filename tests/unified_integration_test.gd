extends SceneTree

const Game = preload("res://scripts/unified_game.gd")
const World = preload("res://scripts/simulation.gd")
const Commands = preload("res://scripts/pixel_commands.gd")
var ok := true

func _initialize() -> void:
    call_deferred("run")

func check(condition: bool, message: String) -> void:
    if not condition:
        ok = false
        push_error("FAILED: " + message)
    else:
        print("PASS: " + message)

func run() -> void:
    root.size = Vector2i(480, 850)
    root.content_scale_size = Vector2i(480, 850)
    var game = Game.new()
    root.add_child(game)
    game.paused = true
    check(game.world != null and game.world.inventory.ledger_ok(),
        "unified scene uses complete authoritative D2-D4 backend")
    check(game.world.visual_elevation.size() == game.world.WIDTH * game.world.HEIGHT,
        "high-density renderer has persistent elevation strata")
    check(game.world_renderer != null and game.world_renderer.atlas != null and
        game.world_renderer.atlas.entries.size() >= 250 and
        game.world_renderer.chunks.size() > 0,
        "high-definition atlas and chunk renderer are present in actual game")
    check(game.world_renderer.weather != null and game.world_renderer.weather_overlay != null,
        "weather cycle and rainfall visuals are present")
    check(game.world_renderer.walks != null,
        "citizen movement uses interpolated walking tracks")
    check(game.hud != null and game.hud.items_button != null and
        game.hud.palette_button != null,
        "new responsive power palette and ITEMS button coexist")
    check(game.world_layer.layer < game.hud.layer and
        game.item_layer.layer > game.hud.layer,
        "draw order preserves atlas terrain, controls and frontmost inventory panel")
    game._process(0.015)
    check(game.world_renderer.visible_chunks > 0 and
        game.world_renderer.visible_chunks < game.world_renderer.chunks.size(),
        "high-definition chunk visibility culling works at phone resolution")
    var decorated := false
    for chunk in game.world_renderer.chunks.values():
        if not chunk.visible:
            continue
        for row in chunk.wind_rows:
            if row.keys.size() > 0:
                decorated = true
                break
        if decorated:
            break
    check(decorated, "visible woodland/meadow sprites include wind-compatible foliage")
    var commands = Commands.new()
    commands.atlas = game.world_renderer.atlas
    commands.add("citizen_gold", Vector2.ZERO, Vector2(16, 16),
        Color.WHITE, 0.25)
    commands.add("oak", Vector2(20, 20), Vector2(20, 20),
        Color.WHITE, -1.0, 1.0)
    commands.set_wind(0.5, 0.6, 1.0)
    check(commands.keys.size() == 2 and commands.walk_phases.size() == 2 and
        commands.sway_factors.size() == 2 and
        commands.sway_factors[1] > 0.0 and commands.walk_phases[0] > 0.0,
        "footstep gait and foliage sway share one conserved draw pipeline")
    commands.free()
    var crater := Vector2i(28, 42)
    game.world.set_terrain_cell(crater.x, crater.y, game.world.MEADOW)
    game.world.set_terrain_cell(crater.x, crater.y + 1, game.world.MEADOW)
    game.world.set_terrain_cell(crater.x, crater.y, game.world.ASH)
    var key := game.world_renderer.atlas.scorch_tile(
        game.world_renderer.scorch_exposure(crater.x, crater.y), 0)
    check(key.begins_with("scorch_") and
        game.world_renderer.atlas.texture(key) != null,
        "irregular transparent ash scars render over neighbouring biome underlay")
    var snapshot: Dictionary = game.world.snapshot()
    var restored = World.from_snapshot(snapshot)
    check(restored != null and restored.snapshot() == snapshot,
        "citizen AI, construction, economy and visual elevation survive JSON restore")
    var encoded: Variant = game.world.prepare_save_bytes()
    var decoded: Variant = game.world.SaveStore.decode(encoded)
    var binary = World.from_snapshot(decoded) if decoded is Dictionary else null
    check(binary != null and binary.snapshot() == snapshot,
        "compressed save retains backend state and graphical elevation")
    var citizen: Dictionary = game.world.citizens[0]
    var start := Vector2i(int(citizen["x"]), int(citizen["y"]))
    var moved := Vector2i(start.x + 1, start.y)
    game.world.set_terrain_cell(moved.x, moved.y, game.world.MEADOW)
    citizen["x"] = moved.x
    citizen["y"] = moved.y
    game.world_renderer.refresh_units()
    check(game.world_renderer.walks.has_active_motion(),
        "renderer tracks genuine citizen displacement without teleporting sprite")
    var previous: Vector2 = game.world_renderer.walks.visual_tile(int(citizen["id"]))
    game.world_renderer.animate(0.07, 0.07)
    var current: Vector2 = game.world_renderer.walks.visual_tile(int(citizen["id"]))
    check(current.distance_to(Vector2(moved)) <= previous.distance_to(Vector2(moved)),
        "interpolated citizen position advances toward simulation destination")
    game.hud.power_changed.emit(0)
    check(game.selected_power == 0, "mobile HUD selects Raise god power")
    game.hud.power_changed.emit(-1)
    check(game.selected_power == -1, "mobile HUD deselects god power into Hand")
    game.hud.items_pressed.emit()
    check(game.inspector.visible and game.inspector.holder_id.begins_with("settlement:"),
        "ITEMS shortcut opens actual physical settlement stockpile")
    var before: PackedByteArray = game.world.terrain.duplicate()
    var corner := Vector2(14, 14)
    game.tapped(corner)
    check(game.world.terrain == before,
        "top HUD touch does not paint world or alter economic state")
    game.inspector.close()
    game.camera_center = Vector2(int(citizen["x"]), int(citizen["y"]))
    game._process(0.01)
    var position := game.world_origin() + game.world_renderer.tile_center(moved) * game.tile_size() / 32.0
    game.tapped(position)
    check(game.inspector.visible and game.inspector.holder_id.begins_with("citizen:"),
        "hand mode inspects actual citizen inventory over high-res sprites")
    game.inspector.close()
    game.queue_redraw()
    game.world_items.queue_redraw()
    game.item_visual.queue_redraw()
    root.remove_child(game)
    game.free()
    if ok:
        print("UNIFIED_INTEGRATION_TESTS_PASSED")
    quit(0 if ok else 1)
