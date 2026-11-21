extends RefCounted
# Authoritative pedestrian roads and physical barter/food relief between local
# settlement depots. Legacy capital APIs and saved routes remain compatible.
const Nav = preload("res://scripts/ai/navigation.gd")
const DIRS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
const GOODS := ["wood", "stone"]
const MAX_ROUTE_CELLS := 320
const MAX_QUEUE := 320
const MAX_EVENTS := 64
const MAX_LINKS := 48
const MAX_NETWORK_NODES := 2048
const MAX_TRADERS := 6
const MAX_ROAD_WORKERS := 4
const ROAD_LABOUR := 2
var links: Dictionary = {}
var local_prices: Dictionary = {}
var network_cursor := 0
var streets_cursor := 0
var roads: Dictionary = {} # cell-index string -> {nation, type, built_tick}
var road_queue: Array[Dictionary] = [] # physical, assigned, incomplete jobs
var road_jobs: Dictionary = {} # citizen id -> cell-index string
var trade_jobs: Dictionary = {} # citizen id -> carried offer and return leg
var route: Array = [] # persistent ordered [x,y] points, never teleports goods
var prices: Array[Dictionary] = [{}, {}]
var recent_trades: Array[Dictionary] = []
var completed_trades := 0
var completed_relief := 0
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
    road_queue.append({"key": key, "cell": [cell.x, cell.y], "nation": world.settlements.nation(nation), "settlement_id": nation,
        "work": 0, "assigned": 0, "created": world.tick})

func link_key(a: int, b: int) -> String:
    return str(mini(a,b)) + ":" + str(maxi(a,b))

func quote(id: int) -> Dictionary:
    return prices[id] if id in [0,1] else local_prices.get(str(id), {})

func _path_connected(world: RefCounted, path: Array) -> bool:
    if path.size() < 2:
        return false
    for i in range(path.size()):
        var cell := _cell(path[i])
        if not world.is_walkable(cell.x,cell.y) or Nav.danger_near(world,cell):
            return false
        if i > 0 and Nav.manhattan(_cell(path[i-1]),cell) != 1:
            return false
        if i > 0 and i < path.size()-1 and not is_road(world,cell):
            return false
    return true

func _plan_connection(world: RefCounted, first: int = 0, second: int = 1) -> void:
    last_route_attempt = world.tick
    var a_id := mini(first,second)
    var b_id := maxi(first,second)
    var a: Vector2i = world.settlements.center(world,a_id)
    var b: Vector2i = world.settlements.center(world,b_id)
    var key := link_key(a_id,b_id)
    if not world.is_walkable(a.x,a.y) or not world.is_walkable(b.x,b.y):
        if key == "0:1": route_status = "missing_capital"
        return
    if a_id == b_id or (links.size() >= MAX_LINKS and not links.has(key)) or road_queue.size() > 160:
        return
    var start: int = world.index_of(a.x,a.y)
    var finish: int = world.index_of(b.x,b.y)
    var frontier: Array[int] = [start]
    var parent := {start:-1}
    var head := 0
    while head < frontier.size() and parent.size() < MAX_NETWORK_NODES:
        var index: int = frontier[head]
        head += 1
        if index == finish: break
        var cell := Vector2i(index % world.WIDTH,index / world.WIDTH)
        for direction in DIRS:
            var next: Vector2i = cell + direction
            var ni: int = world.index_of(next.x,next.y)
            if ni < 0 or parent.has(ni) or parent.size() >= MAX_NETWORK_NODES: continue
            if Nav.danger_near(world,next) or (ni != finish and not _valid_road_tile(world,next)): continue
            parent[ni] = index
            frontier.append(ni)
    var path: Array = []
    if parent.has(finish):
        var current := finish
        while current != -1 and path.size() < MAX_ROUTE_CELLS:
            path.push_front([current % world.WIDTH,current / world.WIDTH])
            current = int(parent.get(current,-1))
    var valid := path.size() >= 2 and _cell(path[0]) == a and path.size() < MAX_ROUTE_CELLS
    links[key] = {"a":a_id,"b":b_id,"path":path if valid else [],"status":"building" if valid else "blocked","attempt":world.tick}
    if key == "0:1":
        route = links[key]["path"]
        route_status = str(links[key]["status"])
    if valid:
        for i in range(1,path.size()-1):
            _queue(world,_cell(path[i]),a_id if i*2 < path.size() else b_id)
    revision += 1

