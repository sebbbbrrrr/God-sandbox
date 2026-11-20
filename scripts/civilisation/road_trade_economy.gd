extends RefCounted
# Phase B-E foundation: authoritative pedestrian roads and physical inter-capital
# barter. Both capitals are the current real depot authorities; this deliberately
# does not pretend that arbitrary independent town inventories exist yet.
const Nav = preload("res://scripts/ai/navigation.gd")
const DIRS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
const GOODS := ["wood", "stone"]
const MAX_ROUTE_CELLS := 320
const MAX_QUEUE := 320
const MAX_EVENTS := 64
const MAX_ROAD_WORKERS := 2
const ROAD_LABOUR := 2
var roads: Dictionary = {} # cell-index string -> {nation, type, built_tick}
var road_queue: Array[Dictionary] = [] # physical, assigned, incomplete jobs
var road_jobs: Dictionary = {} # citizen id -> cell-index string
var trade_jobs: Dictionary = {} # citizen id -> carried offer and return leg
var route: Array = [] # persistent ordered [x,y] points, never teleports goods
var prices: Array[Dictionary] = [{}, {}]
var recent_trades: Array[Dictionary] = []
var completed_trades := 0
var route_status := "unplanned"
var revision := 0
var last_route_attempt := -360

func road_key(world: RefCounted, cell: Vector2i) -> String:
    return str(world.index_of(cell.x, cell.y))

func is_road(world: RefCounted, cell: Vector2i) -> bool:
    return roads.has(road_key(world, cell)) if world.index_of(cell.x, cell.y) >= 0 else false

func road_cost(world: RefCounted, cell: Vector2i) -> int:
    return 5 if is_road(world, cell) else 10

func _cell(data: Array) -> Vector2i:
    return Vector2i(int(data[0]), int(data[1]))

func _queued(key: String) -> bool:
    for site in road_queue:
        if str(site["key"]) == key:
            return true
    return false

func _valid_road_tile(world: RefCounted, cell: Vector2i) -> bool:
    return world.index_of(cell.x, cell.y) >= 0 and world.is_walkable(cell.x, cell.y) \
        and world.at(cell.x, cell.y) != world.ASH and not world.construction.occupied(cell.x, cell.y)

func _queue(world: RefCounted, cell: Vector2i, nation: int) -> void:
    if road_queue.size() >= MAX_QUEUE or not _valid_road_tile(world, cell):
        return
    var key := road_key(world, cell)
    if roads.has(key) or _queued(key):
        return
    road_queue.append({"key": key, "cell": [cell.x, cell.y], "nation": nation,
        "work": 0, "assigned": 0, "created": world.tick})

func _plan_connection(world: RefCounted) -> void:
    last_route_attempt = world.tick
    var a: Vector2i = world.capitals[0]
    var b: Vector2i = world.capitals[1]
    if not world.is_walkable(a.x, a.y) or not world.is_walkable(b.x, b.y):
        route_status = "missing_capital"
        return
    var origin := world.index_of(a.x, a.y)
    var destination := world.index_of(b.x, b.y)
    var frontier: Array[int] = [origin]
    var parent: Dictionary = {}
    parent[origin] = -1
    var head := 0
    # Deterministic bounded BFS runs only when a connection is needed or was
    # invalidated. Never run per citizen or per frame.
    while head < frontier.size() and parent.size() <= world.WIDTH * world.HEIGHT:
        var index: int = frontier[head]
        head += 1
        if index == destination:
            break
        var at := Vector2i(index % world.WIDTH, index / world.WIDTH)
        for direction in DIRS:
            var next: Vector2i = at + direction
            var next_index: int = world.index_of(next.x, next.y)
            if next_index < 0 or parent.has(next_index):
                continue
            if next_index != destination and not _valid_road_tile(world, next):
                continue
            parent[next_index] = index
            frontier.append(next_index)
    if not parent.has(destination):
        route_status = "blocked"
        route.clear()
        return
    var candidate: Array = []
    var cursor := destination
    while cursor != -1 and candidate.size() < MAX_ROUTE_CELLS:
        candidate.push_front([cursor % world.WIDTH, cursor / world.WIDTH])
        cursor = int(parent.get(cursor, -1))
    if candidate.is_empty() or _cell(candidate[0]) != a or candidate.size() >= MAX_ROUTE_CELLS:
        route_status = "too_long"
        route.clear()
        return
    route = candidate
    route_status = "building"
    for i in range(1, route.size() - 1):
        var owner: int = 0 if i * 2 < route.size() else 1
        _queue(world, _cell(route[i]), owner)
    revision += 1

