extends RefCounted
const Nav = preload("res://scripts/ai/navigation.gd")
const DIRS := [Vector2i(1,0), Vector2i(0,1), Vector2i(-1,0), Vector2i(0,-1)]
var tiles: Dictionary = {} # O(1) occupied/reserved footprint lookup, rebuilt after load.

func footprint(row: Dictionary, cell: Vector2i, orientation: int) -> Array[Vector2i]:
    var size: Array = row.get("footprint", [1, 1])
    var width = int(size[orientation % 2])
    var height = int(size[1 - orientation % 2])
    var result: Array[Vector2i] = []
    for y in range(height):
        for x in range(width):
            result.append(cell + Vector2i(x, y))
    return result

func validate(world: RefCounted, row: Dictionary, cell: Vector2i, orientation: int,
        ignore_id: int = 0) -> String:
    if row.is_empty() or orientation not in row.get("orientations", [0]):
        return "definition_or_orientation"
    var cells = footprint(row, cell, orientation)
    var access = false
    var shoreline = false
    var elevation = world.height_at(cell.x, cell.y)
    for point in cells:
        if world.index_of(point.x, point.y) < 0:
            return "bounds"
        var biome: String = str(["ocean", "beach", "meadow", "forest", "mountain", "ash", "town"][world.at(point.x, point.y)])
        if biome not in row["placement"]["terrain"] or Nav.danger_near(world, point):
            return "terrain"
        for farm in world.food.farms:
            if int(farm["x"])==point.x and int(farm["y"])==point.y and not bool(farm["harvested"]): return "agriculture"
        if tiles.has(point) and int(tiles[point]) != ignore_id:
            return "overlap"
        if absi(world.height_at(point.x, point.y) - elevation) > int(row["placement"].get("max_elevation_difference", 3)):
            return "elevation"
        var spacing = int(row["placement"].get("min_spacing", 0))
        for dy in range(-spacing, spacing + 1):
            for dx in range(-spacing, spacing + 1):
                var near = point + Vector2i(dx, dy)
                if tiles.has(near) and int(tiles[near]) != ignore_id:
                    return "spacing"
        for direction in DIRS:
            var next: Vector2i = point + direction
            if world.at(next.x, next.y) == world.OCEAN:
                shoreline = true
            if next not in cells and world.is_walkable(next.x, next.y) and not Nav.danger_near(world, next):
                access = true
    if not access:
        return "access"
    var coast: String = str(row["placement"].get("shoreline", "any"))
    if (coast == "required" and not shoreline) or (coast == "forbidden" and shoreline):
        return "shoreline"
    var water_radius := int(row["placement"].get("water_radius",0))
    if water_radius>0:
        var water := false
        for dy in range(-water_radius,water_radius+2):
            for dx in range(-water_radius,water_radius+2):
                if world.at(cell.x+dx,cell.y+dy)==world.OCEAN: water = true
        if not water: return "water_source"
    var requirement: Dictionary = row["placement"].get("resource_nearby",{})
    if not requirement.is_empty():
        var found := false
        var radius := int(requirement["radius"])
        for dy in range(-radius,radius+1):
            for dx in range(-radius,radius+1):
                if absi(dx)+absi(dy)>radius: continue
                for material in requirement["materials"]:
                    if world.construction.left_at(world,cell.x+dx,cell.y+dy,str(material))>0: found = true
        if not found: return "ore_deposit"
    return ""

func claim(row: Dictionary, entity: Dictionary) -> void:
    for cell in footprint(row, Vector2i(int(entity["x"]), int(entity["y"])), int(entity.get("orientation", 0))):
        tiles[cell] = int(entity["id"])

func release(id: int) -> void:
    for cell in tiles.keys():
        if int(tiles[cell]) == id:
            tiles.erase(cell)
