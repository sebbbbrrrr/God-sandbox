extends RefCounted
# First physical economy slice: timber/stone gathering, hauling and house construction.
# Simulation owns authoritative state. The renderer sees finished homes as TOWN.
const Nav = preload("res://scripts/ai/navigation.gd")
const HOUSE_WOOD := 3
const HOUSE_STONE := 1
const HOUSE_WORK := 6
const RESOURCE_RADIUS := 12
const MAX_GATHERERS := 4

var stockpiles: Array[Dictionary] = [{"wood": 0, "stone": 0}, {"wood": 0, "stone": 0}]
var depleted: Dictionary = {}
var houses: Array[Dictionary] = []
var projects: Array[Dictionary] = []
var jobs: Dictionary = {}
var next_building_id := 1

func plan(world: RefCounted) -> void:
    if world.tick % 60 != 1:
        return
    for nation in range(2):
        var center: Vector2i = world.capitals[nation]
        if center.x < 0 or not world.is_walkable(center.x, center.y):
            continue
        var population := 0
        var house_count := 0
        for person in world.citizens:
            if int(person["nation"]) == nation and int(person["hp"]) > 0:
                population += 1
        for house in houses:
            if int(house["nation"]) == nation and int(house.get("capacity", 0)) > 0:
                house_count += 1
        if house_count >= mini(12, ceili(float(population) / 6.0)) or not project_for(nation).is_empty():
            continue
        var site := find_house_site(world, center)
        if site.x < 0:
            continue
        projects.append({"id": next_building_id, "nation": nation, "x": site.x,
            "y": site.y, "progress": 0, "reserved": 0})
        next_building_id += 1

func project_for(nation: int) -> Dictionary:
    for project in projects:
        if int(project["nation"]) == nation:
            return project
    return {}

func occupied(x: int, y: int) -> bool:
    for house in houses:
        if int(house["x"]) == x and int(house["y"]) == y:
            return true
    for project in projects:
        if int(project["x"]) == x and int(project["y"]) == y:
            return true
    return false

func find_house_site(world: RefCounted, center: Vector2i) -> Vector2i:
    for distance in range(1, 9):
        for dy in range(-distance, distance + 1):
            for dx in range(-distance, distance + 1):
                if absi(dx) + absi(dy) != distance:
                    continue
                var cell := center + Vector2i(dx, dy)
                if not world.is_walkable(cell.x, cell.y) or world.at(cell.x, cell.y) not in [world.MEADOW, world.TOWN]:
                    continue
                if not occupied(cell.x, cell.y) and not Nav.danger_near(world, cell):
                    return cell
    return Vector2i(-1, -1)

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
    var best := Vector2i(-1, -1)
    var distance := 2147483647
    for cell in [source, source + Vector2i(1, 0), source + Vector2i(0, 1),
            source + Vector2i(-1, 0), source + Vector2i(0, -1)]:
        if world.is_walkable(cell.x, cell.y) and not Nav.danger_near(world, cell):
            var next_distance: int = Nav.manhattan(from, cell)
            if next_distance < distance:
                best = cell
                distance = next_distance
    return best

func source_for(world: RefCounted, person: Dictionary, material: String) -> Dictionary:
    var depot: Vector2i = world.capitals[int(person["nation"])]
    var origin := Vector2i(int(person["x"]), int(person["y"]))
    var result: Dictionary = {}
    var shortest := 2147483647
    for dy in range(-RESOURCE_RADIUS, RESOURCE_RADIUS + 1):
        for dx in range(-RESOURCE_RADIUS, RESOURCE_RADIUS + 1):
            if absi(dx) + absi(dy) > RESOURCE_RADIUS:
                continue
            var source := depot + Vector2i(dx, dy)
            if left_at(world, source.x, source.y, material) <= 0:
                continue
            var target := approach(world, origin, source)
            if target.x < 0:
                continue
            var score: int = Nav.manhattan(origin, target) + Nav.manhattan(target, depot)
            if score < shortest:
                shortest = score
                result = {"source": [source.x, source.y], "target": [target.x, target.y]}
    return result

func gatherer_count(nation: int) -> int:
    var result := 0
    for job in jobs.values():
        if str(job["kind"]) == "gather" and int(job["nation"]) == nation:
            result += 1
    return result

func missing_material(nation: int) -> String:
    var timber_in_transit := 0
    var stone_in_transit := 0
    for job in jobs.values():
        if str(job["kind"]) != "gather" or int(job["nation"]) != nation:
            continue
        if str(job["material"]) == "wood":
            timber_in_transit += maxi(1, int(job.get("amount", 0)))
        elif str(job["material"]) == "stone":
            stone_in_transit += maxi(1, int(job.get("amount", 0)))
    if int(stockpiles[nation]["wood"]) + timber_in_transit < HOUSE_WOOD:
        return "wood"
    if int(stockpiles[nation]["stone"]) + stone_in_transit < HOUSE_STONE:
        return "stone"
    return ""