func _plan_local_streets(world: RefCounted) -> void:
    if route.is_empty() or road_queue.size() > 180:
        return
    # Buildings seek the nearest actual road; roads do not silently appear at
    # the completion of a house. A citizen still has to walk there and work.
    var inspected := 0
    for home in world.construction.houses:
        if inspected >= 24 or road_queue.size() >= MAX_QUEUE:
            break
        inspected += 1
        var origin := Vector2i(int(home["x"]), int(home["y"]))
        var target := Vector2i(-1, -1)
        var best := 2147483647
        for dy in range(-7, 8):
            for dx in range(-7, 8):
                var point := origin + Vector2i(dx, dy)
                var distance := absi(dx) + absi(dy)
                if distance > 7 or distance >= best or not is_road(world, point):
                    continue
                best = distance
                target = point
        if best <= 1 or target.x < 0:
            continue
        var current := origin
        for i in range(best):
            var dx: int = signi(target.x - current.x)
            var dy: int = signi(target.y - current.y)
            var horizontal := current + Vector2i(dx, 0)
            var vertical := current + Vector2i(0, dy)
            if dx != 0 and _valid_road_tile(world, horizontal):
                current = horizontal
            elif dy != 0 and _valid_road_tile(world, vertical):
                current = vertical
            else:
                break
            _queue(world, current, int(home.get("nation", 0)))

func connected(world: RefCounted) -> bool:
    if route.size() < 2:
        return false
    for i in range(route.size()):
        var cell := _cell(route[i])
        if not world.is_walkable(cell.x, cell.y):
            return false
        if i > 0 and Nav.manhattan(_cell(route[i - 1]), cell) != 1:
            return false
        if i > 0 and i < route.size() - 1 and not is_road(world, cell):
            return false
    return true

func on_terrain_changed(world: RefCounted, x: int, y: int) -> void:
    var cell := Vector2i(x, y)
    var key := road_key(world, cell)
    if roads.has(key) and not _valid_road_tile(world, cell):
        roads.erase(key)
        revision += 1
    if not route.is_empty():
        for point in route:
            if _cell(point) == cell and not world.is_walkable(x, y):
                route.clear()
                route_status = "blocked"
                last_route_attempt = world.tick - 360
                break
    for i in range(road_queue.size() - 1, -1, -1):
        if str(road_queue[i]["key"]) == key and not _valid_road_tile(world, cell):
            road_queue.remove_at(i)

func _update_prices(world: RefCounted) -> void:
    for nation in range(2):
        var board := {}
        var stock := world.inventory.settlement_inventory(nation)
        for good in GOODS:
            var quantity := int(stock.get(good, 0))
            var shortage := world.construction.missing_material(nation) == good
            board[good] = clampi(100 + (80 if shortage else 0) - mini(65, quantity * 9), 35, 300)
        prices[nation] = board

func on_tick(world: RefCounted) -> void:
    if (route.is_empty() or route_status in ["blocked", "missing_capital"]) and world.tick - last_route_attempt >= 360:
        _plan_connection(world)
    if world.tick % 240 == 1:
        _plan_local_streets(world)
    if world.tick % 60 == 1:
        _update_prices(world)
    for key in road_jobs.keys():
        var person: Dictionary = world.ai_context.people.get(int(key), {})
        if person.is_empty() or int(person.get("hp", 0)) <= 0:
            _release_road(str(key))
    for key in trade_jobs.keys():
        var person: Dictionary = world.ai_context.people.get(int(key), {})
        if person.is_empty() or int(person.get("hp", 0)) <= 0:
            trade_jobs.erase(key)
    if route_status == "building" and connected(world):
        route_status = "connected"

func _release_road(id: String) -> void:
    var key := str(road_jobs.get(id, ""))
    for site in road_queue:
        if str(site["key"]) == key and int(site["assigned"]) == int(id):
            site["assigned"] = 0
    road_jobs.erase(id)

func _move(world: RefCounted, person: Dictionary, mind: Dictionary, target: Vector2i) -> bool:
    var origin := Vector2i(int(person["x"]), int(person["y"]))
    if origin == target:
        return true
    var next: Vector2i = Nav.next_step(world, person, mind, target)
    if next != origin:
        person["x"] = next.x
        person["y"] = next.y
        world.ai_context.moved(person, origin)
    return next == target

