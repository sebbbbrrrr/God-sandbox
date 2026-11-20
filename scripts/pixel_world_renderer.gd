extends Node2D
class_name PixelWorldRenderer

const Atlas = preload("res://scripts/pixel_atlas.gd")
const Chunk = preload("res://scripts/pixel_chunk.gd")
const Commands = preload("res://scripts/pixel_commands.gd")
const TILE := 32
const CHUNK := 16
const RISE := 12
const DIRECTIONS := [Vector2i(0,-1), Vector2i(1,0), Vector2i(0,1), Vector2i(-1,0)]
const DIAGONALS := [Vector2i(-1,-1), Vector2i(1,-1), Vector2i(1,1), Vector2i(-1,1)]
var world: SandboxSimulation
var atlas: PixelAtlas
var chunks: Dictionary = {}
var unit_rows: Array[PixelCommands] = []
var effects: PixelCommands
var detail := 1
var visible_rect := Rect2()
var visible_chunks := 0
var effect_clock := 0.0
var effect_phase := 0
var rebuilds := 0
var path_cells: Dictionary = {}
var town_cells: Dictionary = {}
var paths_dirty := true
var view_dirty := true
var previous_screen_rect := Rect2()
var previous_screen_tile := -1.0

func setup(simulation: SandboxSimulation) -> void:
    world = simulation
    atlas = Atlas.new()
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    z_index = -1000
    for cy in range(ceili(float(world.HEIGHT) / CHUNK)):
        for cx in range(ceili(float(world.WIDTH) / CHUNK)):
            var coord := Vector2i(cx,cy)
            var chunk := Chunk.new()
            chunk.setup(atlas, coord)
            chunk.visible = false
            add_child(chunk)
            chunks[coord] = chunk
    for y in range(world.HEIGHT):
        var row := Commands.new()
        row.atlas = atlas
        row.z_index = 101 + y * 2
        add_child(row)
        unit_rows.append(row)
    effects = Commands.new()
    effects.atlas = atlas
    effects.z_index = 500
    add_child(effects)
    world.terrain_changed.connect(invalidate_cell)
    rebuild_paths()

static func variation(x: int, y: int, world_seed: int, count: int) -> int:
    # Coordinate hash never touches simulation RNG or frame time.
    var h := (x * 374761393 + y * 668265263 + world_seed * 31) & 0x7fffffff
    h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
    return posmod(h ^ (h >> 16), count)

func invalidate_cell(cell: Vector2i) -> void:
    view_dirty = true
    # A one-tile halo catches cardinal and diagonal transitions across boundaries.
    for dy in range(-1,2):
        for dx in range(-1,2):
            var q := cell + Vector2i(dx,dy)
            if world.index_of(q.x,q.y) < 0:
                continue
            var c := Vector2i(q.x / CHUNK, q.y / CHUNK)
            if chunks.has(c):
                chunks[c].dirty = true
    if world.at(cell.x,cell.y)==world.TOWN or town_cells.has(cell) or path_cells.has(cell):
        paths_dirty=true
    effect_clock = 1.0

func mask_for(x: int, y: int, type: int) -> int:
    var mask := 0
    for i in range(4):
        var q: Vector2i = Vector2i(x,y) + DIRECTIONS[i]
        if world.at(q.x,q.y) == type:
            mask |= 1 << i
    return mask

func land_mask(x: int, y: int) -> int:
    var mask := 0
    for i in range(4):
        var q: Vector2i = Vector2i(x,y) + DIRECTIONS[i]
        if world.at(q.x,q.y) != world.OCEAN:
            mask |= 1 << i
    return mask

func top_left(x: int, y: int) -> Vector2:
    return Vector2(x*TILE, y*TILE-world.height_at(x,y)*RISE)

func tile_center(cell: Vector2i) -> Vector2:
    return top_left(cell.x,cell.y)+Vector2(16,16)

func tile_at(pixel: Vector2) -> Vector2i:
    var base := Vector2i(floori(pixel.x / TILE),floori(pixel.y / TILE))
    # Frontmost raised top wins; clicks on a cliff face fall back to its grid cell.
    for y in range(base.y+2,base.y-2,-1):
        if world.index_of(base.x,y) >= 0 and Rect2(top_left(base.x,y),Vector2(TILE,TILE)).has_point(pixel):
            return Vector2i(base.x,y)
    return base

