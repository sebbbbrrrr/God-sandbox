extends SceneTree
const Fixture = preload("res://tests/architecture_fixture.gd")
class CaptureGame extends "res://scripts/unified_game.gd":
    func load_world() -> SandboxSimulation:
        var w = Fixture.world()
        var ids: Array = []
        for row in w.construction.catalogue.definitions.values():
            if not bool(row.get("legacy",true)): ids.append(str(row["id"]))
        for i in range(ids.size()):
            if Fixture.build(w,str(ids[i]),Vector2i(28+i%4*5,12+i/4*6)).is_empty(): push_error("Showcase construction failed: "+str(ids[i]))
        return w
    func save_world() -> void: pass
var game: Node2D

func _initialize() -> void:
    call_deferred("capture")

func save(name: String) -> void:
    for i in range(10): await process_frame
    await RenderingServer.frame_post_draw
    var err := root.get_texture().get_image().save_png("res://docs/architecture/"+name+".png")
    if err!=OK: push_error("Screenshot save failed")
    print("ARCHITECTURE_GL_CAPTURE=",name)

func capture() -> void:
    root.size = Vector2i(1000,900)
    root.content_scale_size = root.size
    game = CaptureGame.new()
    root.add_child(game)
    game.paused = true
    game.selected_power = -1
    game.zoom = 2.0
    game.camera_center = Vector2(36.5,21.5)
    await save("world-showcase")
    game.zoom = 3.3
    game.camera_center = Vector2(35,18)
    await save("world-detail")
    var house: Dictionary = game.world.construction.houses[0]
    game.world.construction.lifecycle.damage(game.world.construction,game.world,int(house["id"]),55,"showcase")
    var abandoned: Dictionary = game.world.construction.houses[1]
    game.world.construction.lifecycle.abandon(game.world.construction,game.world,int(abandoned["id"]),true)
    game.zoom = 3.0
    game.camera_center = Vector2(32,14)
    await save("damaged-abandoned")
    game.world.construction.lifecycle.damage(game.world.construction,game.world,int(house["id"]),100,"showcase")
    await save("collapsed-ruin")
    # A genuine newly planned site beside completed architecture, not fake art.
    Fixture.stock(game.world,{"wood":4,"stone":1,"plant_fibre":2})
    var request: Dictionary = game.world.construction.request_construction(game.world,{"settlement_id":0,"definition_id":"branch_shelter","function":"shelter","location":[28,8]})
    game.camera_center = Vector2(32,12)
    await save("construction-survey")
    for i in range(250):
        Fixture.work(game.world,1)
        var site: Dictionary = game.world.construction.site_by_id(int(request.get("site_id",0)))
        if int(site.get("stage",0))>=3: break
    await save("construction-work")
    if not bool(request.get("ok",false)): push_error("Survey fixture failed")
    if not game.world.inventory.ledger_ok(): push_error("Showcase material conservation failed")
    root.remove_child(game)
    game.free()
    print("ARCHITECTURE_GL_CAPTURES_PASSED")
    quit()
