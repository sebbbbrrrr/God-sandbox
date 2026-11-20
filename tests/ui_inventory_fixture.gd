extends RefCounted
## A test-only real material / crafting journey, never used by gameplay.
const World = preload("res://scripts/simulation.gd")
static func make_world():
    var w = World.new(22026,false)
    for y in range(14,28):
        for x in range(14,28):
            w.set_terrain_cell(x,y,World.MEADOW)
    w.set_terrain_cell(19,20,World.FOREST)
    w.set_terrain_cell(20,19,World.FOREST)
    w.set_terrain_cell(21,20,World.MOUNTAIN)
    w.set_terrain_cell(20,20,World.TOWN)
    w.capitals[0] = Vector2i(20,20)
    w.add_citizen(20,20,0)
    w.ai_context.begin_tick(w)
    w.construction.houses.append({"id":77,"type":"tool_area","nation":0,"capacity":0,"x":20,"y":20,"built_tick":0})
    w.occupations.grant_capability(w,0,"stone_working","experiment")
    for row in [["stone",Vector2i(21,20),2],["flint",Vector2i(21,20),2],["wood",Vector2i(19,20),2],["plant_fibre",Vector2i(20,19),3],["plant_fibre",Vector2i(20,19),3]]:
        if not w.inventory.extract(w,1,row[0],row[1],row[2]) or not w.inventory.transfer(w,"citizen:1","settlement:0",{row[0]:row[2]},1):
            return null
    for item in ["hammerstone","knapped_flint","cordage","stone_axe","knapped_flint","cordage","stone_axe"]:
        if not w.inventory.craft_at(w,item,1):
            return null
    return w
