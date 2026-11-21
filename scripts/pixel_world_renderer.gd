extends Node2D
class_name PixelWorldRenderer

const Atlas = preload("res://scripts/pixel_atlas.gd")
const Chunk = preload("res://scripts/pixel_chunk.gd")
const Commands = preload("res://scripts/pixel_commands.gd")
const Weather = preload("res://scripts/weather_cycle.gd")
const RainOverlay = preload("res://scripts/weather_overlay.gd")
const Walk = preload("res://scripts/citizen_walk.gd")
const TILE := 32
const CHUNK := 16
const RISE := 12
const DIRECTIONS := [Vector2i(0,-1), Vector2i(1,0), Vector2i(0,1), Vector2i(-1,0)]
const BIOMES := [3,1,5,6,4]
const EDGE_FAMILY := ["","dirt","","forest","rock","ash","earth"]
const TREE_SPECIES := ["pine_0","pine_1","pine_2","pine_3","pine_4","oak","birch","willow","beech","spruce","cedar","juniper"]
const SMALL_PLANTS := ["berry_shrub","fern_cluster","wildflowers","tall_grass","mushrooms","leaf_litter","branches","exposed_roots"]
const BUILDINGS := ["hut_a","hut_b","cottage_a","cottage_b","stone_house_a","stone_house_b","workshop_a","workshop_b","storage_a","storage_b","farmhouse_a","farmhouse_b","barn_a","barn_b","market_a","market_b","watchtower_a","watchtower_b"]
const DIAGONALS := [Vector2i(-1,-1), Vector2i(1,-1), Vector2i(1,1), Vector2i(-1,1)]
var world: SandboxSimulation
var atlas: PixelAtlas
var chunks: Dictionary = {}
var unit_rows: Array[PixelCommands] = []
var walks: CitizenWalk
var walk_draw_accum := 0.0
var rendered_building_count := -1
var rendered_roads_revision := -1
var facility_cells: Dictionary = {}
var physical_buildings: Dictionary = {}
var physical_footprints: Dictionary = {}
var effects: PixelCommands
var weather: SandboxWeather
var weather_overlay: PixelWeatherOverlay
var sway_clock := 0.0
var sway_accum := 0.0
const SWAY_INTERVAL := 1.0 / 15.0
var detail := 1
var visible_rect := Rect2()
var visible_chunks := 0
var effect_clock := 0.0
var effect_phase := 0
var rebuilds := 0
var path_cells: Dictionary = {}
var path_barriers: Dictionary = {}
var town_cells: Dictionary = {}
var building_cells: Dictionary = {}
var paths_dirty := true
var view_dirty := true
var previous_screen_rect := Rect2()
var previous_screen_tile := -1.0

func setup(simulation: SandboxSimulation) -> void:
    world = simulation
    weather = Weather.new(world.seed)
    weather.set_time(float(world.tick) * 0.1)
    atlas = Atlas.new()
    walks = Walk.new()
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
    weather_overlay = RainOverlay.new()
    weather_overlay.z_index = 501
    add_child(weather_overlay)
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
    if (world.at(cell.x,cell.y)==world.TOWN) != town_cells.has(cell) or (path_cells.has(cell) and not world.is_walkable(cell.x,cell.y)) or (path_barriers.has(cell) and world.is_walkable(cell.x,cell.y)):
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

func scorch_exposure(x: int, y: int) -> int:
    var exposure := 0
    for i in range(4):
        var neighbour: Vector2i = Vector2i(x, y) + DIRECTIONS[i]
        if world.at(neighbour.x, neighbour.y) != world.ASH:
            exposure |= 1 << i
    for i in range(4):
        var diagonal: Vector2i = Vector2i(x, y) + DIAGONALS[i]
        if world.at(diagonal.x, diagonal.y) != world.ASH:
            exposure |= 1 << (i + 4)
    return exposure