func _plan_network(world: RefCounted) -> void:
    world.settlements.ensure_legacy(world)
    var ids: Array = world.settlements.records.keys()
    ids.sort_custom(func(a: Variant,b: Variant) -> bool: return int(a)<int(b))
    if ids.is_empty(): return
    network_cursor %= ids.size()
    var source := int(ids[network_cursor])
    network_cursor += 1
    if world.settlements.population(source) <= 0: return
    var nearest := -1
    var best := 2147483647
    for key in ids:
        var other := int(key)
        if other == source or world.settlements.population(other) <= 0: continue
        if str(world.settlements.get_record(other)["status"]) in ["abandoned","failed"]: continue
        var link: Dictionary = links.get(link_key(source,other),{})
        if not link.is_empty() and str(link["status"]) != "blocked": continue
        if not link.is_empty() and world.tick-int(link["attempt"])<360: continue
        var distance: int = Nav.manhattan(world.settlements.center(world,source),world.settlements.center(world,other))
        if distance < best and distance <= 64:
            nearest = other
            best = distance
    if nearest >= 0: _plan_connection(world,source,nearest)

func _plan_local_streets(world: RefCounted) -> void:
    if road_queue.size() > 180:
        return
    # Buildings seek the nearest actual road; roads do not silently appear at
    # the completion of a house. A citizen still has to walk there and work.
    var inspected := 0
    var homes: Array = world.construction.houses
    for n in range(mini(24,homes.size())):
        streets_cursor %= homes.size()
        var home: Dictionary = homes[streets_cursor]
        streets_cursor += 1
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
            _queue(world, current, world.settlements.sid(home))

func connected(world: RefCounted, a: int = 0, b: int = 1) -> bool:
    var key := link_key(a,b)
    return _path_connected(world,links.get(key,{}).get("path",route if key=="0:1" else []))

func on_building_changed(world: RefCounted, cell: Vector2i) -> void:
    if not world.construction.occupied(cell.x,cell.y): return
    var key := road_key(world,cell)
    if roads.erase(key): revision += 1
    for link in links.values():
        if [cell.x,cell.y] in link["path"]:
            link["status"] = "blocked"
            link["attempt"] = world.tick-360

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
    for link in links.values():
        if [x,y] in link["path"] and not world.is_walkable(x,y):
            link["status"] = "blocked"
            link["attempt"] = world.tick-360
    for i in range(road_queue.size() - 1, -1, -1):
        if str(road_queue[i]["key"]) == key and not _valid_road_tile(world, cell):
            road_queue.remove_at(i)

func _update_prices(world: RefCounted) -> void:
    world.settlements.ensure_legacy(world)
    for key in world.settlements.records:
        var nation := int(key)
        var board := {}
        var stock: Dictionary = world.inventory.settlement_inventory(nation)
        for good in GOODS:
            var quantity := int(stock.get(good, 0))
            var shortage: bool = world.construction.missing_material(nation) == good
            board[good] = clampi(100 + (80 if shortage else 0) - mini(65, quantity * 9), 35, 300)
        if nation in [0,1]: prices[nation] = board
        else: local_prices[str(nation)] = board

func on_tick(world: RefCounted) -> void:
    if (route.is_empty() or route_status in ["blocked", "missing_capital"]) and world.tick - last_route_attempt >= 360:
        _plan_connection(world)
    if world.tick % 120 == 17:
        _plan_network(world)
    for link in links.values():
        if str(link["status"]) == "building" and _path_connected(world,link["path"]):
            link["status"] = "connected"
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
        if person.is_empty() or int(person.get("hp", 0)) <= 0 or world.tick-int(trade_jobs[key].get("started_tick",world.tick))>1200:
            trade_jobs.erase(key) # actual carried goods remain owned by the citizen; no refund
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
        var nation: int = world.settlements.sid(person)
        for site in road_queue:
            if int(site.get("settlement_id",site["nation"])) != nation or int(site["assigned"]) != 0:
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
        roads[str(chosen["key"])] = {"nation": int(chosen["nation"]), "settlement_id": int(chosen.get("settlement_id",chosen["nation"])), "type": "trail", "built_tick": world.tick}
        road_queue.erase(chosen)
        road_jobs.erase(id)
        mind["route"] = []
        revision += 1
        world.terrain_changed.emit(target) # renderer invalidation; terrain itself is untouched
    return true

