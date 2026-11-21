extends RefCounted
const SALIENT_TERRAIN := [5, 6]

const BELIEF_CAPACITY := 16
const RADIUS := 4
const BUCKET_SIZE := 4
const MAX_CANDIDATES := 32
const MAX_NEARBY := 8
const MAX_PATH_REQUESTS := 12
const RAYS := [Vector2i(4, 0), Vector2i(3, 3), Vector2i(0, 4), Vector2i(-3, 3), Vector2i(-4, 0), Vector2i(-3, -3), Vector2i(0, -4), Vector2i(3, -3)]

var buckets: Dictionary = {}
var cell_counts: Dictionary = {} # tick-local occupancy; maintained on every real move
var people: Dictionary = {}
var risk_maps: Dictionary = {}
var risk_revisions: Dictionary = {}
var minds: Dictionary = {}
var update_slots: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
var id_to_index: Dictionary = {}
var routine_grants: Dictionary = {}
var routine_budget := 96
var registry_count := -1
var registry_next_id := -1
var terrain_revision := 0
var terrain_tick := -1
var terrain_dirty := true
var terrain_source := PackedByteArray()
var hazard_mask := PackedByteArray()
var local_views: Dictionary = {}
var metrics := {"decisions": 0, "social_candidates": 0, "path_requests": 0, "path_nodes": 0, "interactions": 0, "routine_decisions": 0, "deferred_decisions": 0, "urgent_decisions": 0}

func begin_tick(world: RefCounted) -> void:
    buckets.clear()
    cell_counts.clear()
    # Derived risk maps survive until the corresponding knowledge revision changes.
    refresh_terrain(world)
    var rebuild: bool = registry_count != world.citizens.size() or registry_next_id != world.next_id
    if rebuild:
        people.clear()
        minds.clear()
        id_to_index.clear()
        for slot in range(3):
            update_slots[slot] = PackedInt32Array()
    registry_count = world.citizens.size()
    registry_next_id = world.next_id
    local_views.clear()
    for key in metrics:
        metrics[key] = 0
    # Canonical citizen order also guarantees that rebuilt caches replay after load.
    var index := -1
    var due: Array[Vector2i] = []
    routine_grants.clear()
    for person in world.citizens:
        index += 1
        var id: int = person["id"]
        if rebuild:
            people[id] = person
            minds[id] = world.citizen_ai_by_id[str(id)]
            id_to_index[id] = index
            update_slots[id % 3].append(id)
        if int(person["hp"]) <= 0:
            continue
        if (int(world.tick) + id) % 3 == 0 and int(minds[id]["next_decision"]) <= int(world.tick):
            due.append(Vector2i(int(minds[id]["next_decision"]), id))
        var key := bucket_of(Vector2i(person["x"], person["y"]))
        if not buckets.has(key):
            buckets[key] = []
        buckets[key].append(id)
        var cell := Vector2i(int(person["x"]), int(person["y"]))
        cell_counts[cell] = int(cell_counts.get(cell, 0)) + 1

    # Earliest deadline first, ID ties: count-based budget, no wall-clock branching and no starvation.
    due.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
    for i in range(mini(routine_budget, due.size())):
        routine_grants[due[i].y] = true

func added(person: Dictionary, mind: Dictionary = {}) -> void:
    registry_count = -1
    risk_maps.erase(int(person["id"]))
    risk_revisions.erase(int(person["id"]))
    if not mind.is_empty():
        minds[int(person["id"])] = mind
    people[int(person["id"])] = person
    var key := bucket_of(Vector2i(person["x"], person["y"]))
    if not buckets.has(key):
        buckets[key] = []
    buckets[key].append(int(person["id"]))
    var cell := Vector2i(int(person["x"]), int(person["y"]))
    cell_counts[cell] = int(cell_counts.get(cell, 0)) + 1

static func bucket_of(cell: Vector2i) -> int:
    return cell.x / BUCKET_SIZE + (cell.y / BUCKET_SIZE) * 24

func moved(person: Dictionary, old_cell: Vector2i) -> void:
    var current := Vector2i(person["x"], person["y"])
    if current == old_cell:
        return
    cell_counts[old_cell] = maxi(0, int(cell_counts.get(old_cell, 0)) - 1)
    cell_counts[current] = int(cell_counts.get(current, 0)) + 1
    var old_key := bucket_of(old_cell)
    var new_key := bucket_of(current)
    if old_key == new_key:
        return
    if buckets.has(old_key):
        buckets[old_key].erase(int(person["id"]))
    if not buckets.has(new_key):
        buckets[new_key] = []
    buckets[new_key].append(int(person["id"]))

