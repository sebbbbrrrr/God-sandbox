extends SceneTree

const Living = preload("res://scripts/audio/living_world_audio.gd")
const Simulation = preload("res://scripts/simulation.gd")
var failed := false

class FakeAudio:
    extends Node
    var events: Array[String] = []
    func emit_event(event_id: String, _point: Vector2, _spatial: bool = true) -> bool:
        events.append(event_id)
        return true

func _initialize() -> void:
    var observer = Living.new()
    var audio = FakeAudio.new()
    _check(Living.surface_event(Simulation.BEACH) == "citizen.step.sand", "sand material")
    _check(Living.surface_event(Simulation.TOWN) == "citizen.step.wood", "built path material")
    _check(Living.work_event("hammer") == "work.build", "hammer action maps to real job marker")
    _check(Living.work_event("invalid") == "", "unknown job not fabricated")
    _check(Living.biome_event(Simulation.FOREST) == "ambient.forest", "forest ambient")
    _check(not Living.screen_visible(Vector2(-80, 30), Vector2(480, 850), 188.0),
        "offscreen coordinates rejected")
    var world = Simulation.new(789)
    var before := world.snapshot()
    var origin := Vector2(0, 0)
    # Start tracking then move an existing citizen in-place solely in this test.
    var first = world.citizens[0]
    var initial_cell := Vector2i(int(first["x"]), int(first["y"]))
    observer.observe_movement(world, audio, origin, 16.0, Vector2(1000, 1000), 0)
    var destination := Vector2i(-1, -1)
    for dx in range(-1, 2):
        for dy in range(-1, 2):
            var candidate := initial_cell + Vector2i(dx, dy)
            if candidate != initial_cell and world.is_walkable(candidate.x, candidate.y):
                destination = candidate
                break
        if destination.x >= 0:
            break
    _check(destination.x >= 0, "walkable test destination")
    if destination.x >= 0:
        first["x"] = destination.x
        first["y"] = destination.y
        world.tick += 1
        _check(observer.observe_movement(world, audio, origin, 16.0,
            Vector2(1000, 1000), 0) == 1, "actual step emits exactly once")
        _check(observer.observe_movement(world, audio, origin, 16.0,
            Vector2(1000, 1000), 0) == 0, "same tick does not repeat step")
    _check(observer.on_work_marker(audio, "chop", 7, 30, Vector2(150, 150)),
        "authoritative chop animation marker")
    _check(not observer.on_work_marker(audio, "chop", 7, 30, Vector2(150, 150)),
        "same marker cannot repeat")
    _check(not observer.on_work_marker(audio, "paint", 7, 31, Vector2(150, 150)),
        "unsupported action not invented")
    _check(observer.on_weather_event(audio, "thunder", "strike:10", Vector2(100, 100)),
        "actual weather event accepted")
    _check(not observer.on_weather_event(audio, "thunder", "strike:10", Vector2(100, 100)),
        "weather transition deduplicated")
    _check(not observer.on_weather_event(audio, "rain", "", Vector2(100, 100)),
        "missing weather marker rejected")
    observer.reset()
    _check(observer.on_work_marker(audio, "build", 7, 30, Vector2(150, 150)),
        "observer resets on world replacement")
    _check(before["seed"] == world.seed, "observer does not reseed simulation")
    if failed:
        push_error("AUDIO_PHASE_B_TESTS_FAILED")
    else:
        print("AUDIO_PHASE_B_TESTS_PASSED")
    quit(1 if failed else 0)

func _check(result: bool, label: String) -> void:
    if result:
        print("PASS: " + label)
    else:
        failed = true
        push_error("FAIL: " + label)