func _trade_offer(world: RefCounted, nation: int) -> Dictionary:
    var keys: Array = links.keys()
    keys.sort()
    for key in keys:
        var link: Dictionary = links[key]
        if nation not in [int(link["a"]),int(link["b"]) ] or not connected(world,int(link["a"]),int(link["b"])): continue
        var other := int(link["b"]) if nation == int(link["a"]) else int(link["a"])
        if str(world.settlements.get_record(other).get("status","legacy")) in ["abandoned","failed"]: continue
        for good in GOODS:
            var desired := "stone" if good == "wood" else "wood"
            if world.inventory.available("settlement:"+str(nation),good)<4 or world.inventory.available("settlement:"+str(other),good)>1: continue
            if world.inventory.available("settlement:"+str(other),desired)<4 or world.inventory.available("settlement:"+str(nation),desired)>1: continue
            return {"nation":world.settlements.nation(nation),"settlement_id":nation,"other":other,"offer":good,"payment":desired,"link":key}
    # Same-nation food relief is an explicit local surplus/shortage request.
    # A real merchant must pick up and deliver edible units from the food ledger.
    for key in keys:
        var link: Dictionary = links[key]
        if nation not in [int(link["a"]),int(link["b"])] or not connected(world,int(link["a"]),int(link["b"])): continue
        var other := int(link["b"]) if nation==int(link["a"]) else int(link["a"])
        if world.settlements.nation(nation)!=world.settlements.nation(other) or world.settlements.population(other)<=0: continue
        if str(world.settlements.get_record(other)["status"]) in ["abandoned","failed"]: continue
        if world.food.total(world.food.store(nation))<maxi(6,world.settlements.population(nation)*3): continue
        if world.food.total(world.food.store(other))>=maxi(3,world.settlements.population(other)): continue
        for good in world.food.FOOD_TYPES:
            if int(world.food.store(nation).get(good,0))>0:
                return {"kind":"relief","nation":world.settlements.nation(nation),"settlement_id":nation,"other":other,"offer":good,"payment":good,"link":key}
    return {}

func _has_trader(nation: int, limit: int = 1) -> bool:
    var count := 0
    for job in trade_jobs.values():
        if int(job.get("settlement_id",job["nation"])) == nation: count += 1
    return count >= limit

func authorizes_exchange(citizen_id: int, target_nation: int, offer: Dictionary, payment: Dictionary) -> bool:
    var job: Dictionary = trade_jobs.get(str(citizen_id), {})
    return not job.is_empty() and str(job.get("phase", "")) == "exchange" \
        and int(job.get("other", -1)) == target_nation \
        and offer == {str(job.get("offer", "")): 1} and payment == {str(job.get("payment", "")): 1}

# Merchants use built road waypoints rather than teleporting or drawing a
# cosmetic connection. Each waypoint is approached by the normal AI movement.
func _follow_trade_route(world: RefCounted, person: Dictionary, mind: Dictionary, job: Dictionary, destination_nation: int) -> bool:
    var home := int(job.get("settlement_id",job["nation"]))
    var link: Dictionary = links.get(str(job.get("link",link_key(home,int(job["other"])))),{})
    var path: Array = link.get("path",route if home in [0,1] and int(job["other"]) in [0,1] else [])
    var target: Vector2i = world.settlements.center(world,destination_nation)
    # Broken routes return cargo physically off-road; never settle a transaction remotely.
    if path.size()<2 or not _path_connected(world,path):
        if str(job["phase"]) == "exchange":
            job["phase"] = "return"
            job["success"] = false
            mind["route"] = []
        return _move(world,person,mind,world.settlements.center(world,home)) if str(job["phase"]) == "return" else false
    var a_id := int(link.get("a",0))
    var final_index := 0 if destination_nation == a_id else path.size()-1
    var current := clampi(int(job.get("route_index",0 if home==a_id else path.size()-1)),0,path.size()-1)
    if current == final_index:
        return _move(world,person,mind,target)
    var next := current + (1 if final_index>current else -1)
    if _move(world,person,mind,_cell(path[next])): job["route_index"] = next
    return int(job.get("route_index",current)) == final_index and Vector2i(int(person["x"]),int(person["y"])) == target