# Existing saves only contain ASH, not the terrain that burned. Approximate the
# exposed substrate from the closest unburned cardinal/diagonal neighbour rather
# than adding a new save format or changing simulation mechanics.
func scorch_underlay(x: int, y: int) -> String:
    for direction in DIRECTIONS + DIAGONALS:
        var neighbour: Vector2i = Vector2i(x, y) + direction
        var biome: int = world.at(neighbour.x, neighbour.y)
        match biome:
            world.FOREST:
                return "forest"
            world.BEACH:
                return "sand"
            world.MOUNTAIN:
                return "rock"
            world.TOWN:
                return "earth"
            world.MEADOW:
                return "meadow"
    # Coastal scars expose sand where there is no adjacent surviving land.
    for direction in DIRECTIONS + DIAGONALS:
        var neighbour: Vector2i = Vector2i(x, y) + direction
        if world.at(neighbour.x, neighbour.y) == world.OCEAN:
            return "sand"
    return "meadow"

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
    if world.construction.houses.size() != rendered_building_count or world.regional_economy.revision != rendered_roads_revision:
        paths_dirty = true
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
    weather_overlay.update_weather(visible_rect, sway_clock, weather.rain_strength, weather.wind_direction, world.seed)
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
    render_units()

func build_chunk(chunk: PixelChunk) -> void:
    chunk.clear_commands()
    var start := chunk.coord * CHUNK
    for y in range(start.y,mini(start.y+CHUNK,world.HEIGHT)):
        for x in range(start.x,mini(start.x+CHUNK,world.WIDTH)):
            build_cell(chunk,x,y)
    if detail==0:
        bake_distant_chunk(chunk)
    for row in chunk.wind_rows:
        row.sway_time = sway_clock
        row.wind_strength = weather.wind_strength
        row.wind_x = weather.wind_direction.x
    chunk.finish(detail)