func _road_work(world: RefCounted, person: Dictionary, mind: Dictionary) -> bool:
    var id := str(person["id"])
    if not road_jobs.has(id):
        if road_jobs.size() >= MAX_ROAD_WORKERS:
            return false
        var nation := int(person["nation"])
        for site in road_queue:
            if int(site["nation"]) != nation or int(site["assigned"]) != 0:
                continue
            site["assigned"] = int(person["id"])
            road_jobs[id] = str(site["key"])
            mind["route"] = []
            mind["next_path_tick"] = world.tick
            break
    if not road_jobs.has(id):
        return false
    var chosen: Dictionary = {}
    for site in road_queue:
        if str(site["key"]) == str(road_jobs[id]):
            chosen = site
            break
    if chosen.is_empty():
        road_jobs.erase(id)
        return false
    var target := _cell(chosen["cell"])
    if not _valid_road_tile(world, target):
        _release_road(id)
        return false
    var start := Vector2i(int(person["x"]), int(person["y"]))
    if not _move(world, person, mind, target):
        if start == Vector2i(int(person["x"]), int(person["y"])):
            chosen["stalled"] = int(chosen.get("stalled", 0)) + 1
        else:
            chosen["stalled"] = 0
        if int(chosen.get("stalled", 0)) > 30:
            _release_road(id)
        return true
    chosen["work"] = int(chosen["work"]) + 1
    if int(chosen["work"]) >= ROAD_LABOUR:
        roads[str(chosen["key"])] = {"nation": int(chosen["nation"]), "type": "trail", "built_tick": world.tick}
        road_queue.erase(chosen)
        road_jobs.erase(id)
        mind["route"] = []
        revision += 1
        world.terrain_changed.emit(target) # renderer invalidation; terrain itself is untouched
    return true

func _trade_offer(world: RefCounted, nation: int) -> Dictionary:
    if not connected(world):
        return {}
    var other := 1 - nation
    for good in GOODS:
        var desired := "stone" if good == "wood" else "wood"
        if world.inventory.available("settlement:" + str(nation), good) < 4:
            continue
        if world.inventory.available("settlement:" + str(other), good) > 1:
            continue
        if world.inventory.available("settlement:" + str(other), desired) < 4:
            continue
        if world.inventory.available("settlement:" + str(nation), desired) > 1:
            continue
        return {"nation": nation, "other": other, "offer": good, "payment": desired}
    return {}

func _has_trader(nation: int) -> bool:
    for job in trade_jobs.values():
        if int(job["nation"]) == nation:
            return true
    return false

func authorizes_exchange(citizen_id: int, target_nation: int, offer: Dictionary, payment: Dictionary) -> bool:
    var job: Dictionary = trade_jobs.get(str(citizen_id), {})
    return not job.is_empty() and str(job.get("phase", "")) == "exchange" \
        and int(job.get("other", -1)) == target_nation \
        and offer == {str(job.get("offer", "")): 1} and payment == {str(job.get("payment", "")): 1}

func _trading_work(world: RefCounted, person: Dictionary, mind: Dictionary) -> bool:
    var id := str(person["id"])
    if not trade_jobs.has(id):
        if _has_trader(int(person["nation"])):
            return false
        var proposal := _trade_offer(world, int(person["nation"]))
        if proposal.is_empty():
            return false
        proposal["phase"] = "pickup"
        proposal["started_tick"] = world.tick
        trade_jobs[id] = proposal
        mind["route"] = []
        mind["next_path_tick"] = world.tick
    var job: Dictionary = trade_jobs[id]
    var nation := int(job["nation"])
    var home: Vector2i = world.capitals[nation]
    var foreign: Vector2i = world.capitals[int(job["other"])]
    var cargo_id := "citizen:" + id
    var home_id := "settlement:" + str(nation)
    var offered := {str(job["offer"]): 1}
    var received := {str(job["payment"]): 1}
    if str(job["phase"]) == "pickup":
        if not _move(world, person, mind, home):
            return true
        if not world.inventory.transfer(world, home_id, cargo_id, offered, int(person["id"])):
            trade_jobs.erase(id)
            return false
        job["phase"] = "exchange"
        mind["route"] = []
        return true
    if str(job["phase"]) == "exchange":
        if not _move(world, person, mind, foreign):
            return true
        if world.inventory.exchange_at_market(world, int(person["id"]), int(job["other"]), offered, received):
            job["phase"] = "return"
            job["success"] = true
        else:
            job["phase"] = "return"
            job["success"] = false
        mind["route"] = []
        return true
    if not _move(world, person, mind, home):
        return true
    var goods: Dictionary = received if bool(job.get("success", false)) else offered
    if not world.inventory.transfer(world, cargo_id, home_id, goods, int(person["id"])):
        return true
    if bool(job.get("success", false)):
        completed_trades += 1
        recent_trades.append({"tick": world.tick, "from": nation, "to": int(job["other"]),
            "export": str(job["offer"]), "import": str(job["payment"]), "units": 1,
            "source_quote": int(prices[nation].get(str(job["offer"]), 100)),
            "destination_quote": int(prices[int(job["other"])].get(str(job["offer"]), 100))})
        if recent_trades.size() > MAX_EVENTS:
            recent_trades.pop_front()
    trade_jobs.erase(id)
    mind["route"] = []
    return true

