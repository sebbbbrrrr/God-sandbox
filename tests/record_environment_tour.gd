extends SceneTree

class Tour extends "res://scripts/game.gd":
    func load_world() -> SandboxSimulation:
        var sim := SandboxSimulation.new(424242)
        preload("res://tests/environment_fixture.gd").populate(sim)
        return sim
    func save_world() -> void:
        pass

func _initialize() -> void:
    call_deferred("record")

func record() -> void:
    root.size=Vector2i(480,850)
    root.content_scale_size=root.size
    var game := Tour.new()
    root.add_child(game)
    game.paused=true
    game.selected_power=-1
    var views := [Vector2(35,39),Vector2(20,62),Vector2(70,39),Vector2(45,81)]
    # Deterministic 12-second in-engine tour, recorded with Godot's movie writer.
    # Simulation advances at ten fixed steps per second independently of encoding.
    for frame in range(360):
        var section := mini(3,frame/90)
        var progress := float(frame%90)/89.0
        game.camera_center=views[section]+Vector2(progress*2.0-1.0,progress)
        game.zoom=2.4-progress*0.2
        if frame%3==0:
            game.world.step()
            game.world_renderer.refresh_units()
        if frame==290:
            game.world.apply_power(3,45,81)
            game.world_renderer.add_power_effect(3,Vector2i(45,81))
        await process_frame
    game.free()
    print("ENVIRONMENT_TOUR_COMPLETE: 360 frames / 30 fps")
    quit()
