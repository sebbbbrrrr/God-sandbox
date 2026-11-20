extends RefCounted
const FADING_TIES := ["familiarity", "attachment", "trust"]

const CAPACITY := 12
const FIELDS := ["familiarity", "affinity", "trust", "respect", "fear", "rivalry", "attachment"]

static func encounter(state: Dictionary, other_id: int, cell: Vector2i, tick: int, kind: String) -> Dictionary:
    var ties: Array = state["relationships"]
    var tie: Dictionary = {}
    for existing in ties:
        if int(existing["id"]) == other_id:
            tie = existing
            break
    if tie.is_empty():
        tie = {"id": other_id, "familiarity": 0, "affinity": 0, "trust": 0,
            "respect": 0, "fear": 0, "rivalry": 0, "attachment": 0,
            "last_tick": tick, "last_cell": [cell.x, cell.y]}
        ties.append(tie)
    tie["last_tick"] = tick
    tie["last_cell"] = [cell.x, cell.y]
    tie["familiarity"] = mini(100, int(tie["familiarity"]) + 4)
    var warm: int = 2 + int(state["personality"]["sociability"]) / 25
    match kind:
        "friendly":
            tie["affinity"] = mini(100, int(tie["affinity"]) + warm)
            tie["trust"] = mini(100, int(tie["trust"]) + 2)
            tie["respect"] = mini(100, int(tie["respect"]) + 1)
            tie["attachment"] = mini(100, int(tie["attachment"]) + warm / 2)
            tie["rivalry"] = maxi(0, int(tie["rivalry"]) - 2)
            tie["fear"] = maxi(0, int(tie["fear"]) - 2)
        "support", "healed":
            tie["affinity"] = mini(100, int(tie["affinity"]) + warm + 2)
            tie["trust"] = mini(100, int(tie["trust"]) + 7)
            tie["respect"] = mini(100, int(tie["respect"]) + 5)
            tie["attachment"] = mini(100, int(tie["attachment"]) + warm)
            tie["fear"] = maxi(0, int(tie["fear"]) - 4)
        "conflict", "damage":
            tie["affinity"] = maxi(-100, int(tie["affinity"]) - 5 - int(state["personality"]["caution"]) / 25)
            tie["trust"] = maxi(0, int(tie["trust"]) - 10)
            tie["rivalry"] = mini(100, int(tie["rivalry"]) + 6)
            tie["fear"] = mini(100, int(tie["fear"]) + 3 + int(state["personality"]["caution"]) / 20)
            tie["attachment"] = maxi(0, int(tie["attachment"]) - 3)
    if ties.size() > CAPACITY:
        var weakest := 0
        for i in range(1, ties.size()):
            if retention(ties[i], tick) < retention(ties[weakest], tick):
                weakest = i
        ties.remove_at(weakest)
    return tie

static func retention(tie: Dictionary, tick: int) -> int:
    return int(tie["familiarity"]) + int(tie["attachment"]) * 2 + int(tie["trust"]) + int(tie["rivalry"]) - mini(300, (tick - int(tie["last_tick"])) / 30)

static func preference(tie: Dictionary) -> int:
    return int(tie["affinity"]) + int(tie["trust"]) + int(tie["attachment"]) - int(tie["fear"]) * 2 - int(tie["rivalry"]) * 2

static func find(state: Dictionary, id: int) -> Dictionary:
    for tie in state["relationships"]:
        if int(tie["id"]) == id:
            return tie
    return {}

static func advance(state: Dictionary, tick: int) -> void:
    var units: int = tick / 180 - int(state["last_social_decay"]) / 180
    state["last_social_decay"] = tick
    if units <= 0:
        return
    for tie in state["relationships"]:
        # Grudges and alarm recover; a quiet friendship does not become hatred.
        tie["fear"] = maxi(0, int(tie["fear"]) - units * 2)
        tie["rivalry"] = maxi(0, int(tie["rivalry"]) - units)
        tie["affinity"] = int(move_toward(int(tie["affinity"]), 0, units))
        if tick - int(tie["last_tick"]) > 600:
            for key in FADING_TIES:
                tie[key] = maxi(0, int(tie[key]) - units)
