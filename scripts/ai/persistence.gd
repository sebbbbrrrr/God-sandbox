extends RefCounted

const Learning = preload("res://scripts/ai/learning.gd")
const Emotion = preload("res://scripts/ai/emotions.gd")
const Relations = preload("res://scripts/ai/relationships.gd")
const Memory = preload("res://scripts/ai/memory.gd")
const Perception = preload("res://scripts/ai/perception.gd")
const Nav = preload("res://scripts/ai/navigation.gd")

static func number(value: Variant, minimum: int, maximum: int, fallback: int = 0) -> int:
    if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
        return fallback
    if typeof(value) == TYPE_FLOAT and not is_finite(value):
        return fallback
    return clampi(int(value), minimum, maximum)

static func cell(value: Variant) -> Array:
    if value is Array and value.size() == 2 and typeof(value[0]) in [TYPE_INT, TYPE_FLOAT] and typeof(value[1]) in [TYPE_INT, TYPE_FLOAT]:
        return [number(value[0], -1, 95), number(value[1], -1, 127)]
    return [-1, -1]

static func records(data: Dictionary, key: String, limit: int) -> Array:
    var incoming: Variant = data.get(key, [])
    if incoming is Array:
        return incoming.slice(0, limit)
    return []

static func restore(data: Variant, safe: Dictionary, tick: int) -> Dictionary:
    if not data is Dictionary:
        return safe
    for group in ["personality", "needs", "emotions", "learned"]:
        var incoming: Variant = data.get(group, {})
        if not incoming is Dictionary:
            continue
        for key in safe[group]:
            safe[group][key] = number(incoming.get(key, safe[group][key]), -Learning.LIMIT if group == "learned" else 0, Learning.LIMIT if group == "learned" else 100, safe[group][key])
    if not data.has("emotions"):
        safe["emotions"] = Emotion.create(safe["personality"])
    if str(data.get("goal", "")) in Learning.GOALS:
        safe["goal"] = data["goal"]
    for key in ["target", "danger_cell"]:
        safe[key] = cell(data.get(key))
    safe["target_id"] = number(data.get("target_id", 0), 0, 2147483647)
    for key in ["last_decision", "last_needs_tick", "last_emotion_tick", "last_memory_tick", "last_social_decay", "last_belief_tick", "last_learning_tick", "last_hazard_tick", "last_outcome_tick"]:
        safe[key] = number(data.get(key, safe[key]), 0, tick, safe[key])
    for key in ["next_decision", "next_path_tick", "next_social_tick", "commit_until"]:
        safe[key] = number(data.get(key, safe[key]), 0, tick + 600, safe[key])
    safe["risk_revision"] = number(data.get("risk_revision", 0), 0, 9223372036854775807)
    safe["blocked_steps"] = number(data.get("blocked_steps", 0), 0, 100)
    for step in records(data, "route", Nav.MAX_ROUTE):
        var location := cell(step)
        if location[0] >= 0 and location[1] >= 0:
            safe["route"].append(location)
    for record in records(data, "memories", Memory.CAPACITY):
        if not record is Dictionary:
            continue
        var location := cell(record.get("cell"))
        if location[0] < 0 or location[1] < 0:
            continue
        var participants: Array = []
        for id in records(record, "participants", 3):
            if number(id, 0, 2147483647) > 0:
                participants.append(int(id))
        safe["memories"].append({"kind": str(record.get("kind", "danger")).substr(0, 32),
            "cell": location, "tick": number(record.get("tick", 0), 0, tick),
            "participants": participants, "significance": number(record.get("significance", 35), 0, 100),
            "outcome": number(record.get("outcome", -20), -100, 100),
            "importance": number(record.get("importance", 40), 0, 100),
            "confidence": number(record.get("confidence", 100), 0, 100),
            "repetitions": number(record.get("repetitions", 1), 1, 255, 1)})
    var seen: Dictionary = {}
    for record in records(data, "relationships", Relations.CAPACITY):
        if not record is Dictionary:
            continue
        var id := number(record.get("id", 0), 0, 2147483647)
        if id <= 0 or seen.has(id):
            continue
        seen[id] = true
        var tie := {"id": id, "last_cell": cell(record.get("last_cell")), "last_tick": number(record.get("last_tick", 0), 0, tick)}
        for key in Relations.FIELDS:
            tie[key] = number(record.get(key, 0), -100 if key == "affinity" else 0, 100)
        safe["relationships"].append(tie)
    seen.clear()
    for record in records(data, "beliefs", Perception.BELIEF_CAPACITY):
        if not record is Dictionary:
            continue
        var location := cell(record.get("cell"))
        if location[0] < 0 or location[1] < 0 or seen.has(location):
            continue
        seen[location] = true
        safe["beliefs"].append({"cell": location, "terrain": number(record.get("terrain", 0), 0, 6),
            "confidence": number(record.get("confidence", 0), 0, 100),
            "source": "shared" if record.get("source") == "shared" else "direct",
            "source_id": number(record.get("source_id", 0), 0, 2147483647),
            "hops": number(record.get("hops", 0), 0, 2),
            "observed_at": number(record.get("observed_at", 0), 0, tick),
            "updated_at": number(record.get("updated_at", 0), 0, tick),
            "visits": number(record.get("visits", 0), 0, 100)})
    for option in records(data, "utilities", 10):
        if option is Dictionary and str(option.get("goal", "")) in Learning.GOALS:
            safe["utilities"].append({"goal": str(option["goal"]), "score": number(option.get("score", 0), -10000, 10000),
                "target": cell(option.get("target")), "target_id": number(option.get("target_id", 0), 0, 2147483647)})
    return safe
