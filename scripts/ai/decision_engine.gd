extends RefCounted
const BLOCKED_TERRAIN := [0, 4]
const UNSAFE_TERRAIN := [0, 4, 5]
const INTERESTING_TERRAIN := [3, 6]

const GOALS := ["explore", "rest", "seek_safety", "avoid_danger", "socialize", "seek_settlement", "investigate", "return_familiar"]
const Nav = preload("res://scripts/ai/navigation.gd")
const Memory = preload("res://scripts/ai/memory.gd")
const Perception = preload("res://scripts/ai/perception.gd")
const Relations = preload("res://scripts/ai/relationships.gd")

static func candidate(goal: String, score: int, target: Vector2i, target_id: int = 0) -> Array:
    return [GOALS.find(goal), score, target.x, target.y, target_id]

static func choose(world: RefCounted, person: Dictionary, state: Dictionary, nearby: Array, urgent: bool, known_index: Variant = null, diagnostics: bool = true) -> void:
    var pos := Vector2i(person["x"], person["y"])
    var traits: Dictionary = state["personality"]
    var emotions: Dictionary = state["emotions"]
    var needs: Dictionary = state["needs"]
    var options: Array = []
    var horizon := pos
    var horizon_score := -100000
    var refuge := pos
    var refuge_score := 100000
    var unfamiliar := Vector2i(-1, -1)
    var familiar := Vector2i(-1, -1)
    var settlement := Vector2i(-1, -1)
    var familiar_score := -100000
    var settlement_score := 100000
    var unfamiliar_score := -100000
    var offset: int = (int(person["id"]) + int(world.tick) / 90) % 8
    var view: Dictionary = world.ai_context.view(world, pos)
    var index: Dictionary = Perception.belief_index(state) if known_index == null else known_index
    for j in range(8):
        var cell: Vector2i = pos + Perception.RAYS[(j + offset) % 8]
        if not view["observed"].has(cell) or int(view["observed"][cell]) in BLOCKED_TERRAIN:
            continue
        var risk: int = Nav.hazard_cost(world, state, cell)
        var known: int = int(index[cell.x + cell.y * 96]["visits"]) if index.has(cell.x + cell.y * 96) else 0
        var score: int = 30 - known * 3 - risk - j
        if score > horizon_score:
            horizon_score = score
            horizon = cell
        if risk < refuge_score:
            refuge_score = risk
            refuge = cell
    if urgent or horizon == pos:
        # A one-tile refuge remains usable even on a small edited island or narrow corridor.
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                var cell := pos + Vector2i(dx, dy)
                if cell == pos or not world.is_walkable(cell.x, cell.y) or not world.ai_context.visible(world, pos, cell):
                    continue
                var risk: int = Nav.hazard_cost(world, state, cell)
                if risk < refuge_score:
                    refuge_score = risk
                    refuge = cell
                if horizon == pos:
                    horizon = cell
    for fact in state["beliefs"]:
        if int(fact["confidence"]) < 20 or int(fact["terrain"]) in UNSAFE_TERRAIN:
            continue
        var cell := Vector2i(fact["cell"][0], fact["cell"][1])
        var distance := Nav.manhattan(pos, cell)
        var risk := Nav.hazard_cost(world, state, cell)
        if int(fact["visits"]) > 1 and distance > 1:
            var score: int = int(fact["visits"]) + int(fact["confidence"]) / 10 - distance * 2 - risk
            if score > familiar_score:
                familiar_score = score
                familiar = cell
        if int(fact["terrain"]) == 6 and distance > 0:
            var score: int = distance * 2 + risk - int(fact["confidence"]) / 10
            if score < settlement_score:
                settlement_score = score
                settlement = cell
        if int(fact["visits"]) == 0 and distance > 0:
            var score: int = 20 - distance - risk + (8 if int(fact["terrain"]) in INTERESTING_TERRAIN else 0)
            if score > unfamiliar_score:
                unfamiliar_score = score
                unfamiliar = cell
    options.append(candidate("explore", 35 + int(traits["curiosity"]) / 2 + int(emotions["confidence"]) / 5 - int(emotions["fear"]) / 2, horizon))
    options.append(candidate("rest", int(needs["fatigue"]) * 2 + int(emotions["stress"]) / 4 - (180 if urgent else 0), pos))
    if urgent:
        options.append(candidate("seek_safety", 1000, refuge))
    elif Memory.risk(state, pos) >= 15:
        options.append(candidate("avoid_danger", 150 + int(traits["caution"]) / 2, refuge))
    if unfamiliar.x >= 0:
        options.append(candidate("investigate", 30 + int(traits["curiosity"]) / 2 + unfamiliar_score / 2 - int(emotions["fear"]), unfamiliar))
    if familiar.x >= 0:
        options.append(candidate("return_familiar", 10 + int(emotions["fear"]) + int(emotions["stress"]) / 2 + int(traits["caution"]) / 3, familiar))
    if settlement.x >= 0:
        options.append(candidate("seek_settlement", 25 + (100 - int(traits["curiosity"])) / 2 + int(needs["social"]) / 3 - maxi(0, settlement_score), settlement))
    var partner := 0
    var partner_cell := Vector2i(-1, -1)
    var partner_score := -100000
    var disliked := Vector2i(-1, -1)
    for other in nearby:
        var tie := Relations.find(state, int(other["id"]))
        var preference := 0 if tie.is_empty() else Relations.preference(tie)
        var other_cell := Vector2i(other["x"], other["y"])
        if preference < -20:
            disliked = other_cell
            continue
        var score: int = preference - Nav.manhattan(pos, other_cell) * 4
        if score > partner_score or (score == partner_score and int(other["id"]) < partner):
            partner_score = score
            partner = int(other["id"])
            partner_cell = other_cell
    # Familiar people have remembered positions, never live global tracking.
    for tie in state["relationships"]:
        var preference := Relations.preference(tie)
        if int(world.tick) - int(tie["last_tick"]) > 300 or preference <= 10:
            continue
        var cell := Vector2i(tie["last_cell"][0], tie["last_cell"][1])
        var score: int = preference - Nav.manhattan(pos, cell) * 4 - (int(world.tick) - int(tie["last_tick"])) / 12
        if score > partner_score:
            partner_score = score
            partner = int(tie["id"])
            partner_cell = cell
    if partner > 0:
        options.append(candidate("socialize", int(needs["social"]) + int(traits["sociability"]) / 3 + partner_score / 5 + int(emotions["social_attachment"]) / 4 - int(emotions["anger"]) / 2, partner_cell, partner))
    if disliked.x >= 0:
        var away := pos
        var distance := -1
        for direction in Nav.DIRS:
            var cell: Vector2i = pos + direction * 3
            if world.is_walkable(cell.x, cell.y) and not Nav.danger_near(world, cell) and Nav.manhattan(cell, disliked) > distance:
                distance = Nav.manhattan(cell, disliked)
                away = cell
        options.append(candidate("avoid_danger", 180, away))
    var best: Array = options[0]
    for option in options:
        option[1] += int(state["learned"].get(GOALS[option[0]], 0))
        if GOALS[option[0]] == state["goal"]:
            option[1] += 18 + (12 if int(world.tick) < int(state["commit_until"]) else 0)
        if int(option[1]) > int(best[1]):
            best = option
    var trace := PackedInt32Array()
    trace.resize(options.size() * 5)
    var cursor := 0
    for option in options:
        for value in option:
            trace[cursor] = value
            cursor += 1
    state["utility_rows"] = trace
    state["utilities"] = describe(trace) if diagnostics else []
    var old_target := Vector2i(state["target"][0], state["target"][1])
    var invalid_target: bool = not world.is_walkable(old_target.x, old_target.y)
    var reached: bool = state["target"] == [pos.x, pos.y]
    if GOALS[best[0]] != state["goal"] or reached or int(world.tick) >= int(state["commit_until"]) or urgent or invalid_target:
        if (int(state["target"][0]) != int(best[2]) or int(state["target"][1]) != int(best[3])) or state["goal"] != GOALS[best[0]]:
            state["route"] = []
        state["goal"] = GOALS[best[0]]
        state["target"] = [best[2], best[3]]
        state["target_id"] = best[4]
        state["commit_until"] = int(world.tick) + 36
    state["last_decision"] = int(world.tick)
    state["next_decision"] = int(world.tick) + 12 + int(person["id"]) % 4 * 3
    world.ai_context.metrics["decisions"] += 1

static func describe(rows: PackedInt32Array) -> Array:
    var result: Array = []
    for i in range(0, rows.size(), 5):
        result.append({"goal":GOALS[rows[i]], "score":rows[i + 1], "target":[rows[i + 2], rows[i + 3]], "target_id":rows[i + 4]})
    return result
