extends RefCounted
const Nav = preload("res://scripts/ai/navigation.gd")
const Strategic = preload("res://scripts/civilisation/strategic_planner.gd")
const SURVEY_RADIUS := 6
const MAX_CANDIDATES := 24
const MAX_REACHABLE := 1024
var cache: Dictionary = {} # bounded, non-authoritative local ecology samples
var cursor := 0
var last_candidates := 0
var last_nodes := 0

func invalidate(cell: Vector2i) -> void:
    for key in cache.keys():
        var row: Dictionary = cache[key]
        if Nav.manhattan(cell, Vector2i(int(row["x"]), int(row["y"]))) <= SURVEY_RADIUS:
            cache.erase(key)

func survey(world: RefCounted, cell: Vector2i) -> Dictionary:
    var key := str(world.index_of(cell.x, cell.y))
    if cache.has(key) and world.tick == int(cache[key]["tick"]):
        return cache[key]
    var result := {"x": cell.x, "y": cell.y, "tick": world.tick, "land": 0,
        "wood": 0, "stone": 0, "food": 0, "coast": 0, "hazards": 0}
    for dy in range(-SURVEY_RADIUS, SURVEY_RADIUS + 1):
        for dx in range(-SURVEY_RADIUS, SURVEY_RADIUS + 1):
            if absi(dx) + absi(dy) > SURVEY_RADIUS:
                continue
            var p := cell + Vector2i(dx, dy)
            if world.index_of(p.x, p.y) < 0:
                continue
            if world.at(p.x, p.y) == world.MEADOW:
                result["land"] += 1
            result["wood"] += world.construction.left_at(world, p.x, p.y, "wood")
            result["stone"] += world.construction.left_at(world, p.x, p.y, "stone")
            result["food"] += world.food.resource_left(world, p)
            if world.at(p.x, p.y) == world.BEACH:
                result["coast"] += 1
            if Nav.danger_near(world, p):
                result["hazards"] += 1
    if cache.size() >= 64:
        cache.erase(cache.keys()[0])
    cache[key] = result
    return result

func suitable(world: RefCounted, cell: Vector2i, spacing: bool = true) -> bool:
    var shelter: Dictionary = world.construction.catalogue.definition("primitive_shelter")
    if world.construction.placement.validate(world, shelter, cell, 0) != "" or world.regional_economy.is_road(world, cell):
        return false
    if spacing:
        for key in world.settlements.records:
            var row: Dictionary = world.settlements.records[key]
            if str(row["status"]) in ["failed", "abandoned"]:
                continue
            var other: Vector2i = world.settlements.center(world, int(key))
            if other.x >= 0 and Nav.manhattan(cell, other) < 16:
                return false
        for expedition in world.founding.expeditions.values():
            if str(expedition["phase"]) in ["travel", "camp"] and Nav.manhattan(cell,
                    Vector2i(int(expedition["target"][0]), int(expedition["target"][1]))) < 16:
                return false
    var local := survey(world, cell)
    # No river/freshwater layer exists in this world. Coast is an opportunity
    # score, never misrepresented as drinkable water or a survival prerequisite.
    return int(local["land"]) >= 14 and int(local["wood"]) >= 6 and int(local["stone"]) >= 2 \
        and int(local["food"]) >= 12 and int(local["hazards"]) == 0

