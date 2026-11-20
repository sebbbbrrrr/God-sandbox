extends SceneTree

class TestGame extends "res://scripts/game.gd":
    func load_world() -> SandboxSimulation:
        return SandboxSimulation.new(424242)
    func save_world() -> void:
        pass

var success := true
var assertions := 0
func _initialize() -> void:
    call_deferred("run")
func check(ok: bool, message: String) -> void:
    assertions+=1
    if not ok:
        success=false
        push_error("FAILED: "+message)
func touch(game: Node2D, id: int, point: Vector2, pressed: bool) -> void:
    var event := InputEventScreenTouch.new()
    event.index=id;event.position=point;event.pressed=pressed
    game._input(event)
func drag(game: Node2D, id: int, point: Vector2) -> void:
    var event := InputEventScreenDrag.new()
    event.index=id;event.position=point
    game._input(event)
func run() -> void:
    root.size=Vector2i(480,850)
    root.content_scale_size=Vector2i(480,850)
    var game := TestGame.new()
    root.add_child(game)
    game.paused=true
    game.brush_index=0
    game.selected_power=0
    for y in range(55,65):
        for x in range(40,56):game.world.set_terrain(x,y,game.world.OCEAN)
    var a: Vector2=game.world_origin()+game.world_renderer.tile_center(Vector2i(41,60))*game.tile_size()/32.0
    var b: Vector2=game.world_origin()+game.world_renderer.tile_center(Vector2i(53,60))*game.tile_size()/32.0
    touch(game,0,a,true);drag(game,0,b);touch(game,0,b,false)
    for x in range(41,54):check(game.world.at(x,60)==game.world.MEADOW,"continuous fast drag tile %d"%x)
    game.selected_power=2
    touch(game,0,a,true);touch(game,1,b,true)
    var before:=game.world.terrain.duplicate()
    var center: Vector2=game.camera_center
    var old_zoom: float=game.zoom
    drag(game,1,b+Vector2(30,25))
    check(game.camera_center!=center and game.zoom!=old_zoom,"two-finger pan and pinch")
    check(game.world.terrain==before,"two-finger gesture never paints")
    touch(game,1,b+Vector2(30,25),false);drag(game,0,a+Vector2(40,0))
    check(game.world.terrain==before,"lifting one finger never resumes paint")
    touch(game,0,a+Vector2(40,0),false)
    check(game.touches.is_empty() and not game.multi_touch,"gesture resets after release")
    game.selected_power=-1
    center=game.camera_center
    touch(game,0,Vector2(100,200),true);drag(game,0,Vector2(140,220));touch(game,0,Vector2(140,220),false)
    check(game.camera_center!=center,"hand mode single-finger pan")
    game.selected_power=1
    center=game.camera_center
    touch(game,0,Vector2(120,200),true);drag(game,0,Vector2(155,225));touch(game,0,Vector2(155,225),false)
    check(game.camera_center!=center,"non-brush power single-finger navigation")
    before=game.world.terrain.duplicate()
    touch(game,0,Vector2(20,820),true);drag(game,0,Vector2(50,200));touch(game,0,Vector2(50,200),false)
    check(game.world.terrain==before,"toolbar-origin touch cannot paint world")
    var paused_before: bool=game.paused
    game.tapped(Vector2(390,20));check(game.paused!=paused_before,"pause control")
    game.tapped(Vector2(450,20));check(game.simulation_speed==2,"speed control")
    game.tapped(Vector2(330,20));check(game.selected_power==-1,"hand selection")
    game.tapped(Vector2(70,710));check(game.selected_power==0,"category returns to editing")
    game.paused=true
    var point:=Vector2(240,300)
    var cell: Vector2i=game.screen_to_tile(point)
    game.world.set_terrain(cell.x,cell.y,game.world.MEADOW)
    point=game.world_origin()+game.world_renderer.tile_center(cell)*game.tile_size()/32.0
    game.world_renderer.refresh_units()
    var units_before:=0
    for row in game.world_renderer.unit_rows: units_before+=row.keys.size()
    game.selected_power=4
    game.tapped(point)
    var units_after:=0
    for row in game.world_renderer.unit_rows: units_after+=row.keys.size()
    check(units_after==units_before+1,"spawn sprite updates immediately while paused")
    game.world.citizens.back()["hp"]=20
    game.selected_power=1
    game.tapped(point)
    var survivors:=0
    for citizen in game.world.citizens:
        if citizen["hp"]>0: survivors+=1
    units_after=0
    for row in game.world_renderer.unit_rows: units_after+=row.keys.size()
    check(units_after==survivors and units_after<units_before+1,"fire removes dead sprites immediately while paused")
    print("INPUT_TESTS_%s (%d assertions)"%["PASSED" if success else "FAILED",assertions])
    game.free()
    quit(0 if success else 1)
