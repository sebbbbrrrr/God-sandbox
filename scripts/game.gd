extends Node2D

const Simulation = preload("res://scripts/simulation.gd")
const Brush = preload("res://scripts/terrain_brush.gd")
const Inspector = preload("res://scripts/ui/item_inspector.gd")
const ItemArt = preload("res://scripts/ui/item_pixel_art.gd")
const ItemOverlay = preload("res://scripts/ui/item_overlay.gd")
const SAVE_PATH := "user://world.json"
const COLORS := [
    Color("#1e617d"), Color("#dcc490"), Color("#77a45e"),
    Color("#376f54"), Color("#808783"), Color("#5e5249"), Color("#bf9367")
]
const NATION_COLORS := [Color("#f3c16c"), Color("#f08e93")]
const POWER_NAMES := ["Raise", "Fire", "Forest", "Bless", "Spawn", "Ocean"]
const POWER_CATEGORIES := [
    [0, 2, 4], [0, 5], [4], [3], [4], [2], [1, 5], [3]
]
const CATEGORY_NAMES := ["Main", "World", "Units", "Life", "Beasts", "Nature", "Chaos", "Other"]

var world: SandboxSimulation
var camera_center := Vector2(48, 64)
var zoom := 1.0
var paused := false
var simulation_speed := 1
var selected_category := 0
var selected_power := 0
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
var font: Font
var inspector = Inspector.new()
var inspector_touch_id := -1
var inspector_touch_y := 0.0
var inspector_touch_moved := false
var inspector_scroll_pixels := 0.0

func _ready() -> void:
    world = load_world()
    if world == null:
        world = SandboxSimulation.new(int(Time.get_unix_time_from_system()) % 2147483647)
    camera_center = Vector2(world.WIDTH / 2.0, world.HEIGHT / 2.0)
    font = ThemeDB.fallback_font
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
        if iterations == 5:
            sim_accum = minf(sim_accum, 0.5)
        if autosave_ticks >= 600:
            autosave_ticks = 0
            save_world()
    render_accum += delta
    if render_accum >= (1.0 / 30.0):
        render_accum = 0.0
        queue_redraw()

# VisibleRect may be zero during headless SceneTree initialization. The
# configured game canvas is the safe fallback; mobile always uses its real size.
func ui_size() -> Vector2:
    var actual: Vector2 = get_viewport_rect().size
    if actual.x < 1.0 or actual.y < 1.0:
        return Vector2(float(ProjectSettings.get_setting("display/window/size/viewport_width", 480)),
            float(ProjectSettings.get_setting("display/window/size/viewport_height", 850)))
    return actual

func toolbar_height() -> float:
    return 188.0

func tile_size() -> float:
    return 16.0 * zoom

func world_origin() -> Vector2:
    var sz := ui_size()
    return Vector2(sz.x * 0.5, (sz.y - toolbar_height()) * 0.5) - camera_center * tile_size()

func _draw() -> void:
    var sz := ui_size()
    draw_rect(Rect2(Vector2.ZERO, sz), Color("#123d59"))
    draw_terrain(sz)
    draw_world_items(sz)
    draw_people(sz)
    draw_brush_preview(sz)
    draw_interface(sz)
    ItemOverlay.draw_panel(self, font, world, inspector, sz, toolbar_height())

