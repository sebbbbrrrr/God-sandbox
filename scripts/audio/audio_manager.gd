extends Node
## God Sandbox Phase A: opt-in event-driven 2D audio. No simulation state is mutated.
signal event_accepted(event_id: String)
signal event_dropped(event_id: String, reason: String)

const SETTINGS_PATH := "user://audio_settings.cfg"
const SAMPLE_RATE := 22050
const BUS_NAMES := ["Environment", "Citizens", "Construction", "Disasters", "Interface", "Music", "Ambience", "Combat"]
const DEFINITIONS := {
    "ui.select": {"bus": "Interface", "duration": 0.045, "tone": 650.0, "noise": 0.08, "gain": -12.0},
    "ui.toggle": {"bus": "Interface", "duration": 0.075, "tone": 460.0, "noise": 0.08, "gain": -12.0},
    "world.raise": {"bus": "Environment", "duration": 0.18, "tone": 240.0, "noise": 0.35, "gain": -12.0},
    "world.forest": {"bus": "Environment", "duration": 0.21, "tone": 340.0, "noise": 0.42, "gain": -13.0},
    "world.ocean": {"bus": "Environment", "duration": 0.30, "tone": 140.0, "noise": 0.72, "gain": -13.0},
    "world.spawn": {"bus": "Citizens", "duration": 0.13, "tone": 520.0, "noise": 0.12, "gain": -12.0},
    "world.bless": {"bus": "Citizens", "duration": 0.24, "tone": 730.0, "noise": 0.05, "gain": -16.0},
    "world.fire": {"bus": "Disasters", "duration": 0.30, "tone": 95.0, "noise": 0.83, "gain": -11.0},
    "citizen.step": {"bus": "Citizens", "duration": 0.06, "tone": 100.0, "noise": 0.75, "gain": -20.0},
    "construction.hit": {"bus": "Construction", "duration": 0.09, "tone": 290.0, "noise": 0.48, "gain": -14.0},
    "citizen.step.grass": {"bus": "Citizens", "duration": 0.055, "tone": 125.0, "noise": 0.8, "gain": -22.0},
    "citizen.step.sand": {"bus": "Citizens", "duration": 0.075, "tone": 80.0, "noise": 0.92, "gain": -22.0},
    "citizen.step.stone": {"bus": "Citizens", "duration": 0.06, "tone": 350.0, "noise": 0.42, "gain": -21.0},
    "citizen.step.wood": {"bus": "Citizens", "duration": 0.08, "tone": 210.0, "noise": 0.32, "gain": -21.0},
    "work.chop": {"bus": "Construction", "duration": 0.12, "tone": 185.0, "noise": 0.45, "gain": -15.0},
    "work.mine": {"bus": "Construction", "duration": 0.15, "tone": 510.0, "noise": 0.55, "gain": -15.0},
    "work.saw": {"bus": "Construction", "duration": 0.20, "tone": 390.0, "noise": 0.85, "gain": -18.0},
    "work.dig": {"bus": "Construction", "duration": 0.14, "tone": 140.0, "noise": 0.76, "gain": -18.0},
    "work.deliver": {"bus": "Construction", "duration": 0.12, "tone": 190.0, "noise": 0.38, "gain": -17.0},
    "work.build": {"bus": "Construction", "duration": 0.11, "tone": 270.0, "noise": 0.46, "gain": -15.0},
    "work.repair": {"bus": "Construction", "duration": 0.11, "tone": 290.0, "noise": 0.45, "gain": -16.0},
    "work.demolish": {"bus": "Construction", "duration": 0.21, "tone": 115.0, "noise": 0.82, "gain": -14.0},
    "ambient.forest": {"bus": "Ambience", "duration": 0.85, "tone": 625.0, "noise": 0.60, "gain": -26.0},
    "ambient.ocean": {"bus": "Ambience", "duration": 1.0, "tone": 115.0, "noise": 0.96, "gain": -25.0},
    "ambient.settlement": {"bus": "Ambience", "duration": 0.65, "tone": 230.0, "noise": 0.67, "gain": -26.0},
    "ambient.wilderness": {"bus": "Ambience", "duration": 0.7, "tone": 420.0, "noise": 0.75, "gain": -28.0},
    "ambient.night": {"bus": "Ambience", "duration": 1.1, "tone": 180.0, "noise": 0.73, "gain": -29.0},
    "weather.rain": {"bus": "Environment", "duration": 0.9, "tone": 135.0, "noise": 0.98, "gain": -25.0},
    "weather.wind": {"bus": "Environment", "duration": 0.8, "tone": 95.0, "noise": 0.94, "gain": -26.0},
    "weather.thunder": {"bus": "Environment", "duration": 0.9, "tone": 70.0, "noise": 0.82, "gain": -13.0},
    "civilisation.early_stone": {"bus": "Ambience", "duration": 0.500, "tone": 140.0, "noise": 0.45, "gain": -28.0},
    "civilisation.agricultural": {"bus": "Ambience", "duration": 0.525, "tone": 172.0, "noise": 0.49, "gain": -28.0},
    "civilisation.bronze": {"bus": "Ambience", "duration": 0.550, "tone": 204.0, "noise": 0.52, "gain": -28.0},
    "civilisation.classical": {"bus": "Ambience", "duration": 0.575, "tone": 236.0, "noise": 0.56, "gain": -28.0},
    "civilisation.medieval": {"bus": "Ambience", "duration": 0.600, "tone": 268.0, "noise": 0.59, "gain": -28.0},
    "civilisation.scientific": {"bus": "Ambience", "duration": 0.625, "tone": 300.0, "noise": 0.63, "gain": -28.0},
    "civilisation.industrial": {"bus": "Ambience", "duration": 0.650, "tone": 332.0, "noise": 0.67, "gain": -28.0},
    "civilisation.electrical": {"bus": "Ambience", "duration": 0.675, "tone": 364.0, "noise": 0.70, "gain": -28.0},
    "civilisation.information": {"bus": "Ambience", "duration": 0.700, "tone": 396.0, "noise": 0.74, "gain": -28.0},
    "civilisation.advanced": {"bus": "Ambience", "duration": 0.725, "tone": 428.0, "noise": 0.77, "gain": -28.0},
    "civilisation.far_future": {"bus": "Ambience", "duration": 0.750, "tone": 460.0, "noise": 0.81, "gain": -28.0}
}
# Authored, redistributable original 16-kHz mono WAV foley, kept short for mobile.
# Unlisted event IDs fall back to deterministic synthetic textures.
const SAMPLE_PATHS := {
    "work.chop": "res://assets/audio/foley/work_chop.wav",
    "work.mine": "res://assets/audio/foley/work_mine.wav",
    "work.saw": "res://assets/audio/foley/work_saw.wav",
    "work.dig": "res://assets/audio/foley/work_dig.wav",
    "work.build": "res://assets/audio/foley/work_build.wav",
    "work.deliver": "res://assets/audio/foley/work_deliver.wav",
    "citizen.step.grass": "res://assets/audio/foley/step_grass.wav",
    "citizen.step.stone": "res://assets/audio/foley/step_stone.wav",
    "ui.select": "res://assets/audio/foley/ui_select.wav",
    "world.fire": "res://assets/audio/foley/world_fire.wav"
}
const POWER_EVENTS := ["world.raise", "world.fire", "world.forest", "world.bless", "world.spawn", "world.ocean"]
const VOICE_LIMITS := {"battery": 10, "balanced": 20, "high": 40}

