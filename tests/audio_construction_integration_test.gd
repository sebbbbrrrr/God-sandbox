extends SceneTree
const Bridge = preload("res://scripts/audio/construction_audio_bridge.gd")
const Living = preload("res://scripts/audio/living_world_audio.gd")

class FakeAudio:
    extends Node
    var played: Array[String] = []
    func emit_event(event_id: String, _position: Vector2, _spatial: bool = true) -> bool:
        played.append(event_id)
        return true

class FakeConstruction:
    extends RefCounted
    var jobs: Dictionary = {}
    var projects: Array[Dictionary] = []
    var houses: Array[Dictionary] = []

class FakeWorld:
    extends RefCounted
    var tick := 1
    var citizens: Array[Dictionary] = [{"id": 7, "hp": 100, "x": 5, "y": 5}]
    var construction := FakeConstruction.new()

var failed := false

func _initialize() -> void:
    var bridge = Bridge.new()
    var living = Living.new()
    var audio = FakeAudio.new()
    var world = FakeWorld.new()
    root.add_child(audio)
    _check(Bridge.classify_build_action("saw") == "saw", "saw variant mapping")
    _check(Bridge.classify_build_action("hammer") == "build", "hammer variant mapping")
    _check(Bridge.classify_build_action("clear") == "dig", "prep variant mapping")
    _check(Bridge.classify_build_action("unknown") == "", "unknown action suppressed")
    var sz := Vector2(480, 850)
    world.construction.jobs["7"] = {"kind":"gather", "phase":"source", "amount":0, "material":"wood"}
    _check(bridge.observe(world, living, audio, Vector2.ZERO, 16.0, sz, 0.0, 0.0) == 0,
        "initial baseline is silent")
    world.tick = 2
    _check(bridge.observe(world, living, audio, Vector2.ZERO, 16.0, sz, 0.0, 0.0) == 0,
        "unchanged gathering job is silent")
    world.construction.jobs["7"]["phase"] = "depot"
    world.construction.jobs["7"]["amount"] = 1
    world.tick = 3
    _check(bridge.observe(world, living, audio, Vector2.ZERO, 16.0, sz, 0.0, 0.0) == 1,
        "actual extraction schedules one contact sound")
    _check(audio.played.is_empty(), "no premature sound before tool contact")
    _check(not Bridge.contact_crossed(0.0, 0.1, 7), "wind-up remains silent")
    _check(bridge.flush_contacts(living, audio, 0.0, 1.4) == 1,
        "strike marker releases the committed action")
    _check(audio.played == ["work.chop"], "wood extraction routes to axe sound")
    _check(bridge.flush_contacts(living, audio, 1.4, 2.8) == 0,
        "recovery/next gesture cannot replay a spent event")
    _check(bridge.observe(world, living, audio, Vector2.ZERO, 16.0, sz, 0.0, 0.0) == 0,
        "same authoritative tick never repeats")
    world.tick = 4
    _check(bridge.observe(world, living, audio, Vector2.ZERO, 16.0, sz, 0.0, 0.0) == 0,
        "no phantom work after extraction")
    bridge.reset()
    world.tick = 1
    _check(bridge.observe(world, living, audio, Vector2.ZERO, 16.0, sz, 0.0, 0.0) == 0,
        "load/restart baseline resets")
    if failed:
        push_error("AUDIO_CONSTRUCTION_INTEGRATION_TESTS_FAILED")
    else:
        print("AUDIO_CONSTRUCTION_INTEGRATION_TESTS_PASSED")
    quit(1 if failed else 0)

func _check(ok: bool, name: String) -> void:
    if ok:
        print("PASS: " + name)
    else:
        failed = true
        push_error("FAILED: " + name)
