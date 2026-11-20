extends RefCounted

static func populate(world: SandboxSimulation) -> void:
    # Authored diagnostic terrain fixtures, applied through authoritative terrain APIs.
    # Both versions use exactly these cells, heights, seed, citizens and camera positions.
    for y in range(20,99):
        for x in range(9,86):
            var type := world.MEADOW
            var height := 1
            if x < 24:
                type = world.OCEAN if x < 17 + (y / 4) % 3 else world.BEACH
                height = 0
            elif x < 45 and y < 56:
                type = world.FOREST
            elif x > 57 and y < 57:
                type = world.MOUNTAIN
                height = clampi(3-maxi(absi(x-70)/7,absi(y-39)/8),1,3)
            world.set_terrain(x,y,type)
            world.visual_elevation[world.index_of(x,y)] = height
    world.capitals = [Vector2i(43,78),Vector2i(51,87)]
    for y in range(72,91,3):
        for x in range(35,57,3):
            world.set_terrain(x,y,world.TOWN)
    world.citizens.clear()
    world.next_id=1
    for i in range(160):
        world.add_citizen(35 + (i*7)%23,70 + (i*11)%23,i%2)
    for i in range(90):world.step()
