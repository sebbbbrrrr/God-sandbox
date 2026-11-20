extends SceneTree

const Director = preload("res://scripts/audio/world_audio_director.gd")

class FakeAudio:
    extends Node
    var events: Array[String] = []
    func emit_event(event_id: String, _p: Vector2, _s: bool = true) -> bool:
        events.append(event_id)
        return true

class FakeLiving:
    extends RefCounted
    var calls := 0
    func on_weather_event(audio: Node, kind: String, marker: String, point: Vector2) -> bool:
        calls += 1
        return audio.emit_event("weather." + kind, point, false)

class FakeWeather:
    extends RefCounted
    var rain_strength := 0.0
    var wind_strength := 0.0
    var phase_index := 0
    var name := "Calm"
    func description() -> String:
        return name

class FakeOccupations:
    extends RefCounted
    func role(id: String) -> Dictionary:
        if id == "iron_smith":
            return {"first_era": 4, "playable": true}
        if id == "software_engineer":
            return {"first_era": 9, "playable": true}
        if id == "woodcutter":
            return {"first_era": 1, "playable": true}
        return {}

class FakeConstruction:
    extends RefCounted
    var houses: Array[Dictionary] = [{"id": 1, "x": 5, "y": 5}]

class FakeCalendar:
    extends RefCounted
    func date_at(tick: int) -> Dictionary:
        return {"day": int(tick / 8) + 1, "tick_of_day": posmod(tick, 8)}

class FakeWorld:
    extends RefCounted
    var citizens: Array[Dictionary] = [
        {"id": 1, "hp": 100, "x": 5, "y": 5, "nation": 0, "occupation_id": "woodcutter"},
        {"id": 2, "hp": 100, "x": 6, "y": 5, "nation": 0, "occupation_id": "iron_smith"}
    ]
    var construction := FakeConstruction.new()
    var occupations := FakeOccupations.new()
    var calendar := FakeCalendar.new()
    var tick := 0

var failed := false

func _initialize() -> void:
    var director = Director.new()
    var audio = FakeAudio.new()
    var living = FakeLiving.new()
    var weather = FakeWeather.new()
    _check(Director.ERA_EVENTS.size() == 11, "eleven age soundscape identifiers")
    _check(Director.event_for_era(4) == "civilisation.classical", "classical mapping")
    _check(Director.event_for_era(11) == "civilisation.far_future", "future mapping")
    var world = FakeWorld.new()
    var camera := Vector2(5.0, 5.0)
    _check(int(Director.active_era(world, camera)["era"]) == 4,
        "only locally working occupied era counted")
    _check(director.update_civilisation(world, audio, camera, Vector2(480, 850), 20000)
        == "civilisation.classical", "real local technology drives ambience")
    _check(director.update_civilisation(world, audio, camera, Vector2(480, 850), 20001)
        == "", "ambient interval enforces throttling")
    world.citizens[1]["occupation_id"] = ""
    _check(int(Director.active_era(world, camera)["era"]) == 1,
        "no unsupported era unlock with absent workers")
    world.construction.houses.clear()
    _check(Director.active_era(world, camera).is_empty(),
        "no city ambience without an actual building")
    _check(director.update_weather(weather, 10, living, audio, Vector2(480, 850)).is_empty(),
        "calm state silent")
    weather.rain_strength = 0.6
    weather.wind_strength = 0.65
    weather.phase_index = 3
    weather.name = "Rain"
    _check(director.update_weather(weather, 11, living, audio, Vector2(480, 850)).size() == 2,
        "rain and wind onset are based on existing weather state")
    _check(director.update_weather(weather, 12, living, audio, Vector2(480, 850)).is_empty(),
        "sustained storm never creates duplicate onset")
    weather.phase_index = 5
    weather.name = "Storm"
    _check(director.update_weather(weather, 13, living, audio, Vector2(480, 850))
        == ["weather.thunder"], "storm entry makes one thunder onset")
    world.tick = 6
    _check(director.update_day_night(world, audio, Vector2(480, 850), 61000) == "ambient.night",
        "first evening has a grounded calendar cue")
    world.tick = 14
    _check(director.update_day_night(world, audio, Vector2(480, 850), 69000) == "",
        "accelerated calendar does not repeat night cue too often")
    if failed:
        push_error("AUDIO_WORLD_EXPANSION_TESTS_FAILED")
    else:
        print("AUDIO_WORLD_EXPANSION_TESTS_PASSED")
    quit(1 if failed else 0)

func _check(ok: bool, name: String) -> void:
    if ok:
        print("PASS: " + name)
    else:
        failed = true
        push_error("FAILED: " + name)
