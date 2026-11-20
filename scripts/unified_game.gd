extends "res://scripts/game.gd"
# Unified Android test shell: the D4 simulator and inventory authority are
# preserved. Only the view/controller is replaced by Phase 1b pixel renderer,
# animated HUD, mobile input and frame-interpolated citizen presentation.
const Renderer = preload("res://scripts/pixel_world_renderer.gd")
const HUD = preload("res://scripts/sandbox_ui.gd")
const UnifiedOverlay = preload("res://scripts/ui/unified_world_overlay.gd")
const AudioManagerScript = preload("res://scripts/audio/audio_manager.gd")
const LivingWorldAudio = preload("res://scripts/audio/living_world_audio.gd")
const ConstructionAudioBridge = preload("res://scripts/audio/construction_audio_bridge.gd")

var world_renderer: PixelWorldRenderer
var hud: GodSandboxHUD
var world_layer: CanvasLayer
var world_items: Node2D
var item_layer: CanvasLayer
var item_visual: Node2D
var inspected_citizen_id := -1
# Keep the simulation from monopolising the Android main thread at 2x/4x.
# One expensive world.step() cannot be interrupted, but subsequent steps are
# deferred once the CPU slice has been consumed. Rendering uses real time.
const SIM_TICK_SECONDS := 1.0 # At 1x, one authoritative world tick takes one real second.
const MAX_SIM_STEPS_PER_FRAME := 4
const SIM_FRAME_BUDGET_USEC := 4500
const MAX_SIM_BACKLOG_SECONDS := 4.0
const VISUAL_REFRESH_SECONDS := 1.0 / 30.0
const HUD_REFRESH_SECONDS := 0.1
var visual_refresh_accum := 0.0
var hud_refresh_accum := 0.0
var units_need_refresh := false
var work_visual_clock := 0.0
var game_audio: Node
var living_audio = LivingWorldAudio.new()
var construction_audio = ConstructionAudioBridge.new()


func _ready() -> void:
    world = load_world()
    if world == null:
        world = Simulation.new(int(Time.get_unix_time_from_system()) % 2147483647)
    font = ThemeDB.fallback_font
    game_audio = AudioManagerScript.new()
    game_audio.name = "GameAudio"
    add_child(game_audio)
    living_audio.reset()
    construction_audio.reset()
    camera_center = Vector2(world.WIDTH / 2.0, world.HEIGHT / 2.0)
    selected_power = -1
    brush_index = 1
    world_renderer = Renderer.new()
    world_renderer.setup(world)
    add_child(world_renderer)
    world_renderer.refresh_units()

    world_layer = CanvasLayer.new()
    world_layer.layer = 5
    world_layer.name = "EquipmentAndDrops"
    add_child(world_layer)
    world_items = UnifiedOverlay.new()
    world_items.game = self
    world_items.mode = "world"
    world_layer.add_child(world_items)

    hud = HUD.new()
    hud.name = "ResponsiveHUD"
    add_child(hud)
    hud.power_changed.connect(_set_power)
    hud.brush_changed.connect(_set_brush)
    hud.pause_pressed.connect(_toggle_pause)
    hud.speed_pressed.connect(_cycle_speed)
    hud.save_pressed.connect(save_world)
    hud.items_pressed.connect(_open_items)
    hud.set_active_power(selected_power)
    hud.set_brush(brush_index)

    item_layer = CanvasLayer.new()
    item_layer.layer = 20
    item_layer.name = "PhysicalInventory"
    add_child(item_layer)
    item_visual = UnifiedOverlay.new()
    item_visual.game = self
    item_visual.mode = "items"
    item_layer.add_child(item_visual)

    get_viewport().size_changed.connect(_on_resized)
    _on_resized()

func _on_resized() -> void:
    if game_audio != null:
        game_audio.configure_listener(ui_size(), 0.0)
    queue_redraw()
    if world_items != null:
        world_items.queue_redraw()
    if item_visual != null:
        item_visual.queue_redraw()

