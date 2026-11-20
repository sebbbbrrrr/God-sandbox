extends RefCounted

const BELIEF_CAPACITY := 16
const RADIUS := 4
const BUCKET_SIZE := 4
const MAX_CANDIDATES := 32
const MAX_NEARBY := 8
const MAX_PATH_REQUESTS := 12
const RAYS := [Vector2i(4, 0), Vector2i(3, 3), Vector2i(0, 4), Vector2i(-3, 3), Vector2i(-4, 0), Vector2i(-3, -3), Vector2i(0, -4), Vector2i(3, -3)]

var buckets: Dictionary = {}
var people: Dictionary = {}
var risk_maps: Dictionary = {}
var local_views: Dictionary = {}
var metrics := {"decisions": 0, "social_candidates": 0, "path_requests": 0, "path_nodes": 0, "interactions": 0}

func begin_tick(world: RefCounted) -> void:
    buckets.clear()
    people.clear()
    risk_maps.clear()
    local_views.clear()
    for key in metrics:
        metrics[key] = 0
    # Canonical citizen order also guarantees that rebuilt caches replay after load.
    for person in world.citizens:
        if int(person["hp"]) <= 0:
            continue
        added(person)

func added(person: Dictionary) -> void:
    people[int(person["id"])] = person
    var key := bucket_of(Vector2i(person["x"], person["y"]))
    if not buckets.has(key):
        buckets[key] = []
    buckets[key].append(int(person["id"]))

static func bucket_of(cell: Vector2i) -> Vector2i:
    return Vector2i(cell.x / BUCKET_SIZE, cell.y / BUCKET_SIZE)

func moved(person: Dictionary, old_cell: Vector2i) -> void:
    var current := Vector2i(person["x"], person["y"])
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
    var center := bucket_of(cell)
    var checked := 0
    # Rotate bucket and within-bucket sampling, so a crowded tile cannot monopolize encounters.
    var rotation: int = (int(person["id"]) + int(world.tick) / 30) % 9
    for j in range(9):
        var offset: int = (j + rotation) % 9
        var key := center + Vector2i(offset % 3 - 1, offset / 3 - 1)
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
        result[Vector2i(fact["cell"][0], fact["cell"][1])] = fact
    return result

static func observe(state: Dictionary, cell: Vector2i, terrain_type: int, tick: int, visited: bool = false, index: Variant = null, trim: bool = true) -> bool:
    return learn(state, {"cell": [cell.x, cell.y], "terrain": terrain_type,
        "confidence": 100, "source": "direct", "source_id": 0, "hops": 0,
        "observed_at": tick, "updated_at": tick, "visits": 1 if visited else 0}, index, trim)

static func learn(state: Dictionary, fact: Dictionary, index: Variant = null, trim: bool = true) -> bool:
    var beliefs: Array = state["beliefs"]
    var location := Vector2i(fact["cell"][0], fact["cell"][1])
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
            index.erase(Vector2i(evicted["cell"][0], evicted["cell"][1]))
        beliefs.remove_at(weakest)
    return true

static func finish_observation(state: Dictionary) -> void:
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
        beliefs.remove_at(weakest)
        scores.remove_at(weakest)

static func belief_priority(fact: Dictionary) -> int:
    # Keep danger, settlements and repeatedly visited places longer than passing glimpses.
    return int(fact["updated_at"]) / 3 + int(fact["visits"]) * 4 + int(fact["confidence"]) + (60 if int(fact["terrain"]) in [5, 6] else 0)

static func share(sender: Dictionary, receiver: Dictionary, source_id: int, trust: int, tick: int) -> void:
    var chosen: Dictionary = {}
    for fact in sender["beliefs"]:
        if int(fact["hops"]) >= 2 or int(fact["confidence"]) < 35 or int(fact["terrain"]) not in [5, 6]:
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
    var beliefs: Array = state["beliefs"]
    for i in range(beliefs.size() - 1, -1, -1):
        beliefs[i]["confidence"] = maxi(0, int(beliefs[i]["confidence"]) - units * (4 if beliefs[i]["source"] == "shared" else 2))
        if int(beliefs[i]["confidence"]) == 0:
            beliefs.remove_at(i)
