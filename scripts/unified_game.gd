extends "res://scripts/game.gd"
# Unified Android test shell: the D4 simulator and inventory authority are
# preserved. Only the view/controller is replaced by Phase 1b pixel renderer,
# animated HUD, mobile input and frame-interpolated citizen presentation.
const Renderer = preload("res://scripts/pixel_world_renderer.gd")
const HUD = preload("res://scripts/sandbox_ui.gd")
const WorldFiles = preload("res://scripts/ui/world_files.gd")
const UnifiedOverlay = preload("res://scripts/ui/unified_world_overlay.gd")

var world_renderer: PixelWorldRenderer
var hud: GodSandboxHUD
var world_layer: CanvasLayer
var world_items: Node2D
var item_layer: CanvasLayer
var item_visual: Node2D
var inspected_citizen_id := -1
var ui_touches := {}
var touch_origin := Vector2.ZERO
var mouse_origin := Vector2.ZERO
var mouse_world_pressed := false
var mouse_moved := false
var details_accum := 0.0
var last_save_error: Error = OK
# Keep the simulation from monopolising the Android main thread at 2x/4x.
# One expensive world.step() cannot be interrupted, but subsequent steps are
# deferred once the CPU slice has been consumed. Rendering uses real time.
const SIM_TICK_SECONDS := 0.1
const MAX_SIM_STEPS_PER_FRAME := 4
const SIM_FRAME_BUDGET_USEC := 4500
const MAX_SIM_BACKLOG_SECONDS := 0.25
const VISUAL_REFRESH_SECONDS := 1.0 / 30.0
const HUD_REFRESH_SECONDS := 0.1
var visual_refresh_accum := 0.0
var hud_refresh_accum := 0.0
var units_need_refresh := false


func _ready() -> void:
    world = load_world()
    if world == null:
        world = Simulation.new(int(Time.get_unix_time_from_system()) % 2147483647)
    font = ThemeDB.fallback_font
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
    hud.save_pressed.connect(_manual_save)
    hud.reload_pressed.connect(_reload_saved_world)
    hud.interaction_started.connect(_cancel_world_gesture)
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
    get_tree().auto_accept_quit = false
    _refresh_hud()
    _on_resized()

func _on_resized() -> void:
    _cancel_world_gesture()
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
    if hud != null and hud.inventory_model != null and not inspector.visible:
        hud.sync_inventory()
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
            sim_accum -= SIM_TICK_SECONDS
            iterations += 1
            autosave_ticks += 1
        if iterations > 0:
            units_need_refresh = true
        if autosave_ticks >= 600:
            autosave_ticks = 0
            save_world()

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
    world_renderer.animate(real_delta, 0.0 if paused else real_delta)
    if hud != null and hud_refresh_accum >= HUD_REFRESH_SECONDS:
        hud_refresh_accum = 0.0
        _refresh_hud()
        _update_inspection()
        hud.sync_inventory()
    details_accum += real_delta
    if details_accum >= 1.0:
        details_accum = 0.0
        if hud.palette_open and hud.active_category == 4:
            _refresh_world_details()
    render_accum += real_delta
    if render_accum >= VISUAL_REFRESH_SECONDS:
        render_accum = fmod(render_accum, VISUAL_REFRESH_SECONDS)
        queue_redraw()
        world_items.queue_redraw()
        if inspector.visible:
            item_visual.queue_redraw()

func _set_power(power: int) -> void:
    selected_power = power
    preview_visible = false
    stroke_active = false
    if power != -1:
        inspector.close()
        hud.hide_inspector()
        inspected_citizen_id = -1
    _on_resized()

func _set_brush(index: int) -> void:
    brush_index = index
    queue_redraw()

func _toggle_pause() -> void:
    paused = not paused
    _refresh_hud()

func _cycle_speed() -> void:
    simulation_speed = 2 if simulation_speed == 1 else (4 if simulation_speed == 2 else 1)
    _refresh_hud()

func _open_items() -> void:
    selected_power = -1
    hud.set_active_power(-1)
    hud.hide_inspector()
    hud.close_modal()
    open_items_shortcut()
    if inspector.visible:
        hud.open_inventory(inspector, world)
    else:
        hud.notify("No settlement stores to inspect yet")

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