func draw_terrain(sz: Vector2) -> void:
    var ts := tile_size()
    var origin := world_origin()
    var min_x := maxi(0, int(floor(-origin.x / ts)) - 1)
    var max_x := mini(world.WIDTH - 1, int(ceil((sz.x - origin.x) / ts)) + 1)
    var min_y := maxi(0, int(floor((50.0 - origin.y) / ts)) - 1)
    var max_y := mini(world.HEIGHT - 1, int(ceil((sz.y - toolbar_height() - origin.y) / ts)) + 1)
    for y in range(min_y, max_y + 1):
        for x in range(min_x, max_x + 1):
            var type: int = world.at(x, y)
            var p := origin + Vector2(x, y) * ts
            if p.y + ts < 50.0 or p.y > sz.y - toolbar_height():
                continue
            draw_rect(Rect2(p, Vector2(ts + 0.5, ts + 0.5)), COLORS[type])
            if ts < 8.0:
                continue
            var detail := posmod(x * 73 + y * 119 + world.seed, 11)
            match type:
                world.OCEAN:
                    if detail < 2:
                        draw_line(p + Vector2(ts * 0.12, ts * 0.57),
                            p + Vector2(ts * 0.65, ts * 0.57), Color("#5e9eac"), maxf(1.0, ts * 0.06))
                world.MEADOW:
                    if detail < 3:
                        draw_line(p + Vector2(ts * 0.4, ts * 0.73),
                            p + Vector2(ts * 0.33, ts * 0.35), Color("#c1c97d"), maxf(1.0, ts * 0.08))
                world.FOREST:
                    draw_circle(p + Vector2(ts * 0.51, ts * 0.55), ts * 0.28, Color("#20563e"))
                    draw_circle(p + Vector2(ts * 0.40, ts * 0.40), ts * 0.22, Color("#4c9960"))
                world.MOUNTAIN:
                    draw_colored_polygon(PackedVector2Array([
                        p + Vector2(ts * 0.08, ts * 0.88),
                        p + Vector2(ts * 0.57, ts * 0.12),
                        p + Vector2(ts * 0.95, ts * 0.88)
                    ]), Color("#c4c7b6"))
                world.TOWN:
                    draw_rect(Rect2(p + Vector2(ts * 0.2, ts * 0.38), Vector2(ts * 0.6, ts * 0.45)), Color("#67503e"))
                    draw_rect(Rect2(p + Vector2(ts * 0.12, ts * 0.25), Vector2(ts * 0.75, ts * 0.22)), Color("#e5b678"))
                world.ASH:
                    draw_circle(p + Vector2(ts * 0.5, ts * 0.5), ts * 0.13, Color("#ee8147"))

# D4 decorations are only drawn for visible cells. Existing terrain art is
# untouched so the separate high-definition renderer can integrate later.
func draw_world_items(sz: Vector2) -> void:
    var ts := tile_size()
    if ts < 7.0:
        return
    var origin := world_origin()
    var world_bottom := sz.y - toolbar_height()
    for building in world.construction.houses:
        if str(building.get("type", "home")) != "tool_area":
            continue
        var pos := origin + Vector2(float(building["x"]), float(building["y"])) * ts
        if pos.x < -ts or pos.x > sz.x or pos.y < 50.0 - ts or pos.y > world_bottom:
            continue
        ItemArt.draw_workshop(self, Rect2(pos, Vector2(ts, ts)), world.tick)
    for holder in world.inventory.balances:
        var key := str(holder)
        if not key.begins_with("ground:"):
            continue
        var store: Dictionary = world.inventory.balances[holder]
        if store.is_empty():
            continue
        var idx := int(key.get_slice(":", 1))
        var x := idx % world.WIDTH
        var y := int(idx / world.WIDTH)
        var pos := origin + Vector2(float(x), float(y)) * ts
        if pos.x < -ts or pos.x > sz.x or pos.y < 50.0 - ts or pos.y > world_bottom:
            continue
        var kinds: Array = store.keys()
        kinds.sort()
        var visible_id := ""
        var total := 0
        for item_id in kinds:
            var qty := int(store[item_id])
            if qty <= 0:
                continue
            total += qty
            if visible_id == "":
                visible_id = str(item_id)
        if visible_id != "":
            ItemArt.draw_ground(self, Rect2(pos, Vector2(ts, ts)),
                visible_id, total, inspector.visible and inspector.holder_id == key)

func draw_people(sz: Vector2) -> void:
    var ts := tile_size()
    var origin := world_origin()
    var radius := clampf(ts * 0.24, 1.5, 5.0)
    for citizen in world.citizens:
        if citizen["hp"] <= 0:
            continue
        var p := origin + (Vector2(float(citizen["x"]), float(citizen["y"])) + Vector2(0.5, 0.5)) * ts
        if p.x < -ts or p.x > sz.x + ts or p.y < 50.0 or p.y > sz.y - toolbar_height():
            continue
        draw_circle(p, radius, NATION_COLORS[citizen["nation"]])
        if ts >= 13.0:
            var serial := str(world.toolmaking.equipped.get(str(citizen["id"]), ""))
            if serial != "" and world.toolmaking.instances.has(serial):
                var instance: Dictionary = world.toolmaking.instances[serial]
                ItemArt.draw_item(self, str(instance["item_id"]),
                    p + Vector2(radius * 1.65, -radius * 0.55), ts / 19.0)
                if int(instance["condition"]) * 4 < int(instance["max_condition"]):
                    draw_rect(Rect2(p + Vector2(radius * 1.05, radius * 0.65),
                        Vector2(maxf(2.0, ts * 0.16), 2.0)), Color("#df816e"))
        if ts > 15.0:
            draw_arc(p, radius, 0.0, TAU, 12, Color("#263a3d"), 0.8)