func update_view(origin: Vector2, screen_tile: float, screen_rect: Rect2) -> void:
    if not view_dirty and not paths_dirty and position==origin.round() and previous_screen_tile==screen_tile and previous_screen_rect==screen_rect:
        return
    previous_screen_tile=screen_tile
    previous_screen_rect=screen_rect
    view_dirty=false
    position = origin.round()
    scale = Vector2.ONE * screen_tile / TILE
    var a := (screen_rect.position-position) / scale
    var b := (screen_rect.end-position) / scale
    visible_rect = Rect2(a,b-a).grow(64)
    detail = 0 if screen_tile < 13 else (1 if screen_tile < 30 else 2)
    if paths_dirty:
        rebuild_paths()
    visible_chunks = 0
    for coord in chunks:
        var chunk: PixelChunk = chunks[coord]
        chunk.visible = visible_rect.intersects(Rect2(Vector2(coord)*CHUNK*TILE, Vector2.ONE*CHUNK*TILE).grow(64))
        if not chunk.visible:
            continue
        visible_chunks += 1
        if chunk.dirty or chunk.built_detail != detail:
            build_chunk(chunk)
            rebuilds += 1
    for y in range(unit_rows.size()):
        unit_rows[y].visible = y*TILE >= visible_rect.position.y-64 and y*TILE <= visible_rect.end.y+64

func build_chunk(chunk: PixelChunk) -> void:
    chunk.clear_commands()
    var start := chunk.coord * CHUNK
    for y in range(start.y,mini(start.y+CHUNK,world.HEIGHT)):
        for x in range(start.x,mini(start.x+CHUNK,world.WIDTH)):
            build_cell(chunk,x,y)
    if detail==0:
        bake_distant_chunk(chunk)
    chunk.finish(detail)

func bake_distant_chunk(chunk: PixelChunk) -> void:
    # At the distant zoom one source texel is 4 logical pixels. Static terrain and
    # props become ONE draw per chunk; units/water highlights stay live above it.
    var image := Image.create(176,176,false,Image.FORMAT_RGBA8)
    var offset := Vector2(chunk.coord)*CHUNK*TILE-Vector2.ONE*96
    var ordered: Array[PixelCommands] = []
    ordered.append_array(chunk.layers)
    ordered.append_array(chunk.rows)
    for layer in ordered:
        for i in range(layer.keys.size()):
            var part := atlas.miniature(layer.keys[i],layer.sizes[i],layer.tints[i])
            image.blend_rect(part,Rect2i(Vector2i.ZERO,part.get_size()),Vector2i(((layer.positions[i]-offset)/4.0).round()))
    if chunk.far_sprite.texture==null:
        chunk.far_sprite.texture=ImageTexture.create_from_image(image)
    else:
        (chunk.far_sprite.texture as ImageTexture).update(image)

