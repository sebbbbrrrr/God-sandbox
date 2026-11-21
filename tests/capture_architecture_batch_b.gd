extends SceneTree
const F = preload("res://tests/architecture_fixture.gd")
class CaptureGame extends "res://scripts/unified_game.gd":
    func load_world() -> SandboxSimulation:
        var w = F.batch_b_world()
        for technology in ["irrigation","caravan_trade"]: w.occupations.grant_capability(w,0,technology,"teaching")
        var order := {"charcoal_clamp":[30,10],"pottery_kiln":[35,10],"weaving_house":[40,10],"cordage_canopy":[30,16],"timber_workyard":[35,16],"grain_grinding_shelter":[40,16],"fenced_farmstead":[45,16],"water_lift":[24,29],"masonry_workyard":[30,22],"ore_mine":[18,26],"bronze_smelter":[35,22]}
        for id in order:
            var p: Array = order[id]
            if F.build(w,str(id),Vector2i(p[0],p[1])).is_empty(): push_error("Batch B showcase failed: "+str(id))
        if not F.stock(w,{"brick_wall_block":1,"bronze_ingot":3}): push_error("Showcase metallurgy did not consume real inputs")
        var later := {"bronze_forge":[40,22],"bronze_courtyard":[30,28],"bronze_granary":[35,28],"bronze_market":[40,28],"bronze_meeting_hall":[45,28]}
        for id in later:
            var p: Array = later[id]
            if F.build(w,str(id),Vector2i(p[0],p[1])).is_empty(): push_error("Batch B showcase failed: "+str(id))
        if not w.inventory.ledger_ok(): push_error("Showcase has nonconserved material")
        return w
    func save_world() -> void: pass
var game: Node2D
func _initialize() -> void: call_deferred("capture")
func save(name: String) -> void:
    for i in range(10): await process_frame
    await RenderingServer.frame_post_draw
    if root.get_texture().get_image().save_png("res://docs/architecture/"+name+".png")!=OK: push_error("Capture save failed")
    print("ARCHITECTURE_GL_CAPTURE=",name)
func capture() -> void:
    root.size = Vector2i(1000,900)
    root.content_scale_size = root.size
    game = CaptureGame.new()
    root.add_child(game)
    game.paused = true
    game.selected_power = -1
    game.zoom = 1.3
    game.camera_center = Vector2(34,22)
    await save("batch-b-world")
    game.zoom = 2.9
    game.camera_center = Vector2(37.5,26)
    await save("batch-b-bronze-detail")
    var courtyard: Dictionary = {}
    for house in game.world.construction.houses:
        if str(house["definition_id"])=="bronze_courtyard": courtyard = house
    game.world.construction.lifecycle.damage(game.world.construction,game.world,int(courtyard["id"]),50,"showcase")
    await save("batch-b-damage")
    game.world.construction.lifecycle.abandon(game.world.construction,game.world,int(courtyard["id"]),true)
    await save("batch-b-abandoned")
    game.zoom = 2.0
    game.camera_center = Vector2(31,23)
    game.civilisation_ui.open_for(0)
    game.civilisation_ui._switch_tab(1)
    await save("batch-b-inspector")
    root.remove_child(game)
    game.free()
    print("ARCHITECTURE_BATCH_B_CAPTURES_PASSED")
    quit()