func choose_site(world: RefCounted, origin: Vector2i) -> Vector2i:
    # One bounded flood per expedition decision. Candidates come from reachable
    # land; no per-person world scans or unbounded candidate path searches.
    var cells: Array[Vector2i] = [origin]
    var seen := {origin: true}
    var head := 0
    var candidates: Array[Vector2i] = []
    while head < cells.size() and cells.size() < MAX_REACHABLE:
        var here := cells[head]
        head += 1
        var distance := Nav.manhattan(origin, here)
        if distance >= 16 and distance <= 32 and posmod(here.x * 7 + here.y * 11 + world.seed, 13) == 0:
            candidates.append(here)
        for direction in Nav.DIRS:
            var next: Vector2i = here + direction
            if seen.has(next) or Nav.manhattan(origin, next) > 32 or not world.is_walkable(next.x, next.y) or Nav.danger_near(world, next):
                continue
            if cells.size() >= MAX_REACHABLE:
                break
            seen[next] = true
            cells.append(next)
    last_nodes = cells.size()
    last_candidates = 0
    var best := -2147483647
    var chosen := Vector2i(-1, -1)
    for cell in candidates:
        if last_candidates >= MAX_CANDIDATES:
            break
        last_candidates += 1
        if not suitable(world, cell):
            continue
        var local := survey(world, cell)
        var score := mini(120, int(local["food"])) + mini(48, int(local["wood"])) \
            + mini(32, int(local["stone"])) + int(local["land"]) + mini(12, int(local["coast"])) \
            - Nav.manhattan(origin, cell) * 2
        if score > best:
            best = score
            chosen = cell
    return chosen

func reserved(world: RefCounted, id: int, cell: Vector2i) -> bool:
    var row: Dictionary = world.settlements.get_record(id)
    if row.is_empty():
        return false
    var center: Vector2i = world.settlements.center(world, id)
    # Keep a modest communal centre and one expansion/access corridor. Axis
    # depends on actual location, giving deterministic but nonidentical plans.
    var vertical := posmod(center.x + center.y + id, 2) == 0
    return Nav.manhattan(center, cell) <= 1 or (cell.x == center.x if vertical else cell.y == center.y)

func rank(world: RefCounted, definition: Dictionary, cell: Vector2i, center: Vector2i, id: int) -> int:
    if reserved(world, id, cell) or world.regional_economy.is_road(world, cell):
        return -1000000
    # Extend the existing bounded functional ranking; validity stays in the
    # construction footprint authority. No second occupancy/claim authority.
    var score := Strategic.rank(world, definition, cell, center, id)
    var local := survey(world, center)
    var category := str(definition.get("category", ""))
    if category in ["farm", "agriculture"]:
        score += mini(30, int(local["land"]))
    elif category in ["storage", "commerce", "market"]:
        score += 20 - mini(20, Nav.manhattan(cell, center) * 2)
    var function_name := str(definition.get("function",""))
    if function_name in ["forestry","quarry"]:
        var material := "wood" if function_name=="forestry" else "stone"
        var proximity := 0
        for direction in Nav.DIRS:
            for radius in range(1,5):
                var source: Vector2i = cell+direction*radius
                if world.construction.left_at(world,source.x,source.y,material)>0: proximity += 20-radius*3
        score += mini(80,proximity)
    if function_name=="farm" and world.at(cell.x,cell.y)!=world.MEADOW: return -1000000
    return clampi(score, -1000, 1000)

func update_one(world: RefCounted) -> void:
    var keys: Array = world.settlements.records.keys()
    keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
    if keys.is_empty():
        return
    cursor %= keys.size()
    var id := int(keys[cursor])
    cursor += 1
    var row: Dictionary = world.settlements.get_record(id)
    var center: Vector2i = world.settlements.center(world, id)
    if center.x < 0:
        return
    var local := survey(world, center)
    var population: int = world.settlements.population(id)
    var capacity: int = world.settlements.housing(world, id)
    var food: int = world.food.total(world.food.store(id))
    row["plan"] = {"tick": world.tick, "housing_demand": maxi(0, population - capacity),
        "carrying_capacity": clampi(int(local["land"]) / 2 + int(local["food"]) / 6, 6, 72),
        "food": food, "resources": local.duplicate(true), "corridor_axis": posmod(center.x + center.y + id, 2),
        "communal_center": [center.x, center.y]}
    row["prosperity"] = clampi(food * 2 + capacity * 3 - population, 0, 100)
    world.settlement_lifecycle.evaluate(world,id,local)