var quality := "balanced"
var master_volume := 0.8
var muted := false
var category_volumes := {}
var _samples := {}
var _active: Array[AudioStreamPlayer2D] = []
var _last_event_ms := {}
var _listener := Vector2.ZERO
var _screen_size := Vector2(480, 850)
var _ui_bottom := 188.0
var _clock_ms := 0
var _accepted_count := 0
var _dropped_count := 0

func _ready() -> void:
    _ensure_buses()
    load_settings()
    apply_settings()
    process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
    # Reclaim finished voices without retaining references to freed nodes.
    for i in range(_active.size() - 1, -1, -1):
        if not is_instance_valid(_active[i]):
            _active.remove_at(i)

func _ensure_buses() -> void:
    for bus_name in BUS_NAMES:
        if AudioServer.get_bus_index(bus_name) == -1:
            AudioServer.add_bus()
            var idx := AudioServer.bus_count - 1
            AudioServer.set_bus_name(idx, bus_name)
            AudioServer.set_bus_send(idx, "Master")

func configure_listener(viewport_size: Vector2, bottom_panel: float = 188.0) -> void:
    _screen_size = viewport_size
    _ui_bottom = bottom_panel
    _listener = Vector2(viewport_size.x * 0.5, (viewport_size.y - bottom_panel) * 0.5)

