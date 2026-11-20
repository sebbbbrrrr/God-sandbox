extends RefCounted

const GOALS := ["explore", "rest", "seek_safety", "avoid_danger", "socialize", "seek_settlement", "investigate", "return_familiar"]
const LIMIT := 60

static func create() -> Dictionary:
    var result := {}
    for goal in GOALS:
        result[goal] = 0
    return result

static func reinforce(state: Dictionary, goal: String, outcome: int) -> void:
    if state["learned"].has(goal):
        state["learned"][goal] = clampi(int(state["learned"][goal]) + clampi(outcome, -12, 12), -LIMIT, LIMIT)

static func advance(state: Dictionary, tick: int) -> void:
    var units: int = tick / 600 - int(state["last_learning_tick"]) / 600
    state["last_learning_tick"] = tick
    if units > 0:
        for key in GOALS:
            state["learned"][key] = int(move_toward(int(state["learned"][key]), 0, units))