func work_step(world: RefCounted, person: Dictionary, mind: Dictionary) -> bool:
    var nation: int = int(person["nation"])
    var id := str(person["id"])
    var depot: Vector2i = world.capitals[nation]
    if depot.x < 0 or not world.is_walkable(depot.x, depot.y):
        return false
    if not jobs.has(id):
        var project := project_for(nation)
        if project.is_empty():
            return false
        var job: Dictionary = {}
        var profession: String = str(world.occupations.record_for(person).get("preference", ""))
        if int(person["id"]) % 5 == 0 or profession == "shelter_builder":
            # Skilled/aspiring builders can reserve an actual construction job.
            if int(project["reserved"]) != 0:
                return false
            project["reserved"] = int(person["id"])
            job = {"kind": "build", "nation": nation, "project_id": int(project["id"]),
                "phase": "depot", "wood": 0, "stone": 0}
        else:
            if gatherer_count(nation) >= MAX_GATHERERS:
                return false
            var material := missing_material(nation)
            if material.is_empty():
                return false
            world.toolmaking.try_equip(world, person, material)
            var source := source_for(world, person, material)
            if source.is_empty():
                return false
            job = {"kind": "gather", "nation": nation, "phase": "source",
                "material": material, "source": source["source"], "target": source["target"],
                "wood": 0, "stone": 0, "amount": 0}
        jobs[id] = job
        mind["route"] = []
        mind["next_path_tick"] = world.tick
    var task: Dictionary = jobs[id]
    if str(task["kind"]) == "gather":
        return gather_step(world, person, mind, id, task, depot)
    return build_step(world, person, mind, id, task, depot)

func walk(world: RefCounted, person: Dictionary, mind: Dictionary, target: Vector2i) -> bool:
    var previous := Vector2i(int(person["x"]), int(person["y"]))
    if previous == target:
        return true
    var next: Vector2i = Nav.next_step(world, person, mind, target)
    if next != previous:
        person["x"] = next.x
        person["y"] = next.y
        world.ai_context.moved(person, previous)
    return next == target

func gather_step(world: RefCounted, person: Dictionary, mind: Dictionary, id: String, task: Dictionary, depot: Vector2i) -> bool:
    if str(task["phase"]) == "depot":
        if walk(world, person, mind, depot):
            var material := str(task["material"])
            if world.inventory.transfer(world, "citizen:" + id,
                    "settlement:" + str(task["nation"]), {material: maxi(1, int(task.get("amount", 1)))}, int(person["id"])):
                jobs.erase(id)
                mind["route"] = []
        return true
    var source := Vector2i(int(task["source"][0]), int(task["source"][1]))
    var target := Vector2i(int(task["target"][0]), int(task["target"][1]))
    if left_at(world, source.x, source.y, str(task["material"])) == 0 or not world.is_walkable(target.x, target.y):
        jobs.erase(id)
        mind["route"] = []
        return false
    if walk(world, person, mind, target) and Nav.manhattan(Vector2i(int(person["x"]), int(person["y"])), source) <= 1:
        var material := str(task["material"])
        var use_tool: bool = world.toolmaking.tool_for(world, person, material) != ""
        var count: int = mini(2 if use_tool else 1, left_at(world, source.x, source.y, material))
        if world.inventory.extract(world, int(person["id"]), material, source, count):
            world.occupations.on_real_work(world, person,
                "woodcutter" if material == "wood" else "quarry_worker", count)
            task[material] = count # old job inspection stays compatible
            task["amount"] = count
            if use_tool:
                world.toolmaking.wear(world, person, material)
            task["phase"] = "depot"
            mind["route"] = []
    return true

