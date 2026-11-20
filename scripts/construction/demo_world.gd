extends RefCounted
const World = preload("res://scripts/simulation.gd")
static func create():
    var world = World.new(6001, false)
    for y in range(7,27):
        for x in range(7,27):
            world.set_terrain_cell(x,y,World.MEADOW)
    for cell in [Vector2i(13,16),Vector2i(15,16),Vector2i(14,18),Vector2i(19,16)]:
        world.set_terrain_cell(cell.x,cell.y,World.FOREST)
    world.set_terrain_cell(17,16,World.MOUNTAIN)
    world.capitals[0] = Vector2i(16,16)
    for i in range(20):
        world.add_citizen(16,16,0)
    return world
