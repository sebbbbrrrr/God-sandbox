extends SceneTree

class BenchGame extends "res://scripts/game.gd":
    func load_world() -> SandboxSimulation:
        return SandboxSimulation.new(424242)
    func save_world() -> void:
        pass

func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    DirAccess.make_dir_recursive_absolute("res://tests/captures")
    root.size=Vector2i(480,850)
    root.content_scale_size=Vector2i(480,850)
    var game := BenchGame.new()
    root.add_child(game)
    game.selected_power=-1
    var report: Dictionary={"engine":Engine.get_version_info()["string"],"platform":"Linux Xvfb / Mesa llvmpipe software GL; NOT an Android device","cases":[]}
    for setting in [[0.5,160],[1.0,160],[2.0,160],[1.0,1500]]:
        game.zoom=float(setting[0])
        if int(setting[1])>game.world.citizens.size():
            var point: Vector2i=game.world.capitals[0]
            while game.world.citizens.size()<int(setting[1]):game.world.add_citizen(point.x,point.y,game.world.citizens.size()%2)
        for i in range(40): await process_frame
        var samples: Array[float]=[]
        var start:=Time.get_ticks_usec()
        var last:=start
        var mem_start:=OS.get_static_memory_usage()
        var builds_before:=game.world_renderer.rebuilds
        for i in range(180):
            await RenderingServer.frame_post_draw
            var now:=Time.get_ticks_usec()
            samples.append(float(now-last)/1000.0)
            last=now
        samples.sort()
        var elapsed:=float(Time.get_ticks_usec()-start)/1000000.0
        report["cases"].append({"zoom":game.zoom,"citizens":game.world.citizens.size(),"visible_chunks":game.world_renderer.visible_chunks,"mean_fps":180.0/elapsed,"frame_p50_ms":samples[90],"frame_p95_ms":samples[171],"static_memory_start_bytes":mem_start,"static_memory_end_bytes":OS.get_static_memory_usage(),"cached_terrain_rebuilds":game.world_renderer.rebuilds-builds_before,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
    var renderer: PixelWorldRenderer=game.world_renderer
    var point:=game.screen_to_tile(Vector2(240,330))
    var t:=Time.get_ticks_usec()
    game.world.apply_power(0,point.x,point.y)
    renderer.invalidate_cell(point)
    renderer.update_view(game.world_origin(),game.tile_size(),Rect2(0,50,480,612))
    report["single_edit_rebuild_ms"]=float(Time.get_ticks_usec()-t)/1000.0
    var file:=FileAccess.open("res://tests/captures/benchmark.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(report,"  "));file.close()
    print("BENCHMARK: "+JSON.stringify(report))
    game.free()
    quit()