func build_step(world: RefCounted, person: Dictionary, mind: Dictionary, id: String, task: Dictionary, depot: Vector2i) -> bool:
    var project: Dictionary = {}
    for item in projects:
        if int(item["id"]) == int(task["project_id"]):
            project = item
            break
    if project.is_empty():
        # Cancelled project: no instant refund; physically carry cargo home.
        if int(task["wood"]) + int(task["stone"]) > 0:
            if walk(world, person, mind, depot):
                var refund: Dictionary = {}
                for material in ["wood", "stone"]:
                    if int(task[material]) > 0:
                        refund[material] = int(task[material])
                if world.inventory.transfer(world, "citizen:" + id,
                        "settlement:" + str(task["nation"]), refund, int(person["id"])):
                    jobs.erase(id)
            return true
        jobs.erase(id)
        return false
    if str(task["phase"]) == "depot":
        if walk(world, person, mind, depot):
            if int(stockpiles[int(task["nation"])]["wood"]) < HOUSE_WOOD or int(stockpiles[int(task["nation"])]["stone"]) < HOUSE_STONE:
                return true  # builder waits at depot for supplies, never fabricates them
            if not world.inventory.transfer(world, "settlement:" + str(task["nation"]),
                    "citizen:" + id, {"wood": HOUSE_WOOD, "stone": HOUSE_STONE}, int(person["id"])):
                return true
            task["wood"] = HOUSE_WOOD
            task["stone"] = HOUSE_STONE
            task["phase"] = "site"
            mind["route"] = []
        return true
    var site := Vector2i(int(project["x"]), int(project["y"]))
    if not world.is_walkable(site.x, site.y) or Nav.danger_near(world, site):
        return false
    if walk(world, person, mind, site):
        # Expertise reduces required labour while never skipping actual
        # construction actions or creating free materials.
        var effort: int = 1 + (1 if world.occupations.skill_tier(person, "shelter_builder") >= 3 else 0)
        project["progress"] = mini(HOUSE_WORK, int(project["progress"]) + effort)
        world.occupations.on_real_work(world, person, "shelter_builder")
        if int(project["progress"]) == HOUSE_WORK:
            if not world.inventory.consume(world, "citizen:" + id,
                    {"wood": HOUSE_WOOD, "stone": HOUSE_STONE}, int(person["id"]), "house"):
                return false
            houses.append({"id": int(project["id"]), "nation": int(project["nation"]),
                "x": site.x, "y": site.y, "capacity": 6, "built_tick": int(world.tick)})
            for i in range(projects.size()):
                if int(projects[i]["id"]) == int(project["id"]):
                    projects.remove_at(i)
                    break
            jobs.erase(id)
            world.set_terrain_cell(site.x, site.y, world.TOWN)
            mind["route"] = []
    return true

func on_terrain_changed(world: RefCounted, x: int, y: int) -> void:
    depleted.erase(str(world.index_of(x, y)))
    if world.at(x, y) in [world.MEADOW, world.TOWN]:
        return
    for i in range(houses.size() - 1, -1, -1):
        if int(houses[i]["x"]) == x and int(houses[i]["y"]) == y:
            houses.remove_at(i)
    for i in range(projects.size() - 1, -1, -1):
        if int(projects[i]["x"]) == x and int(projects[i]["y"]) == y:
            projects.remove_at(i)

func prune(world: RefCounted) -> void:
    world.inventory.reconcile_deaths(world)
    # Direct brush/terrain writes can bypass the official setter.
    for i in range(houses.size() - 1, -1, -1):
        if world.at(int(houses[i]["x"]), int(houses[i]["y"])) != world.TOWN:
            houses.remove_at(i)
    for i in range(projects.size() - 1, -1, -1):
        var project: Dictionary = projects[i]
        if world.at(int(project["x"]), int(project["y"])) not in [world.MEADOW, world.TOWN]:
            projects.remove_at(i)
    for key in jobs.keys():
        var person: Dictionary = world.ai_context.people.get(int(key), {})
        if not person.is_empty() and int(person["hp"]) > 0:
            continue
        var job: Dictionary = jobs[key]
        # Carried resources are lost with a dead worker; no magical refund.
        if str(job["kind"]) == "build":
            for project in projects:
                if int(project["id"]) == int(job["project_id"]):
                    project["reserved"] = 0
        jobs.erase(key)

func snapshot() -> Dictionary:
    return {"version": 1, "stockpiles": stockpiles.duplicate(true), "depleted": depleted.duplicate(true),
        "houses": houses.duplicate(true), "projects": projects.duplicate(true),
        "jobs": jobs.duplicate(true), "next_building_id": next_building_id}

func load_state(raw: Variant) -> void:
    if not raw is Dictionary:
        return
    if int(raw.get("version", 0)) != 1:
        return
    if raw.get("stockpiles") is Array and raw["stockpiles"].size() == 2:
        for i in range(2):
            var entry: Variant = raw["stockpiles"][i]
            if entry is Dictionary:
                stockpiles[i] = {"wood": maxi(0, int(entry.get("wood", 0))),
                    "stone": maxi(0, int(entry.get("stone", 0)))}
    if raw.get("depleted") is Dictionary:
        for key in raw["depleted"]:
            var n := int(raw["depleted"][key])
            if n > 0:
                depleted[str(key)] = mini(10, n)
    if raw.get("houses") is Array:
        for entry in raw["houses"]:
            if entry is Dictionary and int(entry.get("id", 0)) > 0:
                houses.append(entry.duplicate(true))
    if raw.get("projects") is Array:
        for entry in raw["projects"]:
            if entry is Dictionary and int(entry.get("id", 0)) > 0:
                projects.append(entry.duplicate(true))
    if raw.get("jobs") is Dictionary:
        for key in raw["jobs"]:
            var job: Variant = raw["jobs"][key]
            if job is Dictionary and str(job.get("kind", "")) in ["build", "gather"]:
                jobs[str(key)] = job.duplicate(true)
    next_building_id = maxi(1, int(raw.get("next_building_id", 1)))
