extends RefCounted
class_name SandboxWeather

# Deterministic, visual-only weather driven by simulation time, not by the
# authoritative RNG. Loading an existing save resumes at the correct phase.
const PHASE_SECONDS := 75.0
const TRANSITION_SECONDS := 14.0
const NAMES := ["Calm", "Breezy", "Windy", "Rain", "Breezy", "Storm", "Calm", "Rain"]
const WIND := [0.08, 0.25, 0.55, 0.30, 0.27, 0.78, 0.09, 0.20]
const RAIN := [0.0, 0.0, 0.0, 0.56, 0.0, 0.93, 0.0, 0.36]

var seed: int
var seconds := 0.0
var phase_index := 0
var wind_strength := 0.08
var rain_strength := 0.0
var wind_direction := Vector2.RIGHT

func _init(world_seed: int = 424242) -> void:
    seed = world_seed
    set_time(0.0)

func set_time(value: float) -> void:
    seconds = maxf(0.0, value)
    var segment := floori(seconds / PHASE_SECONDS)
    phase_index = posmod(segment, NAMES.size())
    var previous := phase_index if segment == 0 else posmod(segment - 1, NAMES.size())
    var transition := smoothstep(0.0, TRANSITION_SECONDS, fposmod(seconds, PHASE_SECONDS))
    var baseline := lerpf(float(WIND[previous]), float(WIND[phase_index]), transition)
    var gust := 1.0 + 0.14 * sin(seconds * 0.67 + float(posmod(seed, 97))) + 0.08 * sin(seconds * 1.39)
    wind_strength = clampf(baseline * gust, 0.0, 1.0)
    rain_strength = clampf(lerpf(float(RAIN[previous]), float(RAIN[phase_index]), transition), 0.0, 1.0)
    var old_dir := 1.0 if posmod(seed + segment - 1, 5) < 3 else -1.0
    var new_dir := 1.0 if posmod(seed + segment, 5) < 3 else -1.0
    wind_direction = Vector2(lerpf(old_dir, new_dir, transition), 0.18).normalized()

func description() -> String:
    return str(NAMES[phase_index])
