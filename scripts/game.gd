extends Node2D

const Simulation = preload("res://scripts/simulation.gd")
const Brush = preload("res://scripts/terrain_brush.gd")
const Renderer = preload("res://scripts/pixel_world_renderer.gd")
const HUD = preload("res://scripts/sandbox_ui.gd")
const SAVE_PATH := "user://world.json"

var world: SandboxSimulation
var world_renderer: PixelWorldRenderer
var camera_center := Vector2(48, 64)
var zoom := 1.0
var paused := false
var simulation_speed := 1
var selected_power := -1
var brush_index := 1
const BRUSH_RADII := [0, 2, 4]
const BRUSH_LABELS := ["Small", "Medium", "Large"]
var pointer_position := Vector2.ZERO
var preview_visible := false
var stroke_active := false
var stroke_last := Vector2i.ZERO
var primary_touch_index := -1
var touch_start_in_world := false
var previous_centroid := Vector2.ZERO
var touches := {}
var gesture_moved := false
var multi_touch := false
var last_pinch_distance := 0.0
var sim_accum := 0.0
var render_accum := 0.0
var autosave_ticks := 0
var hud
var inspected_citizen_id := -1

func _ready() -> void:
    world = load_world()
    if world == null:
        world = SandboxSimulation.new(int(Time.get_unix_time_from_system()) % 2147483647)
    camera_center = Vector2(world.WIDTH / 2.0, world.HEIGHT / 2.0)
    world_renderer = Renderer.new()
    world_renderer.setup(world)
    add_child(world_renderer)
    world_renderer.refresh_units()
    hud = HUD.new()
    hud.name = "HUD"
    add_child(hud)
    hud.power_changed.connect(_set_power)
    hud.brush_changed.connect(_set_brush)
    hud.pause_pressed.connect(_toggle_pause)
    hud.speed_pressed.connect(_cycle_speed)
    hud.save_pressed.connect(save_world)
    hud.set_active_power(selected_power)
    hud.set_brush(brush_index)
    get_viewport().size_changed.connect(queue_redraw)
    queue_redraw()

func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
        save_world()

func _exit_tree() -> void:
    if world != null:
        save_world()

func save_world() -> void:
    if world == null:
        return
    var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify(world.snapshot()))
        file.flush()
        file.close()

func load_world() -> SandboxSimulation:
    if not FileAccess.file_exists(SAVE_PATH):
        return null
    var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if file == null:
        return null
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        return null
    return Simulation.from_snapshot(parsed)

func _process(delta: float) -> void:
    if not paused:
        sim_accum += minf(delta, 0.1) * simulation_speed
        var iterations := 0
        while sim_accum >= 0.1 and iterations < 5:
            world.step()
            sim_accum -= 0.1
            iterations += 1
            autosave_ticks += 1
        if iterations>0:
            world_renderer.refresh_units()
        if iterations == 5:
            sim_accum = minf(sim_accum, 0.5)
        if autosave_ticks >= 600:
            autosave_ticks = 0
            save_world()
    world_renderer.update_view(world_origin(),tile_size(),Rect2(Vector2.ZERO,get_viewport_rect().size))
    hud.update_stats(1 + world.tick / 3600, world.citizens.size(), paused, simulation_speed)
    _update_inspection()
    world_renderer.animate(delta)
    render_accum += delta
    if render_accum >= (1.0 / 30.0):
        render_accum = 0.0
        queue_redraw()

func tile_size() -> float:
    return 16.0 * zoom

func world_origin() -> Vector2:
    var sz := get_viewport_rect().size
    return (sz * 0.5 - camera_center * tile_size()).round()

func _draw() -> void:
    draw_brush_preview()

func _set_power(power: int) -> void:
    selected_power = power
    preview_visible = false
    stroke_active = false
    if power != -1:
        inspected_citizen_id = -1
    queue_redraw()

