extends SceneTree

const AudioManagerScript = preload("res://scripts/audio/audio_manager.gd")
var failed := false

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var audio = AudioManagerScript.new()
    root.add_child(audio)
    await process_frame
    for name in audio.BUS_NAMES:
        _check(AudioServer.get_bus_index(name) >= 0, "bus exists: " + name)
    audio.configure_listener(Vector2(480, 850))
    _check(not audio.emit_event("not.registered", Vector2(200, 300)), "unknown events rejected")
    _check(not audio.play_power(-1, Vector2.ZERO), "invalid power rejected")
    _check(not audio.emit_event("world.fire", Vector2(-500, -500)), "offscreen culled")
    audio.set_quality("battery")
    _check(audio.stats()["limit"] == 10, "battery voice limit")
    audio.set_quality("high")
    _check(audio.stats()["limit"] == 40, "high voice limit")
    audio.set_quality("invalid")
    _check(audio.quality == "high", "invalid preset ignored")
    audio.set_master(0.3)
    audio.set_category_volume("Environment", 0.4)
    audio.set_muted(true)
    _check(not audio.play_ui("ui.select"), "mute prevents new voices")
    audio.load_settings()
    _check(is_equal_approx(audio.master_volume, 0.3) and audio.muted, "settings load")
    _check(is_equal_approx(float(audio.category_volumes["Environment"]), 0.4), "bus volume persists")
    audio.set_muted(false)
    _check(audio.play_ui("ui.select"), "UI stream plays")
    _check(audio.stats()["cached_samples"] == 1, "procedural sample cached")
    _check(not audio.play_ui("ui.select"), "event cooldown")
    _check(audio.play_power(1, Vector2(240, 200)), "positional disaster plays")
    _check(audio.stats()["active"] <= audio.stats()["limit"], "under voice cap")
    audio.set_master(0.8)
    audio.set_category_volume("Environment", 1.0)
    audio.set_quality("balanced")
    audio.queue_free()
    if failed:
        push_error("AUDIO_PHASE_A_TESTS_FAILED")
    else:
        print("AUDIO_PHASE_A_TESTS_PASSED")
    quit(1 if failed else 0)

func _check(ok: bool, message: String) -> void:
    if not ok:
        failed = true
        push_error("FAILED: " + message)
    else:
        print("PASS: " + message)
