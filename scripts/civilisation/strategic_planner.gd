extends RefCounted
# Data-driven, deterministic site ranking. Validity remains the responsibility of
# construction/placement.gd. This never reserves a tile or creates a building.
const DIRECTIONS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

static func rank(world: RefCounted, definition: Dictionary, cell: Vector2i, center: Vector2i, nation: int) -> int:
    var distance := absi(cell.x - center.x) + absi(cell.y - center.y)
    var function_name := str(definition.get("function", ""))
    var category := str(definition.get("category", ""))
    var score := 180 - distance * 8
    # A site's future use matters, not simply its first valid placement.
    # Housing clusters near public access; storage/commerce prioritise roads;
    # agriculture must leave land next to active housing available.
    var road_contacts := 0
    var near_homes := 0
    var near_water := 0
    var near_resources := 0
    for dy in range(-3, 4):
        for dx in range(-3, 4):
            var neighbor := cell + Vector2i(dx, dy)
            var steps := absi(dx) + absi(dy)
            if steps == 0 or steps > 3:
                continue
            if world.index_of(neighbor.x, neighbor.y) < 0:
                continue
            if world.regional_economy.is_road(world, neighbor):
                road_contacts += 3 if steps == 1 else 1
            if steps <= 2 and world.construction.occupied(neighbor.x, neighbor.y):
                near_homes += 1
            if world.at(neighbor.x, neighbor.y) == world.OCEAN:
                near_water += 1
            if world.at(neighbor.x, neighbor.y) in [world.FOREST, world.MOUNTAIN]:
                near_resources += 1
    score += mini(30, road_contacts * 6)
    if function_name == "shelter" or category == "dwelling":
        score += mini(20, near_homes * 5)
        score -= maxi(0, near_resources - 3) * 3
        score -= 8 if near_water > 3 else 0
    elif category in ["commerce", "market", "storage"]:
        score += mini(24, road_contacts * 5)
        score += mini(10, near_homes * 2)
    elif category in ["industrial", "workshop", "production"]:
        score += mini(24, near_resources * 4)
        score -= near_homes * 5
    elif category in ["farm", "agriculture"]:
        score += mini(30, near_water * 4)
        score -= near_homes * 4
    # A stable tie-breaker prevents save/replay differences.
    score -= posmod(cell.x * 3 + cell.y * 7 + nation, 4)
    return score