func set_quality(value: String) -> void:
    if not VOICE_LIMITS.has(value):
        return
    quality = value
    save_settings()

func set_master(value: float) -> void:
    master_volume = clampf(value, 0.0, 1.0)
    apply_settings()
    save_settings()

func set_muted(value: bool) -> void:
    muted = value
    apply_settings()
    save_settings()

func set_category_volume(bus_name: String, value: float) -> void:
    if not BUS_NAMES.has(bus_name):
        return
    category_volumes[bus_name] = clampf(value, 0.0, 1.0)
    apply_settings()
    save_settings()

func apply_settings() -> void:
    var master_idx := AudioServer.get_bus_index("Master")
    if master_idx >= 0:
        AudioServer.set_bus_volume_db(master_idx, linear_to_db(maxf(0.0001, master_volume)))
        AudioServer.set_bus_mute(master_idx, muted)
    for bus_name in BUS_NAMES:
        var idx := AudioServer.get_bus_index(bus_name)
        if idx >= 0:
            AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(0.0001, float(category_volumes.get(bus_name, 1.0)))))

func save_settings() -> void:
    var config := ConfigFile.new()
    config.set_value("audio", "quality", quality)
    config.set_value("audio", "master", master_volume)
    config.set_value("audio", "muted", muted)
    for bus_name in BUS_NAMES:
        config.set_value("buses", bus_name, float(category_volumes.get(bus_name, 1.0)))
    config.save(SETTINGS_PATH)

func load_settings() -> void:
    var config := ConfigFile.new()
    if config.load(SETTINGS_PATH) != OK:
        return
    var loaded_quality := str(config.get_value("audio", "quality", "balanced"))
    quality = loaded_quality if VOICE_LIMITS.has(loaded_quality) else "balanced"
    master_volume = clampf(float(config.get_value("audio", "master", 0.8)), 0.0, 1.0)
    muted = bool(config.get_value("audio", "muted", false))
    for bus_name in BUS_NAMES:
        category_volumes[bus_name] = clampf(float(config.get_value("buses", bus_name, 1.0)), 0.0, 1.0)

func play_ui(event_id: String) -> bool:
    return emit_event(event_id, _listener, false)

func play_power(power: int, screen_position: Vector2) -> bool:
    if power < 0 or power >= POWER_EVENTS.size():
        return false
    return emit_event(POWER_EVENTS[power], screen_position, true)