func _trading_work(world: RefCounted, person: Dictionary, mind: Dictionary) -> bool:
    var id := str(person["id"])
    if not trade_jobs.has(id):
        if trade_jobs.size() >= MAX_TRADERS or _has_trader(world.settlements.sid(person),2 if world.occupations.facility_present(world,world.settlements.sid(person),"market") else 1):
            return false
        var proposal := _trade_offer(world, world.settlements.sid(person))
        if proposal.is_empty():
            return false
        proposal["phase"] = "pickup"
        proposal["started_tick"] = world.tick
        trade_jobs[id] = proposal
        mind["route"] = []
        mind["next_path_tick"] = world.tick
    var job: Dictionary = trade_jobs[id]
    if str(job.get("kind",""))=="relief": return _relief_work(world,person,mind,job)
    var nation := int(job.get("settlement_id",job["nation"]))
    var home: Vector2i = world.settlements.center(world,nation)
    var foreign: Vector2i = world.settlements.center(world,int(job["other"]))
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
        var link: Dictionary = links.get(str(job.get("link","0:1")),{})
        job["route_index"] = 0 if nation == int(link.get("a",0)) else link.get("path",route).size()-1
        mind["route"] = []
        return true
    if str(job["phase"]) == "exchange":
        if not _follow_trade_route(world, person, mind, job, int(job["other"])):
            return true
        if str(job["phase"]) != "exchange": return true
        if world.inventory.exchange_at_market(world, int(person["id"]), int(job["other"]), offered, received):
            job["phase"] = "return"
            job["success"] = true
        else:
            job["phase"] = "return"
            job["success"] = false
        mind["route"] = []
        return true
    if not _follow_trade_route(world, person, mind, job, nation):
        return true
    var goods: Dictionary = received if bool(job.get("success", false)) else offered
    if not world.inventory.transfer(world, cargo_id, home_id, goods, int(person["id"])):
        return true
    if bool(job.get("success", false)):
        completed_trades += 1
        recent_trades.append({"tick": world.tick, "from": nation, "to": int(job["other"]),
            "export": str(job["offer"]), "import": str(job["payment"]), "units": 1,
            "source_quote": int(quote(nation).get(str(job["offer"]), 100)),
            "destination_quote": int(quote(int(job["other"])).get(str(job["offer"]), 100))})
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
    return {"version": 2, "completed_relief":completed_relief, "links": links.duplicate(true), "local_prices": local_prices.duplicate(true), "network_cursor": network_cursor, "streets_cursor": streets_cursor, "roads": roads.duplicate(true), "road_queue": road_queue.duplicate(true),
        "road_jobs": road_jobs.duplicate(true), "trade_jobs": trade_jobs.duplicate(true),
        "route": route.duplicate(true), "prices": prices.duplicate(true),
        "recent_trades": recent_trades.duplicate(true), "completed_trades": completed_trades,
        "route_status": route_status, "revision": revision, "last_route_attempt": last_route_attempt}