func _set_brush(index: int) -> void:
    brush_index = index
    queue_redraw()

func _toggle_pause() -> void:
    paused = not paused
    hud.update_stats(1 + world.tick / 3600, world.citizens.size(), paused, simulation_speed)

func _cycle_speed() -> void:
    simulation_speed = 2 if simulation_speed == 1 else (4 if simulation_speed == 2 else 1)
    hud.update_stats(1 + world.tick / 3600, world.citizens.size(), paused, simulation_speed)

func _update_inspection() -> void:
    if inspected_citizen_id < 0 or paused:
        return
    for citizen in world.citizens:
        if int(citizen["id"]) == inspected_citizen_id:
            hud.refresh_citizen(citizen)
            return
    inspected_citizen_id = -1
    hud.hide_inspector()

func editable_power() -> bool:
    return Brush.is_terrain_power(selected_power)

func inside_world(position: Vector2) -> bool:
    var size := get_viewport_rect().size
    return position.x >= 0 and position.x < size.x and position.y >= 0 and position.y < size.y and (hud == null or not hud.blocks_world_input(position))

func screen_to_tile(position: Vector2) -> Vector2i:
    return world_renderer.tile_at((position-world_origin())*32.0/tile_size())

func draw_brush_preview() -> void:
    if not editable_power() or not preview_visible or not inside_world(pointer_position) or touches.size() >= 2:
        return
    var cell := screen_to_tile(pointer_position)
    var radius: int = BRUSH_RADII[brush_index]
    var world_point := world_origin() + world_renderer.tile_center(cell) * tile_size() / 32.0
    var pixel_radius := (float(radius) + 0.5) * tile_size()
    var paint_color := Color("#a9e7ed") if selected_power == 5 else Color("#e8dc9f")
    draw_circle(world_point, pixel_radius, Color(paint_color, 0.22))
    draw_arc(world_point, pixel_radius, 0.0, TAU, 48, Color(paint_color, 0.85), 1.5)

func paint_segment(from_cell: Vector2i, to_cell: Vector2i) -> void:
    if not editable_power():
        return
    Brush.paint_segment(world, selected_power, from_cell, to_cell, BRUSH_RADII[brush_index])
    queue_redraw()

func pan_camera(delta: Vector2) -> void:
    camera_center -= delta / tile_size()
    camera_center.x = clampf(camera_center.x, 0.0, float(world.WIDTH))
    camera_center.y = clampf(camera_center.y, 0.0, float(world.HEIGHT))

func pinch_distance() -> float:
    if touches.size() < 2:
        return 0.0
    var points := touches.values()
    return (points[0] as Vector2).distance_to(points[1] as Vector2)

func touch_centroid() -> Vector2:
    if touches.size() < 2:
        return Vector2.ZERO
    var points := touches.values()
    return ((points[0] as Vector2) + (points[1] as Vector2)) * 0.5