func nearby(world: RefCounted, person: Dictionary) -> Array:
    var result: Array = []
    var cell := Vector2i(person["x"], person["y"])
    var bx := cell.x / BUCKET_SIZE
    var by := cell.y / BUCKET_SIZE
    var checked := 0
    # Rotate bucket and within-bucket sampling, so a crowded tile cannot monopolize encounters.
    var rotation: int = (int(person["id"]) + int(world.tick) / 30) % 9
    for j in range(9):
        var offset: int = (j + rotation) % 9
        var x: int = bx + offset % 3 - 1
        var y: int = by + offset / 3 - 1
        if x < 0 or y < 0 or x >= 24 or y >= 32:
            continue
        var key := x + y * 24
        var ids: Array = buckets.get(key, [])
        var count := mini(4, ids.size())
        for k in range(count):
            if checked >= MAX_CANDIDATES:
                return result
            checked += 1
            metrics["social_candidates"] += 1
            var id: int = ids[(k + int(person["id"]) + int(world.tick) / 30) % ids.size()]
            if id == int(person["id"]):
                continue
            var other: Dictionary = people[id]
            var target := Vector2i(other["x"], other["y"])
            if cell.distance_squared_to(target) <= RADIUS * RADIUS and visible(world, cell, target):
                result.append(other)
                if result.size() >= MAX_NEARBY:
                    return result
    return result

static func visible(world: RefCounted, start: Vector2i, finish: Vector2i) -> bool:
    var dx := absi(finish.x - start.x)
    var dy := absi(finish.y - start.y)
    var width: int = world.WIDTH
    var height: int = world.HEIGHT
    if maxi(dx, dy) > RADIUS or finish.x < 0 or finish.y < 0 or finish.x >= width or finish.y >= height:
        return false
    var terrain: PackedByteArray = world.terrain
    var sx := 1 if start.x < finish.x else -1
    var sy := 1 if start.y < finish.y else -1
    var error := dx - dy
    var point := start
    while point != finish:
        var twice := error * 2
        if twice > -dy:
            error -= dy
            point.x += sx
        if twice < dx:
            error += dx
            point.y += sy
        if point != finish and terrain[point.y * width + point.x] == 4:
            return false
    return true

func view(world: RefCounted, pos: Vector2i) -> Dictionary:
    if local_views.has(pos):
        return local_views[pos]
    var terrain: PackedByteArray = world.terrain
    var width: int = world.WIDTH
    var height: int = world.HEIGHT
    var observed := {}
    var hazards: Array[Vector2i] = []
    for ray in RAYS:
        var cell: Vector2i = pos + ray
        if visible(world, pos, cell):
            observed[cell] = int(terrain[cell.y * width + cell.x])
    for y in range(maxi(0, pos.y - 1), mini(height, pos.y + 2)):
        for x in range(maxi(0, pos.x - 1), mini(width, pos.x + 2)):
            if terrain[y * width + x] == 5:
                hazards.append(Vector2i(x, y))
    var result := {"observed": observed, "hazards": hazards, "terrain": int(terrain[pos.y * width + pos.x])}
    local_views[pos] = result
    return result

static func belief_index(state: Dictionary) -> Dictionary:
    var result := {}
    for fact in state["beliefs"]:
        result[int(fact["cell"][0]) + int(fact["cell"][1]) * 96] = fact
    return result

static func observe(state: Dictionary, cell: Vector2i, terrain_type: int, tick: int, visited: bool = false, index: Variant = null, trim: bool = true) -> bool:
    var old: Variant = null
    if index is Dictionary:
        old = index.get(cell.x + cell.y * 96)
    else:
        for fact in state["beliefs"]:
            if int(fact["cell"][0]) == cell.x and int(fact["cell"][1]) == cell.y:
                old = fact
                break
    if old != null:
        if int(old["terrain"]) == 5 or terrain_type == 5:
            state["risk_revision"] = int(state.get("risk_revision", 0)) + 1
        old["terrain"] = terrain_type
        old["confidence"] = 100
        old["source"] = "direct"
        old["source_id"] = 0
        old["hops"] = 0
        old["observed_at"] = tick
        old["updated_at"] = tick
        if visited:
            old["visits"] = mini(100, int(old["visits"]) + 1)
        return false
    # New records have exclusive ownership; learn() only copies externally shared information.
    var fact := {"cell": [cell.x, cell.y], "terrain": terrain_type,
        "confidence": 100, "source": "direct", "source_id": 0, "hops": 0,
        "observed_at": tick, "updated_at": tick, "visits": 1 if visited else 0}
    state["beliefs"].append(fact)
    state["risk_revision"] = int(state.get("risk_revision", 0)) + 1
    if index is Dictionary:
        index[cell.x + cell.y * 96] = fact
    if trim:
        trim_beliefs(state, index)
    return true

static func trim_beliefs(state: Dictionary, index: Variant = null) -> void:
    var beliefs: Array = state["beliefs"]
    while beliefs.size() > BELIEF_CAPACITY:
        var weakest := 0
        var weakest_score := belief_priority(beliefs[0])
        for i in range(1, beliefs.size()):
            var score := belief_priority(beliefs[i])
            if score < weakest_score:
                weakest_score = score
                weakest = i
        if index is Dictionary:
            index.erase(int(beliefs[weakest]["cell"][0]) + int(beliefs[weakest]["cell"][1]) * 96)
        beliefs.remove_at(weakest)
        state["risk_revision"] = int(state.get("risk_revision", 0)) + 1