func label(text_value: String, at_pos: Vector2, size: int = 13, color: Color = Color.WHITE) -> void:
    draw_string(font, at_pos, text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func editable_power() -> bool:
    return Brush.is_terrain_power(selected_power)

func inside_world(position: Vector2) -> bool:
    var size := ui_size()
    return position.x >= 0 and position.x < size.x and position.y >= 50.0 and position.y < size.y - toolbar_height()

func screen_to_tile(position: Vector2) -> Vector2i:
    var value := (position - world_origin()) / tile_size()
    return Vector2i(floori(value.x), floori(value.y))

func draw_brush_preview(sz: Vector2) -> void:
    if not editable_power() or not preview_visible or not inside_world(pointer_position) or touches.size() >= 2:
        return
    var cell := screen_to_tile(pointer_position)
    var radius: int = BRUSH_RADII[brush_index]
    var world_point := world_origin() + (Vector2(cell) + Vector2(0.5, 0.5)) * tile_size()
    var pixel_radius := (float(radius) + 0.5) * tile_size()
    var paint_color := Color("#a9e7ed") if selected_power == 5 else Color("#e8dc9f")
    draw_circle(world_point, pixel_radius, Color(paint_color, 0.22))
    draw_arc(world_point, pixel_radius, 0.0, TAU, 48, Color(paint_color, 0.85), 1.5)

func draw_interface(sz: Vector2) -> void:
    draw_rect(Rect2(0, 0, sz.x, 50), Color("#203432"))
    label("GOD SANDBOX", Vector2(12, 22), 17, Color("#f5ecd8"))
    label("Year %d  •  %d souls" % [1 + world.tick / 3600, world.citizens.size()], Vector2(12, 40), 11, Color("#c2cebd"))
    draw_rect(Rect2(sz.x - 169, 8, 53, 34), Color("#d1ac72") if selected_power == -1 else Color("#54705d"))
    draw_rect(Rect2(sz.x - 111, 8, 48, 34), Color("#54705d"))
    draw_rect(Rect2(sz.x - 58, 8, 50, 34), Color("#54705d"))
    label("HAND", Vector2(sz.x - 162, 30), 11, Color("#263c31") if selected_power == -1 else Color.WHITE)
    label("PLAY" if paused else "PAUSE", Vector2(sz.x - 106, 30), 11)
    label("%dx" % simulation_speed, Vector2(sz.x - 43, 30), 14)
    var top := sz.y - toolbar_height()
    draw_rect(Rect2(0, top, sz.x, toolbar_height()), Color("#203432"))
    var mode_name: String = "HAND  /  Navigate & inspect" if selected_power == -1 else "POWER  /  " + str(POWER_NAMES[selected_power])
    label(mode_name, Vector2(12, top + 21), 13, Color("#f4e5c5"))
    var cw := (sz.x - 12.0) / float(CATEGORY_NAMES.size())
    for i in range(CATEGORY_NAMES.size()):
        var x := 6.0 + i * cw
        draw_rect(Rect2(x, top + 30, cw - 2, 37),
            Color("#718d63") if i == selected_category and selected_power != -1 else Color("#394e47"))
        label(CATEGORY_NAMES[i], Vector2(x + 4, top + 52), 9)
    var active: Array = POWER_CATEGORIES[selected_category]
    var pw := (sz.x - 12.0) / float(active.size())
    for i in range(active.size()):
        var power: int = active[i]
        var x := 6.0 + pw * i
        draw_rect(Rect2(x, top + 78, pw - 4, 40),
            Color("#d1ac72") if power == selected_power else Color("#52715d"))
        label(POWER_NAMES[power], Vector2(x + 9, top + 103), 12,
            Color("#27382f") if power == selected_power else Color.WHITE)
    var enabled := editable_power()
    var brush_width := (sz.x - 12.0) / 3.0
    for i in range(3):
        var x := 6.0 + brush_width * i
        draw_rect(Rect2(x, top + 127, brush_width - 4, 33),
            Color("#d1ac72") if enabled and brush_index == i else Color("#394e47"))
        label(BRUSH_LABELS[i], Vector2(x + 12, top + 149), 11,
            Color("#27382f") if enabled and brush_index == i else Color("#cbd4ca"))
    label("1 finger: paint" if enabled else "1 finger: move / tap to use",
        Vector2(12, sz.y - 11), 10, Color("#bfcdb9"))
    label("2 fingers: pan + zoom", Vector2(sz.x * 0.54, sz.y - 11), 10, Color("#bfcdb9"))
    ItemOverlay.draw_chip(self, font, sz, toolbar_height(), inspector.visible)

func paint_segment(from_cell: Vector2i, to_cell: Vector2i) -> void:
    if not editable_power():
        return
    Brush.paint_segment(world, selected_power, from_cell, to_cell, BRUSH_RADII[brush_index])
    queue_redraw()

func pan_camera(delta: Vector2) -> void:
    camera_center -= delta / tile_size()
    camera_center.x = clampf(camera_center.x, 0.0, float(world.WIDTH))
    camera_center.y = clampf(camera_center.y, 0.0, float(world.HEIGHT))

# Keep a consistent camera coordinate system for taps, wheel zoom and
# two-finger pinch. Unified pixel UI overrides this with the full viewport
# centre because its floating HUD does not shorten the world canvas.
func camera_view_center() -> Vector2:
    var size: Vector2 = ui_size()
    return Vector2(size.x * 0.5, (size.y - toolbar_height()) * 0.5)

func zoom_at_screen(screen_point: Vector2, factor: float) -> void:
    if not is_finite(factor) or factor <= 0.0:
        return
    var old_size: float = tile_size()
    var stable_world: Vector2 = camera_center + (screen_point - camera_view_center()) / old_size
    zoom = clampf(zoom * factor, 0.5, 4.0)
    camera_center = stable_world - (screen_point - camera_view_center()) / tile_size()
    camera_center.x = clampf(camera_center.x, 0.0, float(world.WIDTH))
    camera_center.y = clampf(camera_center.y, 0.0, float(world.HEIGHT))

# The world coordinate beneath the OLD centroid must appear beneath the
# NEW centroid after the gesture. Do not pan first and then recompute the
# anchor: that double-applies centroid movement and causes oceanward drift.
func pinch_camera(previous: Vector2, current: Vector2,
        old_distance: float, new_distance: float) -> void:
    var old_size: float = tile_size()
    var stable_world: Vector2 = camera_center + (previous - camera_view_center()) / old_size
    if old_distance > 1.0 and new_distance > 1.0:
        zoom = clampf(zoom * new_distance / old_distance, 0.5, 4.0)
    camera_center = stable_world - (current - camera_view_center()) / tile_size()
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

# The modal consumes its own touch stream; swipes scroll item rows rather
# than dragging the world underneath or activating an equipped god power.
func inspector_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.pressed:
            if inspector_touch_id == -1:
                inspector_touch_id = event.index
                inspector_touch_y = event.position.y
                inspector_touch_moved = false
                inspector_scroll_pixels = 0.0
            else:
                inspector_touch_moved = true
        elif event.index == inspector_touch_id:
            if not inspector_touch_moved:
                inspector.tap(world, event.position, ui_size(), toolbar_height())
            inspector_touch_id = -1
            inspector_scroll_pixels = 0.0
        queue_redraw()
    elif event is InputEventScreenDrag:
        if event.index == inspector_touch_id:
            var dy: float = event.position.y - inspector_touch_y
            inspector_touch_y = event.position.y
            inspector_scroll_pixels += dy
            if absf(inspector_scroll_pixels) > 8.0:
                inspector_touch_moved = true
            if absf(inspector_scroll_pixels) >= inspector.ROW_HEIGHT:
                var steps := int(floor(absf(inspector_scroll_pixels) / inspector.ROW_HEIGHT))
                inspector.scroll_by(world, -steps if inspector_scroll_pixels > 0.0 else steps,
                    ui_size(), toolbar_height())
                inspector_scroll_pixels = fmod(inspector_scroll_pixels, inspector.ROW_HEIGHT)
            queue_redraw()
    elif event is InputEventMouseButton:
        if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
            inspector.tap(world, event.position, ui_size(), toolbar_height())
        elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
            inspector.scroll_by(world, -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1,
                ui_size(), toolbar_height())
        queue_redraw()
    elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        inspector.close()
        queue_redraw()

# In hand mode a tap inspects real entities rather than merely printing to
# the development console. Repeating an occupied tile cycles its citizens.
func inspect_cell(cell: Vector2i) -> bool:
    var idx := world.index_of(cell.x, cell.y)
    if idx < 0:
        return false
    var ground_id := "ground:" + str(idx)
    var ground: Dictionary = world.inventory.balances.get(ground_id, {})
    if not ground.is_empty() and inspector.focus_citizen_id > 0:
        return inspector.open_for(world, ground_id, "ground")
    var occupants: Array[int] = []
    for citizen in world.citizens:
        if int(citizen["hp"]) > 0 and int(citizen["x"]) == cell.x and int(citizen["y"]) == cell.y:
            occupants.append(int(citizen["id"]))
    if not occupants.is_empty():
        var idx_to_use := 0
        var last: int = occupants.find(inspector.focus_citizen_id)
        if last >= 0:
            idx_to_use = (last + 1) % occupants.size()
        return inspector.open_for(world, "citizen:" + str(occupants[idx_to_use]), "citizen")
    for building in world.construction.houses:
        if str(building.get("type", "home")) == "tool_area" and \
                int(building["x"]) == cell.x and int(building["y"]) == cell.y:
            return inspector.open_for(world,
                "settlement:" + str(building["nation"]), "workshop")
    if not ground.is_empty():
        return inspector.open_for(world, ground_id, "ground")
    for nation in range(2):
        if world.capitals[nation] == cell:
            return inspector.open_for(world, "settlement:" + str(nation), "settlement")
    return false

func open_items_shortcut() -> void:
    selected_power = -1
    var person: Dictionary = world.inventory._person(world, inspector.focus_citizen_id)
    if not person.is_empty() and int(person.get("hp", 0)) > 0:
        inspector.open_for(world, "citizen:" + str(person["id"]), "citizen")
        return
    var best := -1
    var distance := INF
    for nation in range(2):
        var capital: Vector2i = world.capitals[nation]
        if capital.x < 0:
            continue
        var d := Vector2(capital).distance_squared_to(camera_center)
        if d < distance:
            distance = d
            best = nation
    if best >= 0:
        inspector.open_for(world, "settlement:" + str(best), "settlement")

func _input(event: InputEvent) -> void:
    if inspector.visible:
        inspector_input(event)
        return
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
                pinch_camera(previous_centroid, centroid, last_pinch_distance, distance)
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
                pan_camera(event.relative)
            queue_redraw()
    elif event is InputEventMouseButton:
        if not touches.is_empty():
            return
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                stroke_active = editable_power() and inside_world(event.position)
                touch_start_in_world = inside_world(event.position)
                if stroke_active:
                    stroke_last = screen_to_tile(event.position)
                    paint_segment(stroke_last, stroke_last)
            else:
                if not stroke_active:
                    tapped(event.position)
                stroke_active = false
        elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
            zoom_at_screen(event.position, 1.1)
        elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            zoom_at_screen(event.position, 1.0 / 1.1)
        queue_redraw()

func tapped(position: Vector2) -> void:
    var sz := ui_size()
    if position.y < 50:
        if position.x > sz.x - 60:
            simulation_speed = 2 if simulation_speed == 1 else (4 if simulation_speed == 2 else 1)
        elif position.x > sz.x - 114:
            paused = not paused
        elif position.x > sz.x - 172:
            selected_power = -1
        return
    var top := sz.y - toolbar_height()
    if position.y >= top:
        if position.x >= sz.x - 111.0 and position.x <= sz.x - 12.0 and \
                position.y >= top + 3.0 and position.y <= top + 27.0:
            open_items_shortcut()
            queue_redraw()
            return
        var row := position.y - top
        if row >= 30 and row <= 67:
            var cw := (sz.x - 12.0) / float(CATEGORY_NAMES.size())
            selected_category = clampi(int((position.x - 6.0) / cw), 0, CATEGORY_NAMES.size() - 1)
            selected_power = POWER_CATEGORIES[selected_category][0]
        elif row >= 78 and row <= 118:
            var active: Array = POWER_CATEGORIES[selected_category]
            var pw := (sz.x - 12.0) / float(active.size())
            var i := clampi(int((position.x - 6.0) / pw), 0, active.size() - 1)
            selected_power = active[i]
        elif row >= 127 and row <= 160 and editable_power():
            var brush_width := (sz.x - 12.0) / 3.0
            brush_index = clampi(int((position.x - 6.0) / brush_width), 0, 2)
        queue_redraw()
        return
    if not inside_world(position):
        return
    var cell := screen_to_tile(position)
    if selected_power == -1:
        if inspect_cell(cell):
            queue_redraw()
    elif editable_power():
        paint_segment(cell, cell)
    else:
        world.apply_power(selected_power, cell.x, cell.y)
        queue_redraw()