func bake_distant_chunk(chunk: PixelChunk) -> void:
    # At the distant zoom one source texel is 4 logical pixels. Static terrain and
    # props become ONE draw per chunk; units/water highlights stay live above it.
    var image := Image.create(176,176,false,Image.FORMAT_RGBA8)
    var offset := Vector2(chunk.coord)*CHUNK*TILE-Vector2.ONE*96
    var ordered: Array[PixelCommands] = []
    ordered.append_array(chunk.layers)
    for i in range(chunk.rows.size()):
        ordered.append(chunk.rows[i])
        ordered.append(chunk.wind_rows[i])
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
    var neighbour_masks := [0,0,0,0,0,0,0]
    for i in range(4):
        var q: Vector2i = Vector2i(x,y) + DIRECTIONS[i]
        neighbour_masks[world.at(q.x,q.y)] |= 1 << i
    var is_capital := Vector2i(x,y) in world.capitals and world.is_walkable(x,y) and type!=world.ASH
    var water := chunk.layers[0]
    var ground := chunk.layers[1]
    var transitions := chunk.layers[2]
    var cliffs := chunk.layers[3]
    var decor := chunk.layers[4]
    var objects: PixelCommands = chunk.rows[y % CHUNK]
    var vegetation: PixelCommands = chunk.wind_rows[y % CHUNK]
    if type == world.OCEAN:
        water.add("water_%d" % v,Vector2(x*TILE,y*TILE))
        var shores: int = (~int(neighbour_masks[world.OCEAN])) & 15
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
    var variants: int = {"meadow":8,"forest":8,"sand":8,"rock":6,"ash":5,"earth":2}.get(family,4)
    var surface := variation(x,y,world.seed,variants)
    # Stable broad patches enrich colour without changing the material or sampling scale.
    var shade := 0.97 + variation(x/7,y/7,world.seed,7)*0.01 if type in [world.MEADOW,world.FOREST] else 1.0
    if type == world.ASH:
        var exposure := scorch_exposure(x, y)
        if exposure != 0:
            var substrate := scorch_underlay(x, y)
            var substrate_count: int = {"meadow":8,"forest":8,"sand":8,"rock":6,"earth":2}[substrate]
            var substrate_variant := variation(x,y,world.seed+41,substrate_count)
            ground.add("%s_%d" % [substrate,substrate_variant],p)
            # The second draw is alpha-masked ash; transparent holes reveal
            # nearby surviving terrain instead of a square black tile.
            ground.add(atlas.scorch_tile(exposure,surface),p)
        else:
            ground.add("%s_%d" % [family,surface],p)
    else:
        ground.add("%s_%d" % [family,surface],p,Vector2.ZERO,Color(shade,shade,shade))
    if type == world.MOUNTAIN and variation(x,y,world.seed+27,7)==0:
        ground.add("mountain_%d" % v,p)
    var ocean_mask: int = neighbour_masks[world.OCEAN]
    if ocean_mask:
        transitions.add("coast_cut_%d" % ocean_mask,p)
    # Beach-to-meadow edges spread vegetation into sand instead of a straight line.
    if type == world.BEACH:
        var grass_mask: int = neighbour_masks[world.MEADOW] | neighbour_masks[world.FOREST]
        if grass_mask: transitions.add("meadow_edge_%d" % grass_mask,p)
        if ocean_mask and detail==2 and v%2==0: decor.add("shore_scatter",p)
    # Ordinary biome-edge sprites must not paint rectangular overlays across
    # the newly clipped ash silhouette. Adjacent intact cells keep ash_edge.
    if type != world.ASH:
        for other in BIOMES:
            if other == type:
                continue
            var mask: int = neighbour_masks[other]
            if mask == 0:
                continue
            var edge_family: String = EDGE_FAMILY[other]
            if type != world.MOUNTAIN:
                transitions.add("%s_edge_%d" % [edge_family,mask],p)
    var height := world.height_at(x,y)
    var south_drop := height-world.height_at(x,y+1)
    var east_drop := height-world.height_at(x+1,y)
    if south_drop > 0:
        var face_height := south_drop*RISE+4
        cliffs.add("cliff_%d" % variation(x,y,world.seed,8),p+Vector2(0,TILE-4),Vector2(TILE,face_height))
        cliffs.add("contact_shadow",p+Vector2(0,TILE+face_height-5),Vector2(TILE,12))
        cliffs.add("cliff_strata",p+Vector2(0,TILE-4),Vector2(TILE,face_height))
        cliffs.add("cliff_rim",p+Vector2(0,TILE-6))
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
        decor.add("path_join_%d" % path,p)
    var salt := variation(x,y,world.seed+17,100)
    if type == world.TOWN or is_capital:
        if is_capital or building_cells.has(cell) or facility_cells.has(cell):
            var facility: String = str(facility_cells.get(cell, ""))
            var building: String = "workshop_a" if facility == "tool_area" else \
                ("town_hall_a" if variation(x,y,world.seed,2)==0 else "town_hall_b") if is_capital else \
                BUILDINGS[variation(x,y,world.seed,BUILDINGS.size())]
            if physical_buildings.has(cell):
                var actual: Dictionary = physical_buildings[cell]
                var definition: Dictionary = world.construction.catalogue.definition(str(actual.get("definition_id", "primitive_shelter")))
                building = str(definition.get("visual", {}).get("sprite", building)) if str(actual.get("type", "")) != "tool_area" else "workshop_a"
            var building_tint := Color.WHITE
            if physical_buildings.has(cell):
                var state: Dictionary = physical_buildings[cell]
                if bool(state.get("abandoned",false)): building_tint = Color(0.52,0.55,0.50,0.8)
                elif int(state.get("condition",100))<60: building_tint = Color(0.8,0.7,0.63)
            prop(objects,building,p+Vector2(16,27),1.0,building_tint)
            if detail > 0:
                prop(decor,"fence_gate" if v%2==0 else "stone_wall_h",p+Vector2(17,32),0.75)
                prop(decor,"garden" if v%2==0 else "crops",p+Vector2(7,31),0.58)
                if detail==2:prop(objects,["handcart","crates","hay","chopping_block"][v],p+Vector2(29,28),0.6)
        elif detail > 0:
            prop(decor,["garden","crops","well_open","well_roof"][v],p+Vector2(16,28),0.78)
        return
    if type == world.FOREST:
        if (detail > 0 or salt < 40) and not path_cells.has(cell):
            var tree: String = TREE_SPECIES[variation(x,y,world.seed,TREE_SPECIES.size())]
            var offset := Vector2(9+variation(x,y,world.seed+3,12),24+variation(x,y,world.seed+4,7))
            prop(vegetation,tree,p+offset,0.87+v*0.06,Color.WHITE,1.0)
        if detail == 2 and salt < 26:
            var plant: String = SMALL_PLANTS[variation(x,y,world.seed,SMALL_PLANTS.size())]
            if plant in ["fern_cluster","wildflowers","tall_grass"]:
                prop(vegetation,plant,p+Vector2(5,28),0.55,Color.WHITE,0.5)
            else:
                prop(decor,plant,p+Vector2(5,28),0.55)
    elif type == world.MEADOW:
        if salt < 7 and detail > 0 and not path_cells.has(cell):
            prop(vegetation,["oak","birch","beech","maple"][v],p+Vector2(17,28),0.78,Color.WHITE,0.95)
        elif salt < 20 and detail > 0:
            prop(vegetation,["berry_shrub","tall_grass","wildflowers","sapling_leaf"][v],p+Vector2(16,28),0.6,Color.WHITE,0.55)
        elif salt < 23 and detail == 2:
            prop(decor,["moss_log","fallen_tree","sapling_pine","dead_tree"][v],p+Vector2(18,26),0.6)
    elif type == world.MOUNTAIN:
        if salt<42:
            prop(objects,["mountain_spire","granite_boulder","sandstone_boulder","moss_boulder"][v],p+Vector2(11+salt%12,26+salt%5),0.85+v*0.1)
    elif type == world.ASH and salt < 15 and detail > 0:
        prop(objects,"dead_tree",p+Vector2(17,29),0.72,Color(0.66,0.61,0.58))
    if type == world.BEACH and detail > 0 and salt < 27:
        prop(decor,["driftwood","coastal_stones","pebbles","shells"][v],p+Vector2(16,28),0.62)
        if salt < 9 and ocean_mask:prop(vegetation,"wet_reeds" if v%2==0 else "cattails",p+Vector2(26,29),0.65,Color.WHITE,0.65)
    if south_drop>0 and detail==2 and salt<25:
        prop(objects,"cliff_debris",p+Vector2(18,TILE+south_drop*RISE),0.55)
    if salt >= 93 and type != world.ASH and detail > 0:
        prop(decor,"rock_small" if v%2==0 else "rock_medium",p+Vector2(17,25),0.6)