func load_state(world: RefCounted, raw: Variant) -> bool:
    if raw == null:
        return true # backwards-compatible pre-road world
    if not raw is Dictionary or int(raw.get("version", 0)) not in [1,2]:
        return false
    if not raw.get("roads", {}) is Dictionary or not raw.get("road_queue", []) is Array \
            or not raw.get("road_jobs", {}) is Dictionary or not raw.get("trade_jobs", {}) is Dictionary \
            or not raw.get("route", []) is Array or not raw.get("recent_trades", []) is Array:
        return false
    if raw["roads"].size() > world.WIDTH * world.HEIGHT or raw["road_queue"].size() > MAX_QUEUE \
            or raw["route"].size() > MAX_ROUTE_CELLS or raw["recent_trades"].size() > MAX_EVENTS \
            or raw["road_jobs"].size() > MAX_ROAD_WORKERS or raw["trade_jobs"].size() > MAX_TRADERS:
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
    var incoming_prices: Variant = raw.get("prices", [{}, {}])
    if not incoming_prices is Array or incoming_prices.size() != 2:
        return false
    prices.clear()
    for board in incoming_prices:
        if not board is Dictionary:
            return false
        prices.append(board.duplicate(true))
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
        if int(raw.get("version",1))==1 and (str(job.get("offer", "")) not in GOODS or str(job.get("payment", "")) not in GOODS \
                or str(job["offer"]) == str(job["payment"]) or int(job.get("nation", -1)) not in [0, 1] \
                or int(job.get("other", -1)) != 1 - int(job.get("nation", -1)) \
                or str(job.get("phase", "")) not in ["pickup", "exchange", "return"]):
            return false
    if int(raw.get("version",1)) == 1:
        if not route.is_empty(): links["0:1"] = {"a":0,"b":1,"path":route,"status":route_status,"attempt":last_route_attempt}
    else:
        completed_relief = maxi(0,int(raw.get("completed_relief",0)))
        if not raw.get("links") is Dictionary or raw["links"].size()>MAX_LINKS or not raw.get("local_prices") is Dictionary: return false
        links = raw["links"].duplicate(true)
        local_prices = raw["local_prices"].duplicate(true)
        network_cursor = maxi(0,int(raw.get("network_cursor",0)))
        streets_cursor = maxi(0,int(raw.get("streets_cursor",0)))
        for key in links:
            var link: Variant = links[key]
            if not link is Dictionary or not link.get("path") is Array or link["path"].size()>MAX_ROUTE_CELLS: return false
            if world.settlements.get_record(int(link.get("a",-1))).is_empty() or world.settlements.get_record(int(link.get("b",-1))).is_empty(): return false
            if str(key) != link_key(int(link["a"]),int(link["b"])): return false
            for point in link["path"]:
                if not point is Array or point.size()!=2 or world.index_of(int(point[0]),int(point[1]))<0: return false
        for key in trade_jobs:
            var job: Dictionary = trade_jobs[key]
            var person: Dictionary = world.ai_context.people.get(int(key),{})
            if person.is_empty() or int(job.get("settlement_id",job.get("nation",-1))) != world.settlements.sid(person): return false
            if world.settlements.get_record(int(job.get("other",-1))).is_empty(): return false
            if str(job.get("phase","")) not in ["pickup","exchange","return"]: return false
            var allowed: Array = world.food.FOOD_TYPES if str(job.get("kind",""))=="relief" else GOODS
            if str(job.get("offer","")) not in allowed or str(job.get("payment","")) not in allowed: return false
    return true

func _relief_work(world: RefCounted, person: Dictionary, mind: Dictionary, job: Dictionary) -> bool:
    var id := str(person["id"])
    var origin := int(job["settlement_id"])
    var target := int(job["other"])
    var good := str(job["offer"])
    if str(job["phase"])=="pickup":
        if not _move(world,person,mind,world.settlements.center(world,origin)): return true
        if not world.food.relief_transfer(world,int(person["id"]),origin,good,true):
            trade_jobs.erase(id)
            return false
        job["phase"] = "exchange"
        var link: Dictionary = links[str(job["link"])]
        job["route_index"] = 0 if origin==int(link["a"]) else link["path"].size()-1
        mind["route"] = []
        return true
    if str(job["phase"])=="exchange":
        if not _follow_trade_route(world,person,mind,job,target): return true
        if str(job["phase"])=="exchange":
            job["success"] = world.food.relief_transfer(world,int(person["id"]),target,good,false)
            job["phase"] = "return"
            mind["route"] = []
        return true
    if not _follow_trade_route(world,person,mind,job,origin): return true
    if not bool(job.get("success",false)):
        world.food.relief_transfer(world,int(person["id"]),origin,good,false)
    else:
        completed_relief += 1
        world.settlements.event(world,target,"food_import_delivered")
    trade_jobs.erase(id)
    mind["route"] = []
    return true
