extends SceneTree

const Sim = preload("res://scripts/simulation.gd")
const Renderer = preload("res://scripts/pixel_world_renderer.gd")
const Brush = preload("res://scripts/terrain_brush.gd")
var success := true
var assertions := 0

func _initialize() -> void:
    call_deferred("run")

func check(condition: bool, message: String) -> void:
    assertions += 1
    if not condition:
        success = false
        push_error("FAILED: "+message)

func run() -> void:
    var world := Sim.new(20261119)
    var renderer := Renderer.new()
    renderer.setup(world)
    root.add_child(renderer)
    check(renderer.atlas.entries.size()==358,"all original and new atlas entries")
    for key in renderer.atlas.entries:
        var tex := renderer.atlas.texture(key)
        check(tex != null and Rect2(Vector2.ZERO,tex.get_size()).encloses(renderer.atlas.region(key)),"atlas bounds: "+key)
    check(ResourceLoader.exists(ProjectSettings.get_setting("application/config/icon","")),"Android export icon exists")
    check(renderer.atlas.pages.size()==2,"original and architecture pages load")
    for key in Renderer.TREE_SPECIES+Renderer.SMALL_PLANTS+Renderer.BUILDINGS:
        check(renderer.atlas.entries.has(key),"integrated art exists: "+key)
    # A blocked footpath must disappear and return when the player restores land.
    world.capitals=[Vector2i(40,40),Vector2i(80,80)]
    for x in range(40,47):world.set_terrain(x,40,Sim.MEADOW)
    world.set_terrain(46,40,Sim.TOWN)
    renderer.rebuild_paths()
    check(renderer.path_cells.has(Vector2i(43,40)),"settlement footpath connects to capital")
    world.set_terrain(43,40,Sim.OCEAN)
    check(renderer.paths_dirty,"flooding a footpath invalidates connectivity")
    renderer.rebuild_paths()
    check(not renderer.path_cells.has(Vector2i(43,40)),"footpath never crosses water")
    world.set_terrain(43,40,Sim.MEADOW)
    check(renderer.paths_dirty,"restored terrain reconnects blocked footpath")
    renderer.rebuild_paths()
    check(renderer.path_cells.has(Vector2i(43,40)),"restored footpath reappears")
    world.set_terrain(43,40,Sim.FOREST)
    check(not renderer.paths_dirty,"walkable material change keeps cached path network")
    for y in range(42,49):
        for x in range(42,49):world.set_terrain(x,y,Sim.TOWN)
    renderer.rebuild_paths()
    var anchors:=0
    for cell in renderer.building_cells:
        if cell.x<42 or cell.x>48 or cell.y<42 or cell.y>48:continue
        anchors+=1
        for other in renderer.building_cells:
            check(cell==other or maxi(absi(cell.x-other.x),absi(cell.y-other.y))>1,"large buildings reserve separation")
    check(anchors==0,"terrain paint cannot invent unbuilt functional architecture")
    var hall_chunk: PixelChunk=renderer.chunks[Vector2i(40/16,40/16)]
    renderer.build_chunk(hall_chunk)
    var intact_hall:=false
    for row in hall_chunk.rows:
        for key in row.keys:
            if key=="arch_meeting_canopy":intact_hall=true
    check(intact_hall,"capital renders age-appropriate communal depot artwork")
    var capital: Vector2i=world.capitals[0]
    world.apply_power(1,capital.x,capital.y)
    var capital_chunk: PixelChunk=renderer.chunks[Vector2i(capital.x/16,capital.y/16)]
    renderer.build_chunk(capital_chunk)
    var hall_present:=false
    for row in capital_chunk.rows:
        for key in row.keys:
            if key=="arch_meeting_canopy": hall_present=true
    check(not hall_present,"burned capital loses intact town hall")
    # Exhaustive cardinal transition lookup including diagonal/chunk-border cases.
    var center := Vector2i(15,15)
    world.set_terrain(15,15,Sim.OCEAN)
    for mask in range(16):
        for i in range(4):
            var q: Vector2i = center+Renderer.DIRECTIONS[i]
            world.set_terrain(q.x,q.y,Sim.MEADOW if mask&(1<<i) else Sim.OCEAN)
        check(renderer.land_mask(15,15)==mask,"shoreline mask %d"%mask)
        check(renderer.mask_for(15,15,Sim.MEADOW)==mask,"biome mask %d"%mask)
    renderer.update_view(Vector2.ZERO,32,Rect2(0,0,480,600))
    check(renderer.visible_chunks>0 and renderer.visible_chunks<renderer.chunks.size(),"visible chunk culling")
    var builds := renderer.rebuilds
    renderer.update_view(Vector2.ZERO,32,Rect2(0,0,480,600))
    check(renderer.rebuilds==builds,"static view never regenerates terrain")
    for chunk in renderer.chunks.values(): chunk.dirty=false
    world.set_terrain(15,15,Sim.MEADOW)
    var dirty := 0
    for chunk in renderer.chunks.values():
        if chunk.dirty: dirty+=1
    check(dirty==4,"edit at chunk corner invalidates all four chunks")
    renderer.update_view(Vector2.ZERO,32,Rect2(0,0,480,600))
    check(not renderer.chunks[Vector2i(0,0)].dirty,"edited chunk rebuilt")
    renderer.update_view(Vector2.ZERO,8,Rect2(0,0,480,600))
    check(renderer.detail==0,"distant LOD")
    renderer.update_view(Vector2.ZERO,20,Rect2(0,0,480,600))
    check(renderer.detail==1,"medium LOD")
    renderer.update_view(Vector2.ZERO,48,Rect2(0,0,480,600))
    check(renderer.detail==2,"close LOD")
    # Every elevation and fractional screen scale maps a surface center correctly.
    world.set_terrain(20,20,Sim.MEADOW)
    world.set_terrain(20,21,Sim.MEADOW)
    for height in range(4):
        world.visual_elevation[world.index_of(20,20)]=height
        world.visual_elevation[world.index_of(20,21)]=height
        for ts in [8.0,16.0,23.7,32.0,64.0]:
            var origin := Vector2(-137,63)
            var point: Vector2 = origin+renderer.tile_center(Vector2i(20,20))*ts/32.0
            check(renderer.tile_at((point-origin)*32.0/ts)==Vector2i(20,20),"raised tile picking %d %f"%[height,ts])
    # JSON round-trip, real disk save, legacy payload, malformed elevation fallback.
    var snapshot := world.snapshot()
    var path := "user://render-test-save.json"
    var file := FileAccess.open(path,FileAccess.WRITE)
    file.store_string(JSON.stringify(snapshot));file.close()
    var restored := Sim.from_snapshot(JSON.parse_string(FileAccess.get_file_as_string(path)))
    check(restored != null and restored.terrain==world.terrain and restored.visual_elevation==world.visual_elevation,"disk save/load terrain and elevation")
    check(restored.rng.state==world.rng.state,"JSON preserves full 64-bit RNG state")
    for i in range(200): world.step();restored.step()
    check(restored.citizens==world.citizens and restored.terrain==world.terrain,"restored deterministic continuation")
    snapshot.erase("visual_elevation")
    check(Sim.from_snapshot(snapshot)!=null,"legacy version 1 save loads")
    snapshot["visual_elevation"]="aA=="
    check(Sim.from_snapshot(snapshot).visual_elevation.size()==Sim.WIDTH*Sim.HEIGHT,"malformed elevation safe fallback")
    DirAccess.remove_absolute(path)
    var rng_before := world.rng.state
    var citizens_before := world.citizens.duplicate(true)
    renderer.update_view(Vector2(-400,-800),32,Rect2(0,0,480,600))
    renderer.animate(1.0)
    check(renderer.effects.keys.size()<=96,"bounded water animation")
    check(world.rng.state==rng_before and world.citizens==citizens_before,"renderer never changes simulation")
    check(Renderer.variation(13,12,4,5)==Renderer.variation(13,12,4,5),"seeded sprite placement")
    check(world.apply_power(0,20,20) and world.apply_power(2,20,20),"raise and forest")
    check(world.apply_power(4,20,20),"spawn")
    check(world.apply_power(1,20,20) and world.citizens.back()["hp"]==70,"fire effect")
    check(world.apply_power(3,20,20) and world.citizens.back()["hp"]==100,"bless effect")
    check(world.apply_power(5,20,20) and world.height_at(20,20)==0,"ocean clears elevation")
    print("RENDERING_TESTS_%s (%d assertions)"%["PASSED" if success else "FAILED",assertions])
    renderer.free()
    quit(0 if success else 1)