func rebuild_paths() -> void:
    path_cells.clear()
    path_barriers.clear()
    town_cells.clear()
    building_cells.clear()
    facility_cells.clear()
    physical_buildings.clear()
    physical_footprints.clear()
    for house in world.construction.houses:
        var anchor := Vector2i(int(house["x"]), int(house["y"]))
        physical_buildings[anchor] = house
        var definition: Dictionary = world.construction.catalogue.definition(str(house.get("definition_id", "primitive_shelter")))
        for footprint_cell in world.construction.placement.footprint(definition,anchor,int(house.get("orientation",0))):
            physical_footprints[footprint_cell] = true
        building_cells[anchor] = true
        if str(house.get("type", "")) == "tool_area":
            facility_cells[Vector2i(int(house["x"]), int(house["y"]))] = "tool_area"
    rendered_building_count = world.construction.houses.size()
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
                if not world.is_walkable(point.x,point.y):
                    path_barriers[point]=true
                    break
                if point.x!=previous.x and point.y!=previous.y:
                    var elbow := Vector2i(point.x,previous.y)
                    if not world.is_walkable(elbow.x,elbow.y):
                        path_barriers[elbow]=true
                        break
                    path_cells[elbow]=3
                    path_cells[previous]=int(path_cells.get(previous,0))|1
                    path_cells[point]=int(path_cells.get(point,0))|2
                var direction := 1 if point.x!=previous.x else 2
                path_cells[point]=int(path_cells.get(point,0))|direction
                path_cells[previous]=int(path_cells.get(previous,0))|direction
                previous=point
    # Authoritative roads coexist with older decorative settlement path hints.
    for key in world.regional_economy.roads:
        var index := int(key)
        if index >= 0 and index < world.WIDTH * world.HEIGHT:
            path_cells[Vector2i(index % world.WIDTH, index / world.WIDTH)] = 15
    # Local deterministic minima reserve a one-cell gap between large building footprints.
    for cell in town_cells:
        if physical_footprints.has(cell):
            continue
        var priority := variation(cell.x,cell.y,world.seed+71,100000)
        var anchor := true
        for dy in range(-1,2):
            for dx in range(-1,2):
                var other: Vector2i = cell+Vector2i(dx,dy)
                if other==cell:continue
                if other in world.capitals:
                    anchor=false
                elif town_cells.has(other):
                    var rank := variation(other.x,other.y,world.seed+71,100000)
                    if rank<priority or (rank==priority and (other.y<cell.y or (other.y==cell.y and other.x<cell.x))):anchor=false
        if anchor:building_cells[cell]=true
    var connected := {}
    for cell in path_cells:
        var mask := 0
        for i in range(4):
            if path_cells.has(cell+DIRECTIONS[i]):mask |= 1<<i
        connected[cell]=mask if mask>0 else 15
    path_cells=connected
    for chunk in chunks.values(): chunk.dirty=true
    rendered_roads_revision = world.regional_economy.revision
    paths_dirty=false

