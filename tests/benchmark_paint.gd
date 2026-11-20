extends SceneTree

const Sim = preload("res://scripts/simulation.gd")
const Renderer = preload("res://scripts/pixel_world_renderer.gd")
const Brush = preload("res://scripts/terrain_brush.gd")

func _initialize() -> void:
    call_deferred("run")

func run() -> void:
    var world := Sim.new(424242)
    var renderer := Renderer.new()
    renderer.setup(world)
    root.add_child(renderer)
    var report := {"seed":424242,"samples_per_case":24,"warmup_strokes":4,"cases":[]}
    # CPU brush+rebuild time only. Fixed viewport, unchanged town count and no
    # simulation steps. Alternate real terrain changes; never time a no-op edit.
    for screen_tile in [8.0,24.0,48.0]:
        var origin: Vector2 = Vector2(240,330)-renderer.tile_center(Vector2i(48,64))*screen_tile/32.0
        renderer.update_view(origin,screen_tile,Rect2(0,50,480,612))
        var samples: Array[float] = []
        for i in range(28):
            var start := Time.get_ticks_usec()
            Brush.paint_segment(world,0 if i%2==0 else 5,Vector2i(44,62),Vector2i(52,66),2)
            renderer.update_view(origin,screen_tile,Rect2(0,50,480,612))
            if i>=4:samples.append(float(Time.get_ticks_usec()-start)/1000.0)
        samples.sort()
        var total := 0.0
        for sample in samples:total+=sample
        report["cases"].append({"screen_tile":screen_tile,"mean_ms":total/samples.size(),"p95_ms":samples[22],"worst_ms":samples[-1]})
    DirAccess.make_dir_recursive_absolute("res://tests/captures")
    var file := FileAccess.open("res://tests/captures/paint-benchmark.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(report,"  "));file.close()
    print("PAINT_BENCHMARK: ",JSON.stringify(report))
    renderer.free()
    quit()
