extends RefCounted
const World = preload("res://scripts/simulation.gd")

static func create():
    var world = World.new(811, false)
    for y in range(18, 84):
        for x in range(8, 80):
            world.set_terrain_cell(x, y, World.MEADOW)
    for y in range(22, 80, 8):
        for x in range(12, 76, 8):
            world.set_terrain_cell(x, y, World.FOREST)
            world.set_terrain_cell(x + 2, y, World.MOUNTAIN)
    world.capitals[0] = Vector2i(40, 50)
    for i in range(12):
        world.add_citizen(40, 50, 0)
    return world
