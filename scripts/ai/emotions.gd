extends RefCounted

const KEYS := ["fear", "anger", "happiness", "sadness", "stress", "social_attachment", "confidence"]

static func create(personality: Dictionary) -> Dictionary:
    return {"fear": 0, "anger": 0, "happiness": 15 + int(personality["curiosity"]) / 10,
        "sadness": 0, "stress": 0, "social_attachment": 0,
        "confidence": 45 + int(personality["diligence"]) / 5}

static func add(state: Dictionary, key: String, amount: int) -> void:
    state["emotions"][key] = clampi(int(state["emotions"][key]) + amount, 0, 100)

static func advance(state: Dictionary, tick: int) -> void:
    var previous: int = state["last_emotion_tick"]
    var units: int = tick / 12 - previous / 12
    state["last_emotion_tick"] = tick
    if units <= 0:
        return
    var baseline := create(state["personality"])
    for key in KEYS:
        var current: int = state["emotions"][key]
        var target: int = baseline[key]
        state["emotions"][key] = move_toward(current, target, units * (2 if key in ["fear", "stress"] else 1)) as int

static func react(state: Dictionary, kind: String, strength: int, tick: int) -> void:
    advance(state, tick)
    var traits: Dictionary = state["personality"]
    var amount := clampi(strength, 1, 100)
    match kind:
        "danger", "witness_damage":
            add(state, "fear", amount * (60 + int(traits["caution"])) / 100)
            add(state, "stress", amount / 3)
            add(state, "confidence", -amount / 6)
        "damage":
            add(state, "fear", amount / 2 + int(traits["caution"]) / 10)
            add(state, "stress", amount)
            add(state, "anger", amount * (20 + int(traits["aggression"])) / 100)
            add(state, "sadness", amount / 3)
            add(state, "confidence", -amount / 4)
        "healed", "support":
            add(state, "stress", -amount)
            add(state, "fear", -amount / 2)
            add(state, "sadness", -amount / 2)
            add(state, "happiness", amount / 2)
            add(state, "confidence", amount / 5)
        "friendly":
            add(state, "happiness", amount * (50 + int(traits["sociability"])) / 100)
            add(state, "social_attachment", amount / 2)
            add(state, "stress", -amount / 2)
            add(state, "confidence", amount / 4)
        "conflict":
            add(state, "anger", amount * (30 + int(traits["aggression"])) / 100)
            add(state, "sadness", amount / 3)
            add(state, "stress", amount / 2)
            add(state, "fear", amount * int(traits["caution"]) / 150)
        "discovery":
            add(state, "happiness", amount / 2)
            add(state, "confidence", amount / 3)
        "failure":
            add(state, "stress", amount / 3)
            add(state, "confidence", -amount / 4)