func prop(layer: PixelCommands, key: String, foot: Vector2, factor: float = 1.0, tint: Color = Color.WHITE, sway: float = 0.0) -> void:
    var sz := atlas.size_of(key)*factor
    if key in TREE_SPECIES or key in BUILDINGS or key.begins_with("town_hall"):
        layer.add("ground_shadow",(foot-Vector2(sz.x*0.43,9)).round(),Vector2(sz.x,14).round())
    layer.add(key,(foot-Vector2(sz.x*0.5,sz.y)).round(),sz.round(),tint,-1.0,sway)

func refresh_units() -> void:
    # Refresh only when the authoritative simulation changes. Between ticks,
    # presentation positions advance independently without changing AI state.
    walks.synchronize(world.citizens)
    render_units()

func render_units() -> void:
    for row in unit_rows:
        row.clear_commands()
    for citizen in world.citizens:
        if int(citizen["hp"]) <= 0:
            continue
        var id: int = int(citizen["id"])
        if not walks.tracks.has(id):
            continue
        var track: Dictionary = walks.tracks[id]
        var start: Vector2 = track["from"]
        var goal: Vector2 = track["to"]
        var fraction: float = walks.alpha(id)
        var start_height := world.height_at(roundi(start.x), roundi(start.y))
        var end_height := world.height_at(int(citizen["x"]), int(citizen["y"]))
        var p := start.lerp(goal, fraction) * TILE + Vector2(
            12 + posmod(id, 9), 25 - lerpf(float(start_height), float(end_height), fraction) * RISE)
        var phase: float = walks.walk_phase(id)
        if phase >= 0.0:
            p.y -= absf(sin(phase * TAU * 2.0)) * 0.65
        # Skip invisible sprites, not simulated citizens. No one-sprite nodes.
        if visible_rect.size != Vector2.ZERO and not visible_rect.grow(72.0).has_point(p):
            continue
        var row_index := clampi(roundi(lerpf(start.y, goal.y, fraction)), 0, world.HEIGHT - 1)
        var key := "citizen_gold" if int(citizen["nation"]) == 0 else "citizen_rose"
        var sprite_size := (atlas.size_of(key) * 0.9).round()
        unit_rows[row_index].add(key,
            (p - Vector2(sprite_size.x * 0.5, sprite_size.y)).round(),
            sprite_size, Color.WHITE, phase)
    for row in unit_rows:
        if row.visible:
            row.queue_redraw()

func animate(delta: float, simulated_delta: float = -1.0) -> void:
    var motion_delta: float = delta if simulated_delta < 0.0 else simulated_delta
    if walks.advance(motion_delta):
        walk_draw_accum += delta
        if walk_draw_accum >= 1.0 / 30.0 or not walks.has_active_motion():
            render_units()
            walk_draw_accum = 0.0
    # Animate the small visible vegetation pass at 15 Hz, never the static
    # chunks. Phase transitions follow saved simulation ticks.
    weather.set_time(float(world.tick) * 0.1)
    sway_clock += maxf(0.0, delta)
    sway_accum += maxf(0.0, delta)
    if sway_accum >= SWAY_INTERVAL:
        sway_accum = fmod(sway_accum, SWAY_INTERVAL)
        for chunk in chunks.values():
            if not chunk.visible or detail == 0:
                continue
            for row in chunk.wind_rows:
                row.set_wind(sway_clock, weather.wind_strength, weather.wind_direction.x)
        weather_overlay.update_weather(visible_rect, sway_clock, weather.rain_strength, weather.wind_direction, world.seed)
    effect_clock += motion_delta
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
                effects.add("ripple",p,Vector2(14,5),Color(0.65,0.91,0.94,0.22+effect_phase*0.06 + weather.wind_strength*0.12))
                count+=1
    effects.queue_redraw()

func add_power_effect(power: int, cell: Vector2i) -> void:
    # Short, bounded effects; permanent ash remains part of terrain state.
    if power == 1 or power == 3:
        prop(effects,"fire" if power==1 else "blessing",tile_center(cell)+Vector2(0,8),1.3)
        effects.queue_redraw()
