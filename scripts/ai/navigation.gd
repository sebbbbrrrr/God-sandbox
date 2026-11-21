extends RefCounted
const THREAT_EVENTS := ["damage", "danger", "witness_damage"]

const Memory = preload("res://scripts/ai/memory.gd")
const DIRS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
const MAX_NODES := 64
const MAX_ROUTE := 12

static func danger_near(world: RefCounted, cell: Vector2i) -> bool:
    var context: RefCounted = world.ai_context
    if context.terrain_tick != int(world.tick) or context.terrain_dirty:
        context.refresh_terrain(world)
    if cell.x < 0 or cell.y < 0 or cell.x >= world.WIDTH or cell.y >= world.HEIGHT:
        return false
    return context.hazard_mask[cell.y * int(world.WIDTH) + cell.x] != 0

static func hazard_cost(world: RefCounted, state: Dictionary, cell: Vector2i) -> int:
    var maps: Dictionary = world.ai_context.risk_maps
    var id: int = state["id"]
    var revision: int = state.get("risk_revision", 0)
    if not maps.has(id) or int(world.ai_context.risk_revisions.get(id, -1)) != revision:
        var costs: Dictionary = {}
        for record in state["memories"]:
            if record["kind"] not in THREAT_EVENTS:
                continue
            var center := Vector2i(record["cell"][0], record["cell"][1])
            for dy in range(-2, 3):
                for dx in range(-2, 3):
                    var distance := absi(dx) + absi(dy)
                    if distance > 2:
                        continue
                    var point := center + Vector2i(dx, dy)
                    var risk: int = int(record["importance"]) * int(record["confidence"]) / (100 * (distance + 1))
                    costs[point] = maxi(int(costs.get(point, 0)), risk)
        for fact in state["beliefs"]:
            if int(fact["terrain"]) != 5:
                continue
            var center := Vector2i(fact["cell"][0], fact["cell"][1])
            for dy in range(-1, 2):
                for dx in range(-1, 2):
                    var point := center + Vector2i(dx, dy)
                    costs[point] = maxi(int(costs.get(point, 0)), int(fact["confidence"]) * 2)
        maps[id] = costs
        world.ai_context.risk_revisions[id] = revision
    # Route preference uses beliefs and episodes, never unseen distant fire tiles.
    return int(maps[id].get(cell, 0))

static func plan(world: RefCounted, state: Dictionary, start: Vector2i, target: Vector2i) -> Array:
    var context: RefCounted = world.ai_context
    if int(context.metrics["path_requests"]) >= context.MAX_PATH_REQUESTS:
        return []
    context.metrics["path_requests"] += 1
    # Bounded A*: partial routes are allowed, with deterministic insertion-order ties.
    var open: Array[Vector2i] = [start]
    var parents := {}
    var costs := {start: 0}
    var visited := {}
    var best := start
    var expanded := 0
    while not open.is_empty() and expanded < MAX_NODES:
        var chosen := 0
        var best_score := 2147483647
        for i in range(open.size()):
            var cell: Vector2i = open[i]
            var score: int = int(costs[cell]) + manhattan(cell, target) * 10
            if score < best_score:
                best_score = score
                chosen = i
        var current: Vector2i = open[chosen]
        open.remove_at(chosen)
        if visited.has(current):
            continue
        visited[current] = true
        expanded += 1
        if manhattan(current, target) < manhattan(best, target):
            best = current
        if current == target:
            best = current
            break
        for direction in DIRS:
            var next: Vector2i = current + direction
            if not world.is_walkable(next.x, next.y) or visited.has(next) or manhattan(start, next) > MAX_ROUTE:
                continue
            var cost: int = int(costs[current]) + world.regional_economy.road_cost(world, next) + hazard_cost(world, state, next)
            if not costs.has(next) or cost < int(costs[next]):
                costs[next] = cost
                parents[next] = current
                open.append(next)
    context.metrics["path_nodes"] += expanded
    var route: Array = []
    while best != start and parents.has(best):
        route.push_front([best.x, best.y])
        best = parents[best]
    return route.slice(0, MAX_ROUTE)

static func manhattan(a: Vector2i, b: Vector2i) -> int:
    return absi(a.x - b.x) + absi(a.y - b.y)

