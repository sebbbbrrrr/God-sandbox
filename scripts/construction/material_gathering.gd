extends RefCounted
const Nav = preload("res://scripts/ai/navigation.gd")
const Labour = preload("res://scripts/ai/labour_priorities.gd")
const RESOURCE_RADIUS := 12
const MAX_GATHERERS := 4
var stockpiles: Array[Dictionary] = [{"wood": 0, "stone": 0}, {"wood": 0, "stone": 0}]
var depleted: Dictionary = {}
var houses: Array[Dictionary] = []
var projects: Array[Dictionary] = []
var jobs: Dictionary = {}
var next_building_id = 1

func left_at(world: RefCounted, x: int, y: int, material: String) -> int:
    var biome: int = world.at(x, y)
    if material in ["wood", "plant_fibre"] and biome != world.FOREST:
        return 0
    if material in ["stone", "flint"] and biome != world.MOUNTAIN:
        return 0
    if material not in ["wood", "plant_fibre", "stone", "flint"]:
        return 0
    # Resources from the same cell share depletion; no independent
    # timber/fibre or stone/flint duplication from a single tile.
    return maxi(0, (6 if biome == world.FOREST else 10) - int(depleted.get(str(world.index_of(x, y)), 0)))

func approach(world: RefCounted, from: Vector2i, source: Vector2i) -> Vector2i:
    var best = Vector2i(-1, -1)
    var distance = 2147483647
    for cell in [source, source + Vector2i(1, 0), source + Vector2i(0, 1),
            source + Vector2i(-1, 0), source + Vector2i(0, -1)]:
        if world.is_walkable(cell.x, cell.y) and not Nav.danger_near(world, cell):
            var next_distance: int = Nav.manhattan(from, cell)
            if next_distance < distance:
                best = cell
                distance = next_distance
    return best

func source_for(world: RefCounted, person: Dictionary, material: String) -> Dictionary:
    var depot: Vector2i = world.settlements.center(world, world.settlements.sid(person))
    var origin = Vector2i(int(person["x"]), int(person["y"]))
    var result: Dictionary = {}
    var shortest = 2147483647
    for dy in range(-RESOURCE_RADIUS, RESOURCE_RADIUS + 1):
        for dx in range(-RESOURCE_RADIUS, RESOURCE_RADIUS + 1):
            if absi(dx) + absi(dy) > RESOURCE_RADIUS:
                continue
            var source = depot + Vector2i(dx, dy)
            if left_at(world, source.x, source.y, material) <= 0:
                continue
            var target = approach(world, origin, source)
            if target.x < 0:
                continue
            var claims: int = Labour.claim_count(jobs, [source.x, source.y], ["gather"])
            var score: int = Nav.manhattan(origin, target) + Nav.manhattan(target, depot)
            # A second gatherer should prefer a different forest/quarry tile.
            score += claims * 48 + posmod(source.x * 3 + source.y * 5 + int(person["id"]), 5)
            if score < shortest:
                shortest = score
                result = {"source": [source.x, source.y], "target": [target.x, target.y]}
    return result

func gatherer_count(nation: int) -> int:
    var result = 0
    for job in jobs.values():
        if str(job["kind"]) == "gather" and int(job.get("settlement_id", job["nation"])) == nation:
            result += 1
    return result


func walk(world: RefCounted, person: Dictionary, mind: Dictionary,
        target: Vector2i, contact_radius: int = 0) -> bool:
    var previous = Vector2i(int(person["x"]), int(person["y"]))
    if (Nav.manhattan(previous, target) <= contact_radius):
        return true
    var destination: Vector2i = Nav.hub_access(world, person, target) if contact_radius > 0 else target
    var next: Vector2i = Nav.next_step(world, person, mind, destination)
    if next != previous:
        person["x"] = next.x
        person["y"] = next.y
        world.ai_context.moved(person, previous)
    return Nav.manhattan(next, target) <= contact_radius

func gather_step(world: RefCounted, person: Dictionary, mind: Dictionary, id: String, task: Dictionary, depot: Vector2i) -> bool:
    if str(task["phase"]) == "depot":
        var holder := str(task.get("deposit_holder","settlement:"+str(task.get("settlement_id",task["nation"]))))
        var info: Dictionary = world.inventory._holder(world,holder)
        if info.is_empty():
            holder = "settlement:"+str(task.get("settlement_id",task["nation"]))
            info = world.inventory._holder(world,holder)
        if walk(world, person, mind, info.get("cell",depot), 1):
            var material = str(task["material"])
            if world.inventory.transfer(world, "citizen:" + id,
                    holder, {material: maxi(1, int(task.get("amount", 1)))}, int(person["id"])):
                jobs.erase(id)
                mind["route"] = []
        return true
    var source = Vector2i(int(task["source"][0]), int(task["source"][1]))
    var target = Vector2i(int(task["target"][0]), int(task["target"][1]))
    if left_at(world, source.x, source.y, str(task["material"])) == 0 or not world.is_walkable(target.x, target.y):
        jobs.erase(id)
        mind["route"] = []
        return false
    if walk(world, person, mind, target) and Nav.manhattan(Vector2i(int(person["x"]), int(person["y"])), source) <= 1:
        var material = str(task["material"])
        var use_tool: bool = world.toolmaking.tool_for(world, person, material) != ""
        var local_bonus := 1 if world.occupations.facility_present(world,world.settlements.sid(person),"forestry" if material=="wood" else "quarry") else 0
        var count: int = mini((2 if use_tool else 1)+local_bonus, left_at(world, source.x, source.y, material))
        if world.inventory.extract(world, int(person["id"]), material, source, count):
            world.occupations.on_real_work(world, person,
                "woodcutter" if material == "wood" else "quarry_worker", count)
            task[material] = count # old job inspection stays compatible
            task["amount"] = count
            if use_tool:
                world.toolmaking.wear(world, person, material)
            task["deposit_holder"] = world.local_logistics.deposit_holder(world,person,{material:count})
            task["phase"] = "depot"
            mind["route"] = []
    return true
