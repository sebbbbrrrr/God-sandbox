extends SceneTree

const Walk = preload("res://scripts/citizen_walk.gd")
var passed := true

func check(ok: bool, label: String) -> void:
    if not ok:
        passed = false
        push_error("FAILED: " + label)

func _initialize() -> void:
    var walk := Walk.new()
    var citizens: Array[Dictionary] = [{"id": 7, "hp": 100, "x": 4, "y": 5}]
    walk.synchronize(citizens)
    check(walk.visual_tile(7) == Vector2(4, 5), "spawn appears immediately")
    check(walk.walk_phase(7) < 0.0, "spawn is idle")
    citizens[0]["x"] = 5
    walk.synchronize(citizens)
    check(walk.visual_tile(7) == Vector2(4, 5), "step starts at previous cell")
    check(walk.has_active_motion(), "one-tile step begins walking")
    walk.advance(Walk.WALK_SECONDS * 0.5)
    check(walk.visual_tile(7).distance_to(Vector2(4.5, 5)) < 0.001, "smooth halfway position")
    check(walk.walk_phase(7) > 0.0, "walking footstep phase advances")
    var before_pause := walk.visual_tile(7)
    walk.advance(0.0)
    check(walk.visual_tile(7) == before_pause, "pause freezes pose and position")
    citizens[0]["y"] = 6
    walk.synchronize(citizens)
    check(walk.visual_tile(7) == before_pause, "retargeting starts at current on-screen position")
    walk.advance(Walk.WALK_SECONDS * 0.5)
    check(walk.visual_tile(7).distance_to(before_pause.lerp(Vector2(5, 6), 0.5)) < 0.001,
        "retargeted motion does not snap")
    walk.advance(Walk.WALK_SECONDS)
    check(walk.visual_tile(7) == Vector2(5, 6), "movement ends at actual destination")
    check(not walk.has_active_motion() and walk.walk_phase(7) < 0.0, "stationary citizen returns to idle")
    citizens[0]["x"] = 40
    walk.synchronize(citizens)
    check(walk.visual_tile(7) == Vector2(40, 6), "large teleports snap without crossing the map")
    citizens[0]["hp"] = 0
    walk.synchronize(citizens)
    check(not walk.tracks.has(7), "dead citizens release visual state")
    print("WALKING_TESTS_%s" % ("PASSED" if passed else "FAILED"))
    quit(0 if passed else 1)
