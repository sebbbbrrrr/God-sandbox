extends RefCounted
class_name CitizenAI

# Deterministic simulation-only cognition. No nodes, graphics or global RNG usage.
const GOAL_EXPLORE := "explore"
const GOAL_REST := "rest"
const GOAL_SOCIAL := "socialize"
const GOAL_SAFE := "seek_safety"
const GOAL_SETTLEMENT := "seek_settlement"
const MAX_MEMORIES := 8

static func trait(world_seed: int, person_id: int, salt: int) -> int:
    var value := posmod(world_seed, 1000003)
    value = posmod(value * 37 + person_id * 1009 + salt * 7919, 1000003)
    value = posmod(value * 103 + 17011, 1000003)
    return int(value % 101)

static func create_state(world_seed: int, person_id: int, tick: int) -> Dictionary:
    return {
        "personality": {
            "curiosity": trait(world_seed, person_id, 1),
            "sociability": trait(world_seed, person_id, 2),
            "diligence": trait(world_seed, person_id, 3),
            "aggression": trait(world_seed, person_id, 4),
            "caution": trait(world_seed, person_id, 5)
        },
        "needs": {"fatigue": 0, "social": 0, "safety": 0},
        "goal": GOAL_EXPLORE,
        "last_decision": tick,
        "last_needs_tick": tick,
        "memories": [],
        "danger_cell": [-1, -1]
    }

static func remember(state: Dictionary, kind: String, cell: Vector2i, tick: int) -> void:
    var records: Array = state["memories"]
    if not records.is_empty():
        var last: Dictionary = records[records.size() - 1]
        if last.get("kind") == kind and last.get("cell") == [cell.x, cell.y]:
            last["tick"] = tick
            return
    records.append({"kind": kind, "cell": [cell.x, cell.y], "tick": tick})
    if records.size() > MAX_MEMORIES:
        records.pop_front()

static func advance_needs(state: Dictionary, tick: int) -> void:
    var elapsed: int = maxi(0, tick - int(state["last_needs_tick"]))
    state["last_needs_tick"] = tick
    var needs: Dictionary = state["needs"]
    needs["fatigue"] = clampi(int(needs["fatigue"]) + elapsed / 12, 0, 100)
    needs["social"] = clampi(int(needs["social"]) + elapsed / 18, 0, 100)

static func danger_near(world: RefCounted, cell: Vector2i) -> bool:
    for dy in range(-1, 2):
        for dx in range(-1, 2):
            if world.at(cell.x + dx, cell.y + dy) == world.ASH:
                return true
    return false

static func decide(world: RefCounted, person: Dictionary, state: Dictionary) -> void:
    var current := Vector2i(int(person["x"]), int(person["y"]))
    var needs: Dictionary = state["needs"]
    var traits: Dictionary = state["personality"]
    var danger := danger_near(world, current) or not world.is_walkable(current.x, current.y)
    if danger:
        state["goal"] = GOAL_SAFE
        needs["safety"] = 100
        state["danger_cell"] = [current.x, current.y]
        remember(state, "danger", current, world.tick)
    elif int(needs["fatigue"]) >= 65:
        state["goal"] = GOAL_REST
        needs["safety"] = maxi(0, int(needs["safety"]) - 2)
    elif int(needs["social"]) >= 60 and int(traits["sociability"]) >= 35:
        state["goal"] = GOAL_SOCIAL
        needs["safety"] = maxi(0, int(needs["safety"]) - 2)
    elif int(traits["curiosity"]) < 28:
        state["goal"] = GOAL_SETTLEMENT
        needs["safety"] = maxi(0, int(needs["safety"]) - 2)
    else:
        state["goal"] = GOAL_EXPLORE
        needs["safety"] = maxi(0, int(needs["safety"]) - 2)
    state["last_decision"] = world.tick

static func step(world: RefCounted, person: Dictionary, state: Dictionary) -> void:
    advance_needs(state, world.tick)
    var pos := Vector2i(int(person["x"]), int(person["y"]))
    if danger_near(world, pos) or not world.is_walkable(pos.x, pos.y) or world.tick - int(state["last_decision"]) >= 12:
        decide(world, person, state)
    var goal: String = state["goal"]
    var needs: Dictionary = state["needs"]
    if goal == GOAL_REST:
        needs["fatigue"] = maxi(0, int(needs["fatigue"]) - 5)
        return
    # Bounded one-cell movement, never pathfinds across the entire map.
    var dirs := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
    var offset := trait(world.seed + world.tick, int(person["id"]), 9) % 4
    var best := pos
    var best_score := -1000000
    var home: Vector2i = world.capitals[int(person["nation"])]
    for index in range(4):
        var candidate: Vector2i = pos + dirs[(index + offset) % 4]
        if not world.is_walkable(candidate.x, candidate.y):
            continue
        var score := -index
        if goal == GOAL_SAFE:
            score -= 100 if danger_near(world, candidate) else 0
            score += 30 if world.at(candidate.x, candidate.y) == world.MEADOW else 0
        elif goal == GOAL_SETTLEMENT and home.x >= 0:
            score -= candidate.distance_squared_to(home)
        elif goal == GOAL_SOCIAL and home.x >= 0:
            score -= candidate.distance_squared_to(home)
        else:
            # Each citizen has a different deterministic preferred direction.
            score += 5 if ((index + offset) % 4) == int(person["id"]) % 4 else 0
        if score > best_score:
            best_score = score
            best = candidate
    person["x"] = best.x
    person["y"] = best.y
    if goal == GOAL_SOCIAL:
        needs["social"] = maxi(0, int(needs["social"]) - 2)
    elif goal == GOAL_SAFE and not danger_near(world, best):
        needs["safety"] = maxi(0, int(needs["safety"]) - 5)

static func validate_state(data: Variant, seed: int, id: int, tick: int) -> Dictionary:
    var safe := create_state(seed, id, tick)
    if typeof(data) != TYPE_DICTIONARY:
        return safe
    var incoming: Dictionary = data
    for key in safe["personality"].keys():
        safe["personality"][key] = clampi(int(incoming.get("personality", {}).get(key, safe["personality"][key])), 0, 100)
    for key in safe["needs"].keys():
        safe["needs"][key] = clampi(int(incoming.get("needs", {}).get(key, 0)), 0, 100)
    var goal: String = str(incoming.get("goal", GOAL_EXPLORE))
    if goal in [GOAL_EXPLORE, GOAL_REST, GOAL_SOCIAL, GOAL_SAFE, GOAL_SETTLEMENT]:
        safe["goal"] = goal
    safe["last_decision"] = clampi(int(incoming.get("last_decision", tick)), 0, tick)
    safe["last_needs_tick"] = clampi(int(incoming.get("last_needs_tick", tick)), 0, tick)
    var dc = incoming.get("danger_cell", [-1, -1])
    if dc is Array and dc.size() == 2:
        safe["danger_cell"] = [int(dc[0]), int(dc[1])]
    var memories = incoming.get("memories", [])
    if memories is Array:
        for record in memories.slice(maxi(0, memories.size() - MAX_MEMORIES)):
            if record is Dictionary and record.get("cell", null) is Array and record["cell"].size() == 2:
                safe["memories"].append({
                    "kind": str(record.get("kind", "")).substr(0, 32),
                    "cell": [int(record["cell"][0]), int(record["cell"][1])],
                    "tick": clampi(int(record.get("tick", 0)), 0, tick)
                })
    return safe