# The latest mobile HUD owns safe-area controls; the terrain extends beneath
# it, and physics/camera use identical full-viewport coordinate transforms.
func camera_view_center() -> Vector2:
    # HUD floats ABOVE the terrain: it does not reduce the camera canvas.
    return ui_size() * 0.5

func world_origin() -> Vector2:
    return (camera_view_center() - camera_center * tile_size()).round()

func inside_world(position: Vector2) -> bool:
    var size := ui_size()
    return position.x >= 0 and position.x < size.x and position.y >= 0 and \
        position.y < size.y and (hud == null or not hud.blocks_world_input(position))

func screen_to_tile(position: Vector2) -> Vector2i:
    return world_renderer.tile_at((position - world_origin()) * 32.0 / tile_size()) \
        if world_renderer != null else super.screen_to_tile(position)

func _draw() -> void:
    # Terrain and citizens are owned by PixelWorldRenderer, not the old
    # primitive D4 canvas. The grid brush is still drawn above that renderer.
    if world != null:
        draw_brush_preview(ui_size())

func _process(delta: float) -> void:
    if world == null or world_renderer == null:
        return
    var real_delta: float = maxf(0.0, delta)
    visual_refresh_accum += real_delta
    if not paused:
        work_visual_clock += real_delta * float(simulation_speed)
    hud_refresh_accum += real_delta
    if not paused:
        # Bound accumulated work after a device stall rather than trying to
        # replay seconds of expensive AI updates on the next rendered frame.
        sim_accum = minf(sim_accum + minf(real_delta, 0.1) * float(simulation_speed), MAX_SIM_BACKLOG_SECONDS)
        var frame_started: int = Time.get_ticks_usec()
        var iterations := 0
        while sim_accum >= SIM_TICK_SECONDS and iterations < MAX_SIM_STEPS_PER_FRAME:
            if iterations > 0 and Time.get_ticks_usec() - frame_started >= SIM_FRAME_BUDGET_USEC:
                break
            world.step()
            _audio_world_step()
            sim_accum -= SIM_TICK_SECONDS
            iterations += 1
            autosave_ticks += 1
        if iterations > 0:
            units_need_refresh = true
        if autosave_ticks >= 600:
            autosave_ticks = 0
            save_world()

    if not paused:
        living_audio.observe_ambience(world, game_audio, camera_center, world_origin(),
            tile_size(), ui_size(), 0.0, Time.get_ticks_msec())
    world_renderer.update_view(world_origin(), tile_size(),
        Rect2(Vector2.ZERO, ui_size()))
    # Sprite interpolation follows real display time, not accelerated AI time.
    # At high speeds, coalesce multiple authoritative steps into one visual
    # snapshot instead of rebuilding every citizen row on every frame.
    var refresh_visuals: bool = visual_refresh_accum >= VISUAL_REFRESH_SECONDS
    if refresh_visuals:
        visual_refresh_accum = fmod(visual_refresh_accum, VISUAL_REFRESH_SECONDS)
        if units_need_refresh:
            world_renderer.refresh_units()
            units_need_refresh = false
    if world_renderer.walks != null:
        world_renderer.walks.walk_seconds = 0.85 / float(simulation_speed)
    world_renderer.animate(real_delta, 0.0 if paused else real_delta)
    if hud != null and (hud_refresh_accum >= HUD_REFRESH_SECONDS or paused):
        hud_refresh_accum = 0.0
        hud.update_stats(1 + world.tick / 3600, world.citizens.size(), paused,
            simulation_speed)
        _update_inspection()
    render_accum += real_delta
    if render_accum >= VISUAL_REFRESH_SECONDS:
        render_accum = fmod(render_accum, VISUAL_REFRESH_SECONDS)
        queue_redraw()
        world_items.queue_redraw()
        if inspector.visible:
            item_visual.queue_redraw()