func _input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.pressed:
            touches[event.index] = event.position
            if touches.size() == 1:
                primary_touch_index = event.index
                touch_start_in_world = inside_world(event.position)
                gesture_moved = false
                multi_touch = false
                stroke_active = false
                pointer_position = event.position
                preview_visible = touch_start_in_world and editable_power()
            elif touches.size() == 2:
                multi_touch = true
                stroke_active = false
                preview_visible = false
                last_pinch_distance = pinch_distance()
                previous_centroid = touch_centroid()
            else:
                multi_touch = true
                stroke_active = false
                preview_visible = false
        else:
            if touches.has(event.index):
                touches.erase(event.index)
            if touches.is_empty():
                if not gesture_moved and not multi_touch:
                    if touch_start_in_world:
                        tapped(event.position)
                stroke_active = false
                multi_touch = false
                last_pinch_distance = 0.0
                preview_visible = false
                primary_touch_index = -1
            else:
                # Do not resume painting when a second finger lifts.
                multi_touch = true
                stroke_active = false
                preview_visible = false
                if touches.size() == 1:
                    primary_touch_index = int(touches.keys()[0])
        queue_redraw()
    elif event is InputEventScreenDrag:
        if not touches.has(event.index):
            return
        var previous: Vector2 = touches[event.index]
        touches[event.index] = event.position
        if touches.size() >= 2:
            multi_touch = true
            stroke_active = false
            preview_visible = false
            if touches.size() == 2:
                var centroid := touch_centroid()
                var distance := pinch_distance()
                pan_camera(centroid - previous_centroid)
                if last_pinch_distance > 1.0 and distance > 1.0:
                    var world_under_fingers := (centroid - world_origin()) / tile_size()
                    zoom = clampf(zoom * distance / last_pinch_distance, 0.5, 4.0)
                    var screen_center := get_viewport_rect().size * 0.5
                    camera_center = world_under_fingers - (centroid - screen_center) / tile_size()
                    camera_center.x = clampf(camera_center.x, 0.0, float(world.WIDTH))
                    camera_center.y = clampf(camera_center.y, 0.0, float(world.HEIGHT))
                last_pinch_distance = distance
                previous_centroid = centroid
        elif not multi_touch and event.index == primary_touch_index:
            if previous.distance_to(event.position) > 0.5:
                gesture_moved = true
            if touch_start_in_world:
                if editable_power():
                    if not stroke_active:
                        stroke_last = screen_to_tile(previous)
                        stroke_active = true
                    if inside_world(event.position):
                        var current := screen_to_tile(event.position)
                        paint_segment(stroke_last, current)
                        stroke_last = current
                    pointer_position = event.position
                    preview_visible = inside_world(event.position)
                else:
                    pan_camera(event.position - previous)
        queue_redraw()
    elif event is InputEventMouseMotion:
        if touches.is_empty():
            pointer_position = event.position
            preview_visible = editable_power() and inside_world(event.position)
            if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and editable_power() and inside_world(event.position):
                if stroke_active:
                    var cell := screen_to_tile(event.position)
                    paint_segment(stroke_last, cell)
                    stroke_last = cell
            elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not editable_power() and touch_start_in_world:
                if event.relative.length_squared() > 0.5:
                    gesture_moved = true
                pan_camera(event.relative)
            queue_redraw()
    elif event is InputEventMouseButton:
        if not touches.is_empty():
            return
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                stroke_active = editable_power() and inside_world(event.position)
                touch_start_in_world = inside_world(event.position)
                gesture_moved = false
                if stroke_active:
                    stroke_last = screen_to_tile(event.position)
                    paint_segment(stroke_last, stroke_last)
            else:
                if not stroke_active and touch_start_in_world and not gesture_moved:
                    tapped(event.position)
                stroke_active = false
                touch_start_in_world = false
        elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
            zoom = minf(zoom * 1.1, 4.0)
        elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            zoom = maxf(zoom / 1.1, 0.5)
        queue_redraw()

func tapped(position: Vector2) -> void:
    if not inside_world(position):
        return
    var cell := screen_to_tile(position)
    if selected_power == -1:
        inspected_citizen_id = -1
        for person in world.citizens:
            if int(person["x"]) == cell.x and int(person["y"]) == cell.y and int(person["hp"]) > 0:
                inspected_citizen_id = int(person["id"])
                hud.show_citizen(person)
                return
        var terrain_names := ["Ocean", "Beach", "Meadow", "Forest", "Mountain", "Ash", "Settlement"]
        var terrain: int = world.at(cell.x, cell.y)
        hud.show_terrain(cell, terrain_names[clampi(terrain, 0, terrain_names.size() - 1)], world.height_at(cell.x, cell.y))
    elif editable_power():
        paint_segment(cell, cell)
    else:
        if world.apply_power(selected_power, cell.x, cell.y):
            world_renderer.refresh_units()
            world_renderer.add_power_effect(selected_power, cell)
            queue_redraw()
