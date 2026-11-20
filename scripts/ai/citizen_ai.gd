extends RefCounted
class_name CitizenAI
const THREAT_EVENTS := ["danger", "damage", "witness_damage"]
const POSITIVE_EVENTS := ["healed", "support", "friendly", "discovery"]
const NEGATIVE_EVENTS := ["damage", "danger", "witness_damage"]
const DISCOVERY_GOALS := ["explore", "investigate", "seek_settlement", "return_familiar"]

# All authoritative cognition uses integer simulated time, stable IDs and bounded data.
const Emotions = preload("res://scripts/ai/emotions.gd")
const Memory = preload("res://scripts/ai/memory.gd")
const Relations = preload("res://scripts/ai/relationships.gd")
const Perception = preload("res://scripts/ai/perception.gd")
const Decisions = preload("res://scripts/ai/decision_engine.gd")
const Learning = preload("res://scripts/ai/learning.gd")
const Nav = preload("res://scripts/ai/navigation.gd")
const Persistence = preload("res://scripts/ai/persistence.gd")
const GOAL_EXPLORE := "explore"
const GOAL_REST := "rest"
const GOAL_SOCIAL := "socialize"
const GOAL_SAFE := "seek_safety"
const GOAL_SETTLEMENT := "seek_settlement"
const MAX_MEMORIES := Memory.CAPACITY

static func trait_value(world_seed: int, person_id: int, salt: int) -> int:
    var value := posmod(world_seed, 1000003)
    value = posmod(value * 37 + person_id * 1009 + salt * 7919, 1000003)
    value = posmod(value * 103 + 17011, 1000003)
    return int(value % 101)

static func create_state(world_seed: int, person_id: int, tick: int) -> Dictionary:
    var traits := {"curiosity": trait_value(world_seed, person_id, 1),
        "sociability": trait_value(world_seed, person_id, 2),
        "diligence": trait_value(world_seed, person_id, 3),
        "aggression": trait_value(world_seed, person_id, 4),
        "caution": trait_value(world_seed, person_id, 5)}
    return {"risk_revision": 0, "id": person_id, "personality": traits, "needs": {"fatigue": 0, "social": 0, "safety": 0},
        "emotions": Emotions.create(traits), "memories": [], "relationships": [],
        "beliefs": [], "learned": Learning.create(), "goal": GOAL_EXPLORE,
        "target": [-1, -1], "target_id": 0, "route": [], "utilities": [], "utility_rows": PackedInt32Array(),
        "last_decision": tick, "next_decision": tick + person_id % 12,
        "last_needs_tick": tick, "last_emotion_tick": tick, "last_memory_tick": tick,
        "last_social_decay": tick, "last_belief_tick": tick, "last_learning_tick": tick,
        "commit_until": tick, "next_path_tick": tick, "next_social_tick": tick,
        "last_hazard_tick": maxi(0, tick - 60), "danger_cell": [-1, -1],
        "last_outcome_tick": tick, "blocked_steps": 0}

static func advance_needs(state: Dictionary, tick: int) -> void:
    var previous: int = state["last_needs_tick"]
    state["last_needs_tick"] = tick
    var needs: Dictionary = state["needs"]
    needs["fatigue"] = clampi(int(needs["fatigue"]) + tick / 12 - previous / 12, 0, 100)
    needs["social"] = clampi(int(needs["social"]) + tick / 18 - previous / 18, 0, 100)
    needs["safety"] = maxi(0, int(needs["safety"]) - (tick / 6 - previous / 6))

static func danger_near(world: RefCounted, cell: Vector2i) -> bool:
    return Nav.danger_near(world, cell)

static func remember(state: Dictionary, kind: String, cell: Vector2i, tick: int) -> void:
    Memory.remember(state, kind, cell, tick)

static func event(world: RefCounted, person: Dictionary, kind: String, cell: Vector2i,
        strength: int = 30, actor_id: int = 0) -> void:
    if int(person["hp"]) <= 0 and kind != "damage":
        return
    if actor_id > 0:
        var actor: Dictionary = world.ai_context.people.get(actor_id, {})
        var observer := Vector2i(person["x"], person["y"])
        if actor.is_empty() or not Perception.visible(world, observer, Vector2i(actor["x"], actor["y"])):
            actor_id = 0
    var state: Dictionary = world.citizen_ai_by_id[str(person["id"])]
    world.ai_context.risk_maps.erase(int(person["id"]))
    if kind in THREAT_EVENTS:
        Perception.observe(state, cell, world.at(cell.x, cell.y), world.tick)
    Emotions.react(state, kind, strength, world.tick)
    var positive: bool = kind in POSITIVE_EVENTS
    Memory.remember(state, kind, cell, world.tick, [actor_id] if actor_id > 0 else [],
        strength, strength if positive else -strength, mini(100, strength + 30))
    if kind in NEGATIVE_EVENTS:
        state["needs"]["safety"] = mini(100, int(state["needs"]["safety"]) + strength)
        state["danger_cell"] = [cell.x, cell.y]
        state["last_hazard_tick"] = int(world.tick)
        state["next_decision"] = int(world.tick)
        state["route"] = []
        Learning.reinforce(state, state["goal"], -maxi(3, strength / 4))
    # Identity can only be supplied by a mechanic with a witnessed, identified actor.
    if actor_id > 0 and actor_id != int(person["id"]):
        Relations.encounter(state, actor_id, cell, world.tick, kind)