func _audio_world_step() -> void:
    # Read-only sound observers follow the same authoritative step as the AI.
    # Real-time audio is never multiplied by the time-speed setting.
    var origin := world_origin()
    var ts := tile_size()
    var size := ui_size()
    living_audio.observe_movement(world, game_audio, origin, ts, size, 0.0,
        simulation_speed > 1)
    construction_audio.observe(world, living_audio, game_audio, origin, ts, size,
        0.0, work_visual_clock)

func paint_segment(from_cell: Vector2i, to_cell: Vector2i) -> void:
    if not editable_power():
        return
    var changed: int = Brush.paint_segment(world, selected_power, from_cell,
        to_cell, BRUSH_RADII[brush_index])
    if changed > 0:
        game_audio.play_power(selected_power, world_origin() +
            (Vector2(to_cell) + Vector2(0.5, 0.5)) * tile_size())
    queue_redraw()

func _set_power(power: int) -> void:
    game_audio.play_ui("ui.select")
    selected_power = power
    preview_visible = false
    stroke_active = false
    if power != -1:
        inspector.close()
        hud.hide_inspector()
        inspected_citizen_id = -1
    _on_resized()

func _set_brush(index: int) -> void:
    game_audio.play_ui("ui.select")
    brush_index = index
    queue_redraw()

func _toggle_pause() -> void:
    game_audio.play_ui("ui.toggle")
    paused = not paused
    hud.update_stats(1 + world.tick / 3600, world.citizens.size(), paused, simulation_speed)

func _cycle_speed() -> void:
    game_audio.play_ui("ui.toggle")
    simulation_speed = 2 if simulation_speed == 1 else (4 if simulation_speed == 2 else 1)
    hud.update_stats(1 + world.tick / 3600, world.citizens.size(), paused, simulation_speed)

func _open_items() -> void:
    selected_power = -1
    hud.set_active_power(-1)
    hud.hide_inspector()
    open_items_shortcut()
    item_visual.queue_redraw()

func _update_inspection() -> void:
    if inspected_citizen_id < 0 or paused:
        return
    var person: Dictionary = world.inventory._person(world, inspected_citizen_id)
    if not person.is_empty() and int(person.get("hp", 0)) > 0:
        hud.refresh_citizen(person)
    else:
        inspected_citizen_id = -1
        hud.hide_inspector()
        inspector.close()

func _input(event: InputEvent) -> void:
    # Android emulates mouse for native Godot buttons. Real touch is already
    # processed separately for the world so do not duplicate gestures.
    if event.device == InputEvent.DEVICE_ID_EMULATION and \
            (event is InputEventMouseButton or event is InputEventMouseMotion):
        return
    if inspector.visible:
        super._input(event)
        if item_visual != null:
            item_visual.queue_redraw()
        get_viewport().set_input_as_handled()
        return
    super._input(event)

func tapped(position: Vector2) -> void:
    # Never apply a god power when a HUD control was touched. The Control
    # handles its own button press via the emulated mouse event.
    if not inside_world(position):
        return
    var cell := screen_to_tile(position)
    if world.index_of(cell.x, cell.y) < 0:
        return
    if selected_power == -1:
        hud.hide_inspector()
        if inspect_cell(cell):
            inspected_citizen_id = inspector.focus_citizen_id
            item_visual.queue_redraw()
            return
        inspected_citizen_id = -1
        var kinds := ["Ocean", "Beach", "Meadow", "Forest", "Mountain",
            "Ash", "Settlement"]
        var kind: int = world.at(cell.x, cell.y)
        hud.show_terrain(cell, kinds[clampi(kind, 0, kinds.size() - 1)],
            world.height_at(cell.x, cell.y))
    elif editable_power():
        paint_segment(cell, cell)
    elif world.apply_power(selected_power, cell.x, cell.y):
        game_audio.play_power(selected_power, world_origin() +
            (Vector2(cell) + Vector2(0.5, 0.5)) * tile_size())
        world_renderer.refresh_units()
        world_renderer.add_power_effect(selected_power, cell)
        world_items.queue_redraw()
        queue_redraw()
