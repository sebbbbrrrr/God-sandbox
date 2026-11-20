extends SceneTree
const Manager = preload("res://scripts/audio/audio_manager.gd")
var failed := false

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var manager = Manager.new()
    root.add_child(manager)
    await process_frame
    for event_id in Manager.SAMPLE_PATHS:
        var path: String = Manager.SAMPLE_PATHS[event_id]
        _check(ResourceLoader.exists(path), "imported original sample " + event_id)
        var sample = manager._get_sample(event_id)
        _check(sample is AudioStream, "sound stream is playable " + event_id)
        _check(manager._samples.has(event_id), "asset caching " + event_id)
    _check(Manager.SAMPLE_PATHS.size() == 10, "ten authored short WAV samples")
    _check(manager._get_sample("ambient.forest") is AudioStream,
        "unregistered recording uses explicit fallback")
    _check(manager.stats()["cached_samples"] == 11, "cache remains bounded by used keys")
    manager.queue_free()
    if failed:
        push_error("AUDIO_SAMPLE_VALIDATION_FAILED")
    else:
        print("AUDIO_SAMPLE_VALIDATION_PASSED")
    quit(1 if failed else 0)

func _check(ok: bool, message: String) -> void:
    if ok:
        print("PASS: " + message)
    else:
        failed = true
        push_error("FAILED: " + message)