static func sense(world: RefCounted, person: Dictionary, state: Dictionary) -> Dictionary:
    var pos := Vector2i(person["x"], person["y"])
    var index := Perception.belief_index(state)
    var key := pos.x + pos.y * 96
    var first_visit: bool = not index.has(key) or int(index[key]["visits"]) == 0
    var view: Dictionary = world.ai_context.view(world, pos)
    Perception.observe(state, pos, int(view["terrain"]), world.tick, true, index, false)
    for cell in view["observed"]:
        Perception.observe(state, cell, int(view["observed"][cell]), world.tick, false, index, false)
    var hazard := Vector2i(-1, -1)
    for cell in view["hazards"]:
        Perception.observe(state, cell, world.ASH, world.tick, false, index, false)
        hazard = cell
    Perception.finish_observation(state, index)
    if not world.is_walkable(pos.x, pos.y):
        hazard = pos
    if hazard.x >= 0 and (state["danger_cell"] != [hazard.x, hazard.y] or int(world.tick) - int(state["last_hazard_tick"]) >= 30):
        event(world, person, "danger", hazard, 35)
    if first_visit and not Nav.danger_near(world, pos) and int(world.tick) - int(state["last_outcome_tick"]) >= 30 and state["goal"] in DISCOVERY_GOALS:
        Learning.reinforce(state, state["goal"], 3)
        Memory.remember(state, "discovery", pos, world.tick, [], 12, 15, 20)
        Emotions.react(state, "discovery", 8, world.tick)
        state["last_outcome_tick"] = int(world.tick)

    return index

static func interact(world: RefCounted, person: Dictionary, other: Dictionary) -> bool:
    if int(person["id"]) == int(other["id"]) or int(person["hp"]) <= 0 or int(other["hp"]) <= 0:
        return false
    var pos := Vector2i(person["x"], person["y"])
    var other_pos := Vector2i(other["x"], other["y"])
    if Nav.manhattan(pos, other_pos) > 1 or not Perception.visible(world, pos, other_pos) or Nav.danger_near(world, pos) or Nav.danger_near(world, other_pos):
        return false
    var a: Dictionary = world.citizen_ai_by_id[str(person["id"])]
    var b: Dictionary = world.citizen_ai_by_id[str(other["id"])]
    if int(world.tick) < int(a["next_social_tick"]) or int(world.tick) < int(b["next_social_tick"]):
        return false
    var old := Relations.find(a, int(other["id"]))
    var grievance: int = 0 if old.is_empty() else int(old["rivalry"])
    var hostile: bool = (int(a["emotions"]["anger"]) > 40 and int(a["personality"]["aggression"]) > 55) or (grievance > 45 and int(a["emotions"]["stress"]) > 30)
    var kind := "conflict" if hostile else "friendly"
    # A calm social partner can actually soothe distress; this creates earned, directional trust.
    var support_a: bool = not hostile and int(a["emotions"]["stress"]) > 25 and int(b["emotions"]["stress"]) < 25 and int(b["personality"]["sociability"]) > 40
    var support_b: bool = not hostile and int(b["emotions"]["stress"]) > 25 and int(a["emotions"]["stress"]) < 25 and int(a["personality"]["sociability"]) > 40
    var kind_a := "support" if support_a else kind
    var kind_b := "support" if support_b else kind
    Relations.encounter(a, int(other["id"]), other_pos, world.tick, kind_a)
    Relations.encounter(b, int(person["id"]), pos, world.tick, kind_b)
    Emotions.react(a, kind_a, 14, world.tick)
    Emotions.react(b, kind_b, 14, world.tick)
    Memory.remember(a, kind_a, pos, world.tick, [int(other["id"])], 20, -20 if hostile else 20, 35)
    Memory.remember(b, kind_b, other_pos, world.tick, [int(person["id"])], 20, -20 if hostile else 20, 35)
    for state in [a, b]:
        state["needs"]["social"] = maxi(0, int(state["needs"]["social"]) - (3 if hostile else 22))
        state["next_social_tick"] = int(world.tick) + 30 + (100 - int(state["personality"]["sociability"])) / 5
        Learning.reinforce(state, GOAL_SOCIAL, -7 if hostile else 4)
    if not hostile:
        Perception.share(a, b, int(person["id"]), int(Relations.find(b, int(person["id"]))["trust"]), world.tick)
        Perception.share(b, a, int(other["id"]), int(Relations.find(a, int(other["id"]))["trust"]), world.tick)
    world.ai_context.metrics["interactions"] += 1
    return true

