extends RefCounted

const CAPACITY := 12

static func remember(state: Dictionary, kind: String, cell: Vector2i, tick: int,
        participants: Array = [], significance: int = 35, outcome: int = -20,
        importance: int = 40, confidence: int = 100) -> void:
    var records: Array = state["memories"]
    var location := [cell.x, cell.y]
    for record in records:
        if record["kind"] == kind and record["cell"] == location and record["participants"] == participants and tick - int(record["tick"]) <= 180:
            record["tick"] = tick
            record["importance"] = mini(100, maxi(importance, int(record["importance"])) + 3)
            record["confidence"] = maxi(int(record["confidence"]), confidence)
            record["significance"] = maxi(int(record["significance"]), significance)
            record["outcome"] = clampi(outcome, -100, 100)
            record["repetitions"] = mini(255, int(record["repetitions"]) + 1)
            return
    records.append({"kind": kind, "cell": location, "tick": tick,
        "participants": participants.duplicate(), "significance": clampi(significance, 0, 100),
        "outcome": clampi(outcome, -100, 100), "importance": clampi(importance, 0, 100),
        "confidence": clampi(confidence, 0, 100), "repetitions": 1})
    if records.size() > CAPACITY:
        var weakest := 0
        for i in range(1, records.size()):
            if priority(records[i], tick) < priority(records[weakest], tick):
                weakest = i
        records.remove_at(weakest)

static func priority(record: Dictionary, tick: int) -> int:
    return int(record["importance"]) * 4 + int(record["significance"]) + int(record["confidence"]) - mini(300, (tick - int(record["tick"])) / 12)

static func advance(state: Dictionary, tick: int) -> void:
    var units: int = tick / 60 - int(state["last_memory_tick"]) / 60
    state["last_memory_tick"] = tick
    if units <= 0:
        return
    var records: Array = state["memories"]
    for i in range(records.size() - 1, -1, -1):
        var record: Dictionary = records[i]
        record["confidence"] = maxi(0, int(record["confidence"]) - units * (1 + (100 - int(record["importance"])) / 15))
        if int(record["confidence"]) == 0:
            records.remove_at(i)

static func risk(state: Dictionary, cell: Vector2i) -> int:
    var result := 0
    for record in state["memories"]:
        if record["kind"] not in ["danger", "damage", "witness_damage"]:
            continue
        var distance: int = absi(cell.x - int(record["cell"][0])) + absi(cell.y - int(record["cell"][1]))
        if distance <= 2:
            result = maxi(result, int(record["importance"]) * int(record["confidence"]) / (100 * (distance + 1)))
    return result