# Capped bucket sampling prevents O(population^2) scans at busy hubs.
static func _occupants(world: RefCounted, cell: Vector2i, self_id: int) -> int:
    var amount: int = int(world.ai_context.cell_counts.get(cell, 0))
    var actor: Dictionary = world.ai_context.people.get(self_id, {})
    if not actor.is_empty() and int(actor["x"]) == cell.x and int(actor["y"]) == cell.y:
        amount -= 1
    return maxi(0, amount)

# Choose adjacent contact for physical inventory/food transfers. If all four
# counters are packed, route new arrivals to nearby staging cells instead of
# putting dozens of sprites on one tile. Waiting is real walking, not teleport.
static func hub_access(world: RefCounted, person: Dictionary, hub: Vector2i) -> Vector2i:
    var origin := Vector2i(int(person["x"]), int(person["y"]))
    if manhattan(origin, hub) <= 1:
        return origin
    var self_id: int = int(person["id"])
    var best := hub
    var best_score := 2147483647
    var minimum_occupied := 2147483647
    var offset: int = posmod(self_id * 7, DIRS.size())
    for i in range(DIRS.size()):
        var candidate: Vector2i = hub + DIRS[(i + offset) % DIRS.size()]
        if not world.is_walkable(candidate.x, candidate.y) or danger_near(world, candidate):
            continue
        var occupied: int = _occupants(world, candidate, self_id)
        minimum_occupied = mini(minimum_occupied, occupied)
        var score: int = manhattan(origin, candidate) * 3 + occupied * 12 + i
        if score < best_score:
            best_score = score
            best = candidate
    if minimum_occupied < 2:
        return best
    var staging := Vector2i(-1, -1)
    var staging_score := 2147483647
    for radius in range(2, 5):
        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                if absi(dx) + absi(dy) != radius:
                    continue
                var candidate := hub + Vector2i(dx, dy)
                if not world.is_walkable(candidate.x, candidate.y) or danger_near(world, candidate):
                    continue
                var occupied: int = _occupants(world, candidate, self_id)
                var score: int = manhattan(origin, candidate) * 3 + occupied * 22
                # Keep a citizen stable at their waiting point until a
                # contact position becomes free instead of oscillating.
                if candidate == origin:
                    score -= 25
                score += posmod(dx * 7 + dy * 11 + self_id, 7)
                if score < staging_score:
                    staging_score = score
                    staging = candidate
        if staging.x >= 0 and staging_score <= 25:
            break
    return staging if staging.x >= 0 else best

static func next_step(world: RefCounted, person: Dictionary, state: Dictionary, target: Vector2i) -> Vector2i:
    var pos := Vector2i(person["x"], person["y"])
    if pos == target:
        state["route"] = []
        return pos
    var route: Array = state["route"]
    if not route.is_empty():
        var next := Vector2i(route[0][0], route[0][1])
        # Revalidate at execution time, including direct brush writes that have no notification hook.
        if manhattan(pos, next) != 1 or not world.is_walkable(next.x, next.y) or danger_near(world, next):
            route.clear()
    if route.is_empty() and int(world.tick) >= int(state["next_path_tick"]):
        if int(world.ai_context.metrics["path_requests"]) < world.ai_context.MAX_PATH_REQUESTS:
            route = plan(world, state, pos, target)
        state["route"] = route
        state["next_path_tick"] = int(world.tick) + 9
    if not route.is_empty():
        var next := Vector2i(route[0][0], route[0][1])
        if world.is_walkable(next.x, next.y) and (not danger_near(world, next) or danger_near(world, pos)):
            route.pop_front()
            return next
        route.clear()
    # Safe bounded fallback when a route is blocked or the shared path budget is spent.
    var best := pos
    var score: int = manhattan(pos, target) * 10 + hazard_cost(world, state, pos)
    for direction in DIRS:
        var cell: Vector2i = pos + direction
        if not world.is_walkable(cell.x, cell.y):
            continue
        var value: int = manhattan(cell, target) * 10 + hazard_cost(world, state, cell)
        if value < score or (not world.is_walkable(pos.x, pos.y) and best == pos):
            score = value
            best = cell
    return best