static func step(world: RefCounted, person: Dictionary, state: Dictionary, scheduled: bool = false) -> void:
    advance_needs(state, world.tick)
    Emotions.advance(state, world.tick)
    Memory.advance(state, world.tick)
    Relations.advance(state, world.tick)
    Perception.advance(state, world.tick)
    Learning.advance(state, world.tick)
    var pos := Vector2i(person["x"], person["y"])
    # Infants require being carried by a guardian; they never walk on their own.
    if str(person.get("life_stage", "adult")) == "infant":
        return
    var urgent: bool = Nav.danger_near(world, pos) or not world.is_walkable(pos.x, pos.y)
    # Young dependents cannot perform adult construction jobs. Their safety
    # responses remain active during hazards.
    if not urgent and world.lifecycle.dependent_step(world, person, state):
        return
    # An expectant adult must travel to shelter and give birth in real time;
    # danger avoidance always takes precedence over this movement.
    if not urgent and world.demography.delivery_step(world, person, state):
        return
    # Guardians perform actual travel and childcare before ordinary labour.
    if not urgent and world.households.care_step(world, person, state):
        return
    # Food collection and survival take priority over optional construction.
    if not urgent and world.food.work_step(world, person, state):
        return
    # Work is a physical commitment, interrupted by immediate danger.
    if not urgent and world.construction.work_step(world, person, state):
        return
    var think: bool = int(world.tick) >= int(state["next_decision"]) or (urgent and state["goal"] != GOAL_SAFE)
    if think and scheduled and not urgent and not world.ai_context.routine_grants.has(int(person["id"])):
        world.ai_context.metrics["deferred_decisions"] += 1
        think = false
    if think:
        world.ai_context.metrics["urgent_decisions" if urgent else "routine_decisions"] += 1
        var index := sense(world, person, state)
        var nearby: Array = world.ai_context.nearby(world, person)
        Decisions.choose(world, person, state, nearby, urgent, index, false)
        if not urgent and int(world.tick) >= int(state["next_social_tick"]):
            var preferred: Dictionary = {}
            var preference := -100000
            for other in nearby:
                var other_state: Dictionary = world.citizen_ai_by_id[str(other["id"])]
                if int(other_state["next_social_tick"]) > int(world.tick) or Nav.manhattan(pos, Vector2i(other["x"], other["y"])) > 1:
                    continue
                var tie := Relations.find(state, int(other["id"]))
                var score := 0 if tie.is_empty() else Relations.preference(tie)
                if score < -20:
                    continue
                if score > preference or (score == preference and (preferred.is_empty() or int(other["id"]) < int(preferred["id"]))):
                    preference = score
                    preferred = other
            if not preferred.is_empty():
                interact(world, person, preferred)
    if state["goal"] == GOAL_REST and not urgent:
        var previous: int = state["needs"]["fatigue"]
        state["needs"]["fatigue"] = maxi(0, previous - 5)
        if previous >= 25 and int(state["needs"]["fatigue"]) < 25:
            Learning.reinforce(state, GOAL_REST, 3)
            state["next_decision"] = int(world.tick)
        return
    var target := Vector2i(state["target"][0], state["target"][1])
    if target.x < 0:
        return
    var next := Nav.next_step(world, person, state, target)
    if next == pos and pos != target:
        state["blocked_steps"] = mini(100, int(state["blocked_steps"]) + 1)
        if int(state["blocked_steps"]) >= 4:
            state["target"] = [pos.x, pos.y]
            state["route"] = []
            state["next_decision"] = int(world.tick) + 3
            state["commit_until"] = int(world.tick)
            state["blocked_steps"] = 0
            if int(world.tick) - int(state["last_outcome_tick"]) >= 30:
                Learning.reinforce(state, state["goal"], -4)
                Emotions.react(state, "failure", 8, world.tick)
                state["last_outcome_tick"] = int(world.tick)
    else:
        state["blocked_steps"] = 0
    person["x"] = next.x
    person["y"] = next.y
    world.ai_context.moved(person, pos)
    if next == target:
        state["next_decision"] = mini(int(state["next_decision"]), int(world.tick) + 6)

static func validate_state(data: Variant, seed: int, id: int, tick: int) -> Dictionary:
    return Persistence.restore(data, create_state(seed, id, tick), tick)

static func inspect(state: Dictionary) -> Dictionary:
    return {"goal": state["goal"], "target": state["target"], "emotions": state["emotions"],
        "utilities": Decisions.describe(state["utility_rows"]) if not state["utility_rows"].is_empty() else state["utilities"], "relationships": state["relationships"],
        "memories": state["memories"], "beliefs": state["beliefs"], "learned": state["learned"]}.duplicate(true)