func emit_event(event_id: String, screen_position: Vector2, spatial: bool = true) -> bool:
    if muted or not DEFINITIONS.has(event_id):
        return _drop(event_id, "muted_or_unknown")
    if spatial and (screen_position.x < -80.0 or screen_position.y < -80.0 or
            screen_position.x > _screen_size.x + 80.0 or
            screen_position.y > _screen_size.y - _ui_bottom + 80.0):
        return _drop(event_id, "offscreen")
    var now := Time.get_ticks_msec()
    # Paint strokes can generate hundreds of mutations per frame; cap audio separately.
    var cooldown := 75 if event_id.begins_with("world.") else (300 if event_id.begins_with("work.") else (1000 if event_id.begins_with("ambient.") or event_id.begins_with("weather.") else 45))
    if now - int(_last_event_ms.get(event_id, -100000)) < cooldown:
        return _drop(event_id, "cooldown")
    _last_event_ms[event_id] = now
    _clean_active()
    var cap: int = VOICE_LIMITS[quality]
    if _active.size() >= cap:
        return _drop(event_id, "voice_budget")
    var definition: Dictionary = DEFINITIONS[event_id]
    var player := AudioStreamPlayer2D.new()
    player.bus = str(definition["bus"])
    player.stream = _get_sample(event_id)
    player.volume_db = float(definition["gain"])
    # Gentle per-event timbre variation; unrelated to simulation speed.
    if event_id.begins_with("work.") or event_id.begins_with("citizen.step."):
        player.pitch_scale = 0.96 + float(posmod(_accepted_count * 17 + event_id.hash(), 9)) * 0.01
    player.max_distance = 1000.0
    player.attenuation = 0.6 if spatial else 0.0
    player.position = screen_position if spatial else _listener
    add_child(player)
    _active.append(player)
    player.finished.connect(player.queue_free)
    player.play()
    _accepted_count += 1
    event_accepted.emit(event_id)
    return true

func _clean_active() -> void:
    for i in range(_active.size() - 1, -1, -1):
        if not is_instance_valid(_active[i]) or not _active[i].playing:
            if is_instance_valid(_active[i]):
                _active[i].queue_free()
            _active.remove_at(i)

func _drop(event_id: String, reason: String) -> bool:
    _dropped_count += 1
    event_dropped.emit(event_id, reason)
    return false

func stats() -> Dictionary:
    _clean_active()
    return {"active": _active.size(), "limit": VOICE_LIMITS[quality],
        "accepted": _accepted_count, "dropped": _dropped_count,
        "cached_samples": _samples.size()}

func register_sample(event_id: String, stream: AudioStream) -> bool:
    if not DEFINITIONS.has(event_id) or stream == null:
        return false
    _samples[event_id] = stream
    return true

func _get_sample(event_id: String) -> AudioStream:
    if _samples.has(event_id):
        return _samples[event_id]
    if SAMPLE_PATHS.has(event_id):
        var path: String = SAMPLE_PATHS[event_id]
        if ResourceLoader.exists(path):
            var imported := load(path) as AudioStream
            if imported != null:
                _samples[event_id] = imported
                return imported
    # Lightweight original procedural placeholder; replace through register_sample
    # with properly licensed realistic recordings during later content phases.
    var info: Dictionary = DEFINITIONS[event_id]
    var count := int(float(info["duration"]) * SAMPLE_RATE)
    var bytes := PackedByteArray()
    bytes.resize(count * 2)
    var random := RandomNumberGenerator.new()
    random.seed = event_id.hash()
    var phase := 0.0
    for i in range(count):
        var envelope := pow(1.0 - float(i) / float(count), 2.0)
        phase += TAU * float(info["tone"]) / float(SAMPLE_RATE)
        var wave := sin(phase) * (1.0 - float(info["noise"])) + random.randf_range(-1.0, 1.0) * float(info["noise"])
        var sample := int(clampf(wave * envelope * 0.65, -1.0, 1.0) * 32767.0)
        bytes[i * 2] = sample & 255
        bytes[i * 2 + 1] = (sample >> 8) & 255
    var wav := AudioStreamWAV.new()
    wav.format = AudioStreamWAV.FORMAT_16_BITS
    wav.mix_rate = SAMPLE_RATE
    wav.stereo = false
    wav.data = bytes
    _samples[event_id] = wav
    return wav
