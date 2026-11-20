extends RefCounted
## Read-only living-world sound observer. No RNG or simulation state is modified.
## Only completed position changes produce footsteps; work audio uses explicit job events.
const SURFACE_EVENTS := {
    1: "citizen.step.sand",
    2: "citizen.step.grass",
    3: "citizen.step.grass",
    4: "citizen.step.stone",
    5: "citizen.step.stone",
    6: "citizen.step.wood"
}
const WORK_EVENTS := {
    "chop": "work.chop", "fell": "work.chop", "mine": "work.mine",
    "quarry": "work.mine", "saw": "work.saw", "dig": "work.dig",
    "excavate": "work.dig", "deliver": "work.deliver", "unload": "work.deliver",
    "build": "work.build", "hammer": "work.build", "masonry": "work.build",
    "roof": "work.build", "repair": "work.repair", "demolish": "work.demolish"
}
const BIOME_EVENTS := {
    0: "ambient.ocean", 1: "ambient.ocean", 2: "ambient.wilderness",
    3: "ambient.forest", 4: "ambient.wilderness", 5: "ambient.wilderness",
    6: "ambient.settlement"
}
const AMBIENCE_INTERVAL_MS := 7500
const MAX_FOOTSTEPS_PER_STEP := 3

var _previous_positions := {}
var _previous_tick := -1
var _last_ambience_ms := -100000
var _last_work_marker := {}
var _last_weather_marker := ""

static func surface_event(terrain_type: int) -> String:
    return str(SURFACE_EVENTS.get(terrain_type, "citizen.step.grass"))

static func work_event(action: String) -> String:
    return str(WORK_EVENTS.get(action.to_lower(), ""))

static func biome_event(terrain_type: int) -> String:
    return str(BIOME_EVENTS.get(terrain_type, "ambient.wilderness"))

static func world_to_screen(cell: Vector2i, origin: Vector2, cell_pixels: float) -> Vector2:
    return origin + (Vector2(cell) + Vector2(0.5, 0.5)) * cell_pixels

static func screen_visible(point: Vector2, size: Vector2, panel_height: float) -> bool:
    return point.x >= 0.0 and point.x <= size.x and point.y >= 50.0 and point.y <= size.y - panel_height

func reset() -> void:
    _previous_positions.clear()
    _previous_tick = -1
    _last_ambience_ms = -100000
    _last_work_marker.clear()
    _last_weather_marker = ""

func observe_movement(world, audio, origin: Vector2, cell_pixels: float,
        screen_size: Vector2, panel_height: float, accelerated: bool = false) -> int:
    if int(world.tick) == _previous_tick:
        return 0
    if int(world.tick) < _previous_tick:
        reset()
    _previous_tick = int(world.tick)
    var heard := 0
    var next_positions := {}
    # Only actual moved citizens count. Snapshot scanning is read-only, and events
    # are capped even if many world.step calls occur during one render frame.
    for citizen in world.citizens:
        if int(citizen.get("hp", 0)) <= 0:
            continue
        var id := int(citizen["id"])
        var cell := Vector2i(int(citizen["x"]), int(citizen["y"]))
        next_positions[id] = cell
        if heard >= (1 if accelerated else MAX_FOOTSTEPS_PER_STEP):
            continue
        if not _previous_positions.has(id) or _previous_positions[id] == cell:
            continue
        var point := world_to_screen(cell, origin, cell_pixels)
        if not screen_visible(point, screen_size, panel_height):
            continue
        if audio.emit_event(surface_event(int(world.at(cell.x, cell.y))), point, true):
            heard += 1
    _previous_positions = next_positions
    return heard

func observe_ambience(world, audio, center: Vector2, origin: Vector2,
        cell_pixels: float, screen_size: Vector2, panel_height: float,
        now_ms: int) -> String:
    if now_ms - _last_ambience_ms < AMBIENCE_INTERVAL_MS:
        return ""
    if cell_pixels <= 0.0:
        return ""
    # Sample the audible camera neighbourhood (not entire world).
    var counts := {}
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            var cx := int(floor(center.x)) + dx * 2
            var cy := int(floor(center.y)) + dy * 2
            if cx < 0 or cy < 0 or cx >= int(world.WIDTH) or cy >= int(world.HEIGHT):
                continue
            var terrain_type := int(world.at(cx, cy))
            counts[terrain_type] = int(counts.get(terrain_type, 0)) + 1
    if counts.is_empty():
        return ""
    var selected_type := -1
    var best := -1
    for terrain_type in counts:
        if int(counts[terrain_type]) > best:
            selected_type = int(terrain_type)
            best = int(counts[terrain_type])
    var event_id := biome_event(selected_type)
    # A single soft texture per interval rather than an ambient player per tile.
    var point := Vector2(screen_size.x * 0.5, (screen_size.y - panel_height) * 0.5)
    if audio.emit_event(event_id, point, false):
        _last_ambience_ms = now_ms
        return event_id
    return ""

func on_work_marker(audio, action: String, worker_id: int, marker_id: int,
        screen_position: Vector2) -> bool:
    # The calling construction animation must provide its actual hit/action marker.
    # Distinct worker/marker keys stop replaying a gesture across render frames.
    var event_id := work_event(action)
    if event_id == "" or worker_id <= 0:
        return false
    if int(_last_work_marker.get(worker_id, -1)) >= marker_id:
        return false
    _last_work_marker[worker_id] = marker_id
    if _last_work_marker.size() > 256:
        _last_work_marker.clear()
        _last_work_marker[worker_id] = marker_id
    return audio.emit_event(event_id, screen_position, true)

func on_weather_event(audio, kind: String, event_marker: String,
        screen_position: Vector2) -> bool:
    # Use weather simulation transitions/actual thunder strike markers, not random audio.
    var event_id := "weather." + kind.to_lower()
    if not ["weather.rain", "weather.wind", "weather.thunder"].has(event_id):
        return false
    if event_marker == "" or event_marker == _last_weather_marker:
        return false
    _last_weather_marker = event_marker
    return audio.emit_event(event_id, screen_position, true)