static func learn(state: Dictionary, fact: Dictionary, index: Variant = null, trim: bool = true) -> bool:
    state["risk_revision"] = int(state.get("risk_revision", 0)) + 1
    var beliefs: Array = state["beliefs"]
    var location: int = int(fact["cell"][0]) + int(fact["cell"][1]) * 96
    var old: Dictionary = {}
    if index is Dictionary:
        old = index.get(location, {})
    else:
        for item in beliefs:
            if item["cell"] == fact["cell"]:
                old = item
                break
    if not old.is_empty():
        var visits: int = mini(100, int(old["visits"]) + int(fact["visits"]))
        if fact["source"] == "shared" and (int(old["observed_at"]) >= int(fact["observed_at"]) or int(old["confidence"]) > int(fact["confidence"])):
            return false
        old.merge(fact, true)
        old["visits"] = visits
        return false
    var copy: Dictionary = fact.duplicate(true)
    beliefs.append(copy)
    if index is Dictionary:
        index[location] = copy
    if trim and beliefs.size() > BELIEF_CAPACITY:
        var weakest := 0
        var weakest_score := belief_priority(beliefs[0])
        for i in range(1, beliefs.size()):
            var score := belief_priority(beliefs[i])
            if score < weakest_score:
                weakest_score = score
                weakest = i
        if index is Dictionary:
            var evicted: Dictionary = beliefs[weakest]
            index.erase(int(evicted["cell"][0]) + int(evicted["cell"][1]) * 96)
        beliefs.remove_at(weakest)
    return true

static func finish_observation(state: Dictionary, index: Variant = null) -> void:
    # One bounded batch has at most 16 + 9 + 9 records. Score each once, preserving stable tie order.
    var beliefs: Array = state["beliefs"]
    if beliefs.size() <= BELIEF_CAPACITY:
        return
    var scores: Array[int] = []
    for fact in beliefs:
        scores.append(belief_priority(fact))
    while beliefs.size() > BELIEF_CAPACITY:
        var weakest := 0
        for i in range(1, scores.size()):
            if scores[i] < scores[weakest]:
                weakest = i
        if index is Dictionary:
            index.erase(int(beliefs[weakest]["cell"][0]) + int(beliefs[weakest]["cell"][1]) * 96)
        beliefs.remove_at(weakest)
        scores.remove_at(weakest)
        state["risk_revision"] = int(state.get("risk_revision", 0)) + 1

static func belief_priority(fact: Dictionary) -> int:
    # Keep danger, settlements and repeatedly visited places longer than passing glimpses.
    return int(fact["updated_at"]) / 3 + int(fact["visits"]) * 4 + int(fact["confidence"]) + (60 if int(fact["terrain"]) in SALIENT_TERRAIN else 0)

static func share(sender: Dictionary, receiver: Dictionary, source_id: int, trust: int, tick: int) -> void:
    var chosen: Dictionary = {}
    for fact in sender["beliefs"]:
        if int(fact["hops"]) >= 2 or int(fact["confidence"]) < 35 or int(fact["terrain"]) not in SALIENT_TERRAIN:
            continue
        if chosen.is_empty() or belief_priority(fact) > belief_priority(chosen):
            chosen = fact
    if chosen.is_empty():
        return
    var copy: Dictionary = chosen.duplicate(true)
    copy["source"] = "shared"
    copy["source_id"] = source_id
    copy["hops"] = int(copy["hops"]) + 1
    copy["confidence"] = mini(int(copy["confidence"]), 30 + trust / 2) - 10
    copy["updated_at"] = tick
    copy["visits"] = 0
    learn(receiver, copy)

static func advance(state: Dictionary, tick: int) -> void:
    var units: int = tick / 120 - int(state["last_belief_tick"]) / 120
    state["last_belief_tick"] = tick
    if units <= 0:
        return
    state["risk_revision"] = int(state.get("risk_revision", 0)) + 1
    var beliefs: Array = state["beliefs"]
    for i in range(beliefs.size() - 1, -1, -1):
        beliefs[i]["confidence"] = maxi(0, int(beliefs[i]["confidence"]) - units * (4 if beliefs[i]["source"] == "shared" else 2))
        if int(beliefs[i]["confidence"]) == 0:
            beliefs.remove_at(i)

func refresh_terrain(world: RefCounted) -> void:
    terrain_tick = int(world.tick)
    if not terrain_dirty and terrain_source == world.terrain:
        return
    terrain_dirty = false
    if terrain_source == world.terrain and not hazard_mask.is_empty():
        return
    terrain_revision += 1
    # A detached packed snapshot detects legacy direct writes through native byte equality.
    terrain_source = world.terrain.duplicate()
    var width: int = world.WIDTH
    var height: int = world.HEIGHT
    hazard_mask.resize(width * height)
    hazard_mask.fill(0)
    for i in range(terrain_source.size()):
        if terrain_source[i] != 5:
            continue
        var cx := i % width
        var cy := i / width
        for y in range(maxi(0, cy - 1), mini(height, cy + 2)):
            for x in range(maxi(0, cx - 1), mini(width, cx + 2)):
                hazard_mask[y * width + x] = 1