func build_cell(chunk: PixelChunk, x: int, y: int) -> void:
    var type := world.at(x,y)
    var p := top_left(x,y)
    var v := variation(x,y,world.seed,4)
    var is_capital := Vector2i(x,y) in world.capitals and world.is_walkable(x,y) and type!=world.ASH
    var water := chunk.layers[0]
    var ground := chunk.layers[1]
    var transitions := chunk.layers[2]
    var cliffs := chunk.layers[3]
    var decor := chunk.layers[4]
    var objects: PixelCommands = chunk.rows[y % CHUNK]
    if type == world.OCEAN:
        water.add("water_%d" % v,Vector2(x*TILE,y*TILE))
        var shores := land_mask(x,y)
        if shores:
            water.add("shallow_edge_%d" % shores,p)
            transitions.add("shore_edge_%d" % shores,p)
        for i in range(4):
            var q: Vector2i = Vector2i(x,y) + DIAGONALS[i]
            var adjacent: int = [9,3,6,12][i]
            if shores & adjacent == 0 and world.at(q.x,q.y) != world.OCEAN:
                transitions.add("shore_corner_%d" % i,p)
        return
    var family := "meadow"
    match type:
        world.BEACH: family = "sand"
        world.FOREST: family = "forest"
        world.MOUNTAIN: family = "rock"
        world.ASH: family = "ash"
        world.TOWN: family = "earth"
    if is_capital:
        family = "earth"
    ground.add("%s_%d" % [family,0 if family == "earth" else v],p)
    if type == world.MOUNTAIN and v == 0:
        ground.add("mountain_%d" % v,p)
    var ocean_mask := mask_for(x,y,world.OCEAN)
    if ocean_mask:
        transitions.add("coast_cut_%d" % ocean_mask,p)
    # Beach-to-meadow edges spread vegetation into sand instead of a straight line.
    if type == world.BEACH:
        var grass_mask := mask_for(x,y,world.MEADOW) | mask_for(x,y,world.FOREST)
        if grass_mask: transitions.add("meadow_edge_%d" % grass_mask,p)
    # Overlay higher-priority neighbouring biome edges without hard tile borders.
    for other in [world.FOREST,world.BEACH,world.ASH,world.TOWN,world.MOUNTAIN]:
        if other == type:
            continue
        var mask := mask_for(x,y,other)
        if mask == 0:
            continue
        var edge_family: String = {world.FOREST:"forest",world.BEACH:"dirt",world.ASH:"ash",world.TOWN:"earth",world.MOUNTAIN:"rock"}[other]
        if type != world.MOUNTAIN:
            transitions.add("%s_edge_%d" % [edge_family,mask],p)
    var height := world.height_at(x,y)
    var south_drop := height-world.height_at(x,y+1)
    var east_drop := height-world.height_at(x+1,y)
    if south_drop > 0:
        var face_height := south_drop*RISE+4
        cliffs.add("cliff_%d" % variation(x,y,world.seed,8),p+Vector2(0,TILE-4),Vector2(TILE,face_height))
        cliffs.add("contact_shadow",p+Vector2(0,TILE+face_height-5),Vector2(TILE,12))
    if east_drop > 0:
        cliffs.add("cliff_east",p,Vector2(TILE,TILE),Color(1,1,1,0.38))
        if v%2==0 and detail>0:
            prop(decor,"moss_rock",p+Vector2(30,24),0.42)
    if south_drop>0 and east_drop>0:
        cliffs.add("cliff_outer",p+Vector2(16,TILE-4),Vector2(16,south_drop*RISE+4))
    elif south_drop>0 and world.height_at(x+1,y+1)>=height:
        cliffs.add("cliff_inner",p+Vector2(16,TILE-4),Vector2(16,south_drop*RISE+4))
    var cell := Vector2i(x,y)
    if path_cells.has(cell) and type!=world.ASH:
        var path: int = path_cells[cell]
        decor.add("path_h" if path==1 else ("path_v" if path==2 else "path_cross"),p)
    var salt := variation(x,y,world.seed+17,100)
    if type == world.TOWN or is_capital:
        var building: String = "town_hall" if is_capital else ["hut","cottage","workshop","cottage"][v]
        prop(objects,building,p+Vector2(16,25))
        if detail > 0:
            prop(decor,"fence_h",p+Vector2(18,31))
            if v == 0: prop(decor,"barrels",p+Vector2(29,24),0.65)
        return
    if type == world.FOREST:
        if (detail > 0 or salt < 40) and not path_cells.has(cell):
            var tree := "pine_%d" % variation(x,y,world.seed,5)
            var offset := Vector2(9+variation(x,y,world.seed+3,12),24+variation(x,y,world.seed+4,7))
            prop(objects,tree,p+offset,0.87+v*0.06)
        if detail == 2 and salt < 26:
            prop(decor,"fern",p+Vector2(5,28),0.55)
    elif type == world.MEADOW:
        if salt < 7 and detail > 0 and not path_cells.has(cell):
            prop(objects,"pine_%d" % v,p+Vector2(17,28),0.78)
        elif salt < 20 and detail > 0:
            prop(decor,["bush","grass","flowers_white","flowers_gold"][v],p+Vector2(16,28),0.6)
        elif salt < 23 and detail == 2:
            prop(decor,"log" if v == 0 else "stump",p+Vector2(18,26),0.6)
    elif type == world.MOUNTAIN:
        prop(objects,"rock_tall" if v%2==0 else "moss_rock",p+Vector2(17,27),1.0+v*0.15)
    elif type == world.ASH and salt < 15 and detail > 0:
        prop(decor,"stump",p+Vector2(17,25),0.7,Color(0.5,0.47,0.44))
    if salt >= 93 and type != world.ASH and detail > 0:
        prop(decor,"rock_small" if v%2==0 else "rock_medium",p+Vector2(17,25),0.6)

