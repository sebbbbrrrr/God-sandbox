extends RefCounted
## Camera-aware, era-sensitive soundscape derived ONLY from actual world state.
## Does not unlock eras, introduce weather, mutate the simulation or invent jobs.
const ERA_EVENTS := [
    "civilisation.early_stone", "civilisation.agricultural",
    "civilisation.bronze", "civilisation.classical", "civilisation.medieval",
    "civilisation.scientific", "civilisation.industrial",
    "civilisation.electrical", "civilisation.information",
    "civilisation.advanced", "civilisation.far_future"
]
const INTERVAL_MS := 11000
const MIN_RESIDENTS := 2
var _last_civilisation_ms := -20000
var _last_rain_state := false
var _last_windy_state := false
var _last_weather_phase := -1

func reset() -> void:
    _last_civilisation_ms = -20000
    _last_rain_state = false
    _last_windy_state = false
    _last_weather_phase = -1

static func event_for_era(era: int) -> String:
    return ERA_EVENTS[clampi(era - 1, 0, ERA_EVENTS.size() - 1)]

static func active_era(world, camera_cell: Vector2) -> Dictionary:
    # Residents and building sites are observed near the camera, not across nations.
    var residents := 0
    var count_by_era := {}
    var nearest_nation := -1
    var closest := 1000000.0
    for citizen in world.citizens:
        if int(citizen.get("hp", 0)) <= 0:
            continue
        var p := Vector2(float(citizen["x"]), float(citizen["y"]))
        var distance := p.distance_squared_to(camera_cell)
        if distance > 14.0 * 14.0:
            continue
        residents += 1
        if distance < closest:
            closest = distance
            nearest_nation = int(citizen.get("nation", 0))
        var role_id := str(citizen.get("occupation_id", ""))
        if role_id == "":
            continue
        var role: Dictionary = world.occupations.role(role_id)
        if role.is_empty() or not bool(role.get("playable", false)):
            continue
        var era := clampi(int(role.get("first_era", 1)), 1, 11)
        count_by_era[era] = int(count_by_era.get(era, 0)) + 1
    if residents < MIN_RESIDENTS:
        return {}
    var selected_era := 1
    # A later age needs actual audible local workers, not a calendar label.
    for era in count_by_era:
        if int(count_by_era[era]) > 0:
            selected_era = maxi(selected_era, int(era))
    var nearby_buildings := 0
    for house in world.construction.houses:
        var p := Vector2(float(house.get("x", -100)), float(house.get("y", -100)))
        if p.distance_squared_to(camera_cell) <= 15.0 * 15.0:
            nearby_buildings += 1
    if nearby_buildings <= 0:
        return {}
    return {"era": selected_era, "residents": residents,
        "buildings": nearby_buildings, "nation": nearest_nation}

func update_civilisation(world, audio, camera_cell: Vector2,
        viewport: Vector2, now_ms: int) -> String:
    if now_ms - _last_civilisation_ms < INTERVAL_MS:
        return ""
    _last_civilisation_ms = now_ms
    var evidence := active_era(world, camera_cell)
    if evidence.is_empty():
        return ""
    var sound := event_for_era(int(evidence["era"]))
    if audio.emit_event(sound, viewport * 0.5, false):
        return sound
    return ""

func update_weather(weather, world_tick: int, living,
        audio, viewport: Vector2) -> Array[String]:
    var result: Array[String] = []
    if weather == null:
        return result
    var rain := float(weather.rain_strength) >= 0.15
    var windy := float(weather.wind_strength) >= 0.40
    var phase := int(weather.phase_index)
    var center := viewport * 0.5
    # Transition/phase changes are sourced from the existing deterministic
    # visual weather controller. Wind and rain are short onset cues, not loops.
    if rain and not _last_rain_state:
        if living.on_weather_event(audio, "rain", "rain:" + str(world_tick), center):
            result.append("weather.rain")
    if windy and not _last_windy_state:
        if living.on_weather_event(audio, "wind", "wind:" + str(world_tick), center):
            result.append("weather.wind")
    if phase != _last_weather_phase and str(weather.description()) == "Storm":
        if living.on_weather_event(audio, "thunder", "storm:" + str(world_tick), center):
            result.append("weather.thunder")
    _last_rain_state = rain
    _last_windy_state = windy
    _last_weather_phase = phase
    return result