# UI owns any pointer that begins on a Control for its entire lifetime.
# Real touch drives the world; its emulated mouse only drives native Controls.
func _input(event: InputEvent) -> void:
    if event.device == InputEvent.DEVICE_ID_EMULATION and (event is InputEventMouseButton or event is InputEventMouseMotion):
        return
    if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        hud.handle_back()
        get_viewport().set_input_as_handled()
        return
    if event is InputEventScreenTouch:
        if event.pressed:
            if hud.blocks_world_input(event.position) or not ui_touches.is_empty():
                _cancel_world_gesture()
                ui_touches[event.index] = true
                return
            touches[event.index] = event.position
            if touches.size() == 1:
                primary_touch_index = event.index
                touch_origin = event.position
                touch_start_in_world = true
                gesture_moved = false
                multi_touch = false
                stroke_active = false
                pointer_position = event.position
                preview_visible = editable_power()
            else:
                multi_touch = true
                stroke_active = false
                preview_visible = false
                previous_centroid = touch_centroid()
                last_pinch_distance = pinch_distance()
        else:
            if event.canceled:
                _cancel_world_gesture()
                ui_touches.erase(event.index)
                return
            if ui_touches.has(event.index):
                ui_touches.erase(event.index)
                return
            if not touches.has(event.index):
                return
            touches.erase(event.index)
            if touches.is_empty():
                var apply_tap := not gesture_moved and not multi_touch and inside_world(event.position)
                _reset_world_gesture()
                if apply_tap:
                    tapped(event.position)
            else:
                multi_touch = true
                stroke_active = false
                preview_visible = false
                previous_centroid = touch_centroid()
                last_pinch_distance = pinch_distance()
        queue_redraw()
    elif event is InputEventScreenDrag:
        if not touches.has(event.index):
            return
        var previous: Vector2 = touches[event.index]
        touches[event.index] = event.position
        if touches.size() == 2:
            multi_touch = true
            stroke_active = false
            preview_visible = false
            var centroid := touch_centroid()
            var distance := pinch_distance()
            pinch_camera(previous_centroid, centroid, last_pinch_distance, distance)
            previous_centroid = centroid
            last_pinch_distance = distance
        elif touches.size() == 1 and not multi_touch:
            if event.position.distance_to(touch_origin) >= 8.0:
                gesture_moved = true
            if gesture_moved:
                if editable_power():
                    _drag_brush(previous, event.position)
                else:
                    pan_camera(event.position - previous)
        queue_redraw()
    elif event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                mouse_world_pressed = inside_world(event.position)
                mouse_origin = event.position
                mouse_moved = false
                stroke_active = false
            else:
                var apply_tap := mouse_world_pressed and not mouse_moved and inside_world(event.position)
                mouse_world_pressed = false
                stroke_active = false
                if apply_tap:
                    tapped(event.position)
        elif event.pressed and inside_world(event.position):
            if event.button_index == MOUSE_BUTTON_WHEEL_UP:
                zoom_at_screen(event.position, 1.1)
            elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
                zoom_at_screen(event.position, 1.0 / 1.1)
        queue_redraw()
    elif event is InputEventMouseMotion:
        pointer_position = event.position
        preview_visible = editable_power() and inside_world(event.position)
        if mouse_world_pressed:
            if mouse_origin.distance_to(event.position) >= 8.0:
                mouse_moved = true
            if mouse_moved:
                if editable_power():
                    _drag_brush(event.position - event.relative, event.position)
                else:
                    pan_camera(event.relative)
        queue_redraw()

func _drag_brush(previous: Vector2, current: Vector2) -> void:
    if not inside_world(current):
        stroke_active = false
        preview_visible = false
        return
    var cell := screen_to_tile(current)
    if not stroke_active:
        stroke_last = screen_to_tile(previous) if inside_world(previous) else cell
    paint_segment(stroke_last, cell)
    stroke_last = cell
    stroke_active = true
    pointer_position = current
    preview_visible = true

func _reset_world_gesture() -> void:
    touches.clear()
    multi_touch = false
    gesture_moved = false
    primary_touch_index = -1
    touch_start_in_world = false
    stroke_active = false
    preview_visible = false
    last_pinch_distance = 0.0
    mouse_world_pressed = false

func _cancel_world_gesture() -> void:
    for id in touches:
        ui_touches[id] = true
    _reset_world_gesture()

func _notification(what: int) -> void:
    super._notification(what)
    if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
        _reset_world_gesture()
        ui_touches.clear()
    elif what == NOTIFICATION_WM_CLOSE_REQUEST:
        get_tree().quit()
    elif what == NOTIFICATION_WM_GO_BACK_REQUEST and hud != null:
        hud.handle_back()

func _refresh_hud() -> void:
    var alive := 0
    for person in world.citizens:
        if int(person.get("hp", 0)) > 0:
            alive += 1
    var date: Dictionary = world.calendar.date_at(world.tick)
    hud.update_stats(int(date["year"]), alive, paused, simulation_speed)
    if hud.world_details == "":
        _refresh_world_details()

func _refresh_world_details() -> void:
    var date: Dictionary = world.calendar.date_at(world.tick)
    var text := "Year %d · Day %d · %s\nWorld seed %d\n" % [int(date["year"]), int(date["day"]), str(date["season"]), world.seed]
    for nation in range(world.capitals.size()):
        var era: Dictionary = world.occupations.era_summary(world, nation)
        text += "\nCivilisation %d\n%s\n" % [nation + 1, str(era["label"])]
    hud.set_world_details(text)

func load_world() -> SandboxSimulation:
    var data := WorldFiles.read_snapshot(SAVE_PATH)
    return Simulation.from_snapshot(data) if not data.is_empty() else null

func save_world() -> void:
    if world != null:
        last_save_error = WorldFiles.write_world(world, SAVE_PATH)

func _manual_save() -> void:
    save_world()
    hud.notify("World saved" if last_save_error == OK else "Could not save world", last_save_error != OK)

func _reload_saved_world() -> void:
    var data := WorldFiles.read_snapshot(SAVE_PATH)
    var restored = Simulation.from_snapshot(data) if not data.is_empty() else null
    if restored == null:
        hud.notify("No valid saved world found", true)
        return
    _cancel_world_gesture()
    hud.close_modal()
    inspector.close()
    inspected_citizen_id = -1
    world_renderer.free()
    world = restored
    world_renderer = Renderer.new()
    world_renderer.setup(world)
    add_child(world_renderer)
    move_child(world_renderer, 0)
    world_renderer.refresh_units()
    camera_center = Vector2(world.WIDTH / 2.0, world.HEIGHT / 2.0)
    sim_accum = 0.0
    autosave_ticks = 0
    _refresh_world_details()
    _refresh_hud()
    _on_resized()
    hud.notify("Saved world restored")

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
            hud.open_inventory(inspector, world)
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
        world_renderer.refresh_units()
        world_renderer.add_power_effect(selected_power, cell)
        world_items.queue_redraw()
        queue_redraw()