func rebuild_paths() -> void:
    path_cells.clear()
    town_cells.clear()
    for y in range(world.HEIGHT):
        for x in range(world.WIDTH):
            if world.at(x,y)!=world.TOWN: continue
            var cell := Vector2i(x,y)
            town_cells[cell]=true
            var capital: Vector2i = world.capitals[0]
            if cell.distance_squared_to(world.capitals[1])<cell.distance_squared_to(capital):
                capital=world.capitals[1]
            if world.index_of(capital.x,capital.y)<0: continue
            var steps := maxi(absi(cell.x-capital.x),absi(cell.y-capital.y))
            var previous := cell
            for i in range(steps+1):
                var point := Vector2i(Vector2(cell).lerp(Vector2(capital),float(i)/maxi(steps,1)).round())
                if not world.is_walkable(point.x,point.y): break
                if point.x!=previous.x and point.y!=previous.y:
                    var elbow := Vector2i(point.x,previous.y)
                    if not world.is_walkable(elbow.x,elbow.y): break
                    path_cells[elbow]=3
                    path_cells[previous]=int(path_cells.get(previous,0))|1
                    path_cells[point]=int(path_cells.get(point,0))|2
                var direction := 1 if point.x!=previous.x else 2
                path_cells[point]=int(path_cells.get(point,0))|direction
                path_cells[previous]=int(path_cells.get(previous,0))|direction
                previous=point
    for chunk in chunks.values(): chunk.dirty=true
    paths_dirty=false

func prop(layer: PixelCommands, key: String, foot: Vector2, factor: float = 1.0, tint: Color = Color.WHITE) -> void:
    var sz := atlas.size_of(key)*factor
    layer.add(key,(foot-Vector2(sz.x*0.5,sz.y)).round(),sz.round(),tint)

func refresh_units() -> void:
    for row in unit_rows:
        row.clear_commands()
    for citizen in world.citizens:
        if citizen["hp"] <= 0:
            continue
        var x: int = citizen["x"]
        var y: int = citizen["y"]
        var p := top_left(x,y)+Vector2(12+citizen["id"]%9,25)
        prop(unit_rows[y],"citizen_gold" if citizen["nation"]==0 else "citizen_rose",p,0.9)
    for row in unit_rows:
        row.queue_redraw()

func animate(delta: float) -> void:
    effect_clock += delta
    if effect_clock < 0.25:
        return
    effect_clock = 0.0
    effect_phase = (effect_phase+1)%4
    effects.clear_commands()
    var count := 0
    for y in range(maxi(0,floori(visible_rect.position.y/TILE)),mini(world.HEIGHT,ceili(visible_rect.end.y/TILE))):
        for x in range(maxi(0,floori(visible_rect.position.x/TILE)),mini(world.WIDTH,ceili(visible_rect.end.x/TILE))):
            if count >= 96:
                break
            if world.at(x,y)==world.OCEAN and variation(x,y,world.seed,17)==0:
                var p := Vector2(x*TILE+effect_phase*2,y*TILE+16)
                effects.add("ripple",p,Vector2(14,5),Color(0.65,0.91,0.94,0.22+effect_phase*0.06))
                count+=1
    effects.queue_redraw()

func add_power_effect(power: int, cell: Vector2i) -> void:
    # Short, bounded effects; permanent ash remains part of terrain state.
    if power == 1 or power == 3:
        prop(effects,"fire" if power==1 else "blessing",tile_center(cell)+Vector2(0,8),1.3)
        effects.queue_redraw()