func work_step(world: RefCounted, person: Dictionary, mind: Dictionary) -> bool:
    if int(person.get("hp", 0)) <= 0 or world.lifecycle.is_dependent(person):
        return false
    var id := str(person["id"])
    if world.construction.jobs.has(id) or world.food.jobs.has(id) or world.toolmaking.jobs.has(id):
        return false
    if trade_jobs.has(id):
        return _trading_work(world, person, mind)
    if road_jobs.has(id):
        return _road_work(world, person, mind)
    if _road_work(world, person, mind):
        return true
    return _trading_work(world, person, mind)

func snapshot() -> Dictionary:
    return {"version": 1, "roads": roads.duplicate(true), "road_queue": road_queue.duplicate(true),
        "road_jobs": road_jobs.duplicate(true), "trade_jobs": trade_jobs.duplicate(true),
        "route": route.duplicate(true), "prices": prices.duplicate(true),
        "recent_trades": recent_trades.duplicate(true), "completed_trades": completed_trades,
        "route_status": route_status, "revision": revision, "last_route_attempt": last_route_attempt}

func load_state(world: RefCounted, raw: Variant) -> bool:
    if raw == null:
        return true # backwards-compatible pre-road world
    if not raw is Dictionary or int(raw.get("version", 0)) != 1:
        return false
    if not raw.get("roads", {}) is Dictionary or not raw.get("road_queue", []) is Array \
            or not raw.get("road_jobs", {}) is Dictionary or not raw.get("trade_jobs", {}) is Dictionary \
            or not raw.get("route", []) is Array or not raw.get("recent_trades", []) is Array:
        return false
    if raw["roads"].size() > world.WIDTH * world.HEIGHT or raw["road_queue"].size() > MAX_QUEUE \
            or raw["route"].size() > MAX_ROUTE_CELLS or raw["recent_trades"].size() > MAX_EVENTS \
            or raw["road_jobs"].size() > MAX_ROAD_WORKERS or raw["trade_jobs"].size() > 2:
        return false
    for key in raw["roads"]:
        if not str(key).is_valid_int():
            return false
        var index := int(key)
        if index < 0 or index >= world.WIDTH * world.HEIGHT:
            return false
        if not world.is_walkable(index % world.WIDTH, index / world.WIDTH):
            return false
    for site in raw["road_queue"]:
        if not site is Dictionary or not site.get("cell", []) is Array or site["cell"].size() != 2:
            return false
        if world.index_of(int(site["cell"][0]), int(site["cell"][1])) < 0:
            return false
    for point in raw["route"]:
        if not point is Array or point.size() != 2 or world.index_of(int(point[0]), int(point[1])) < 0:
            return false
    roads = raw["roads"].duplicate(true)
    road_queue.clear()
    for site in raw["road_queue"]:
        road_queue.append(site.duplicate(true))
    road_jobs = raw["road_jobs"].duplicate(true)
    trade_jobs = raw["trade_jobs"].duplicate(true)
    route = raw["route"].duplicate(true)
    prices = raw.get("prices", [{}, {}]).duplicate(true)
    if prices.size() != 2:
        return false
    recent_trades.clear()
    for event in raw["recent_trades"]:
        if not event is Dictionary:
            return false
        recent_trades.append(event.duplicate(true))
    completed_trades = maxi(0, int(raw.get("completed_trades", 0)))
    route_status = str(raw.get("route_status", "unplanned"))
    revision = int(raw.get("revision", 0))
    last_route_attempt = int(raw.get("last_route_attempt", -360))
    for id in road_jobs:
        var found := false
        for site in road_queue:
            if str(site["key"]) == str(road_jobs[id]) and int(site["assigned"]) == int(id):
                found = true
                break
        if not found or not world.ai_context.people.has(int(id)):
            return false
    for id in trade_jobs:
        if not world.ai_context.people.has(int(id)):
            return false
        var job: Dictionary = trade_jobs[id]
        if str(job.get("offer", "")) not in GOODS or str(job.get("payment", "")) not in GOODS \
                or str(job["offer"]) == str(job["payment"]) or int(job.get("nation", -1)) not in [0, 1] \
                or int(job.get("other", -1)) != 1 - int(job.get("nation", -1)) \
                or str(job.get("phase", "")) not in ["pickup", "exchange", "return"]:
            return false
    return true
