extends RefCounted
class_name CitizenWalk

# Presentation-only movement state. AI, collision and save data remain tile based.
var walk_seconds := 0.85
var tracks: Dictionary = {}

func synchronize(citizens: Array[Dictionary]) -> void:
    var present: Dictionary = {}
    for citizen in citizens:
        if int(citizen["hp"]) <= 0:
            continue
        var id: int = int(citizen["id"])
        var destination := Vector2(float(citizen["x"]), float(citizen["y"]))
        present[id] = true
        if not tracks.has(id):
            tracks[id] = {"from": destination, "to": destination, "elapsed": walk_seconds}
            continue
        var track: Dictionary = tracks[id]
        var previous_target: Vector2 = track["to"]
        if previous_target == destination:
            continue
        var previous_origin: Vector2 = track["from"]
        var fraction := clampf(float(track["elapsed"]) / walk_seconds, 0.0, 1.0)
        var current := previous_origin.lerp(previous_target, fraction)
        # Teleports / restoration must not animate across unrelated tiles.
        if current.distance_to(destination) > 2.0:
            current = destination
        track["from"] = current
        track["to"] = destination
        track["elapsed"] = walk_seconds if current == destination else 0.0
    for id in tracks.keys():
        if not present.has(id):
            tracks.erase(id)

func advance(delta: float) -> bool:
    if delta <= 0.0:
        return false
    var changed := false
    for track in tracks.values():
        if float(track["elapsed"]) < walk_seconds:
            track["elapsed"] = minf(walk_seconds, float(track["elapsed"]) + delta)
            changed = true
    return changed

func has_active_motion() -> bool:
    for track in tracks.values():
        if float(track["elapsed"]) < walk_seconds:
            return true
    return false

func alpha(id: int) -> float:
    if not tracks.has(id):
        return 1.0
    return clampf(float(tracks[id]["elapsed"]) / walk_seconds, 0.0, 1.0)

func visual_tile(id: int) -> Vector2:
    if not tracks.has(id):
        return Vector2.ZERO
    var track: Dictionary = tracks[id]
    var start: Vector2 = track["from"]
    var goal: Vector2 = track["to"]
    return start.lerp(goal, alpha(id))

func walk_phase(id: int) -> float:
    if not tracks.has(id):
        return -1.0
    var track: Dictionary = tracks[id]
    if track["from"] == track["to"] or float(track["elapsed"]) >= walk_seconds:
        return -1.0
    return alpha(id)
