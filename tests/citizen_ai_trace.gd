extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
const AI = preload("res://scripts/ai/citizen_ai.gd")
const Brush = preload("res://scripts/terrain_brush.gd")
var trace_population := 160
var trace_ticks := 360
var trace_stride := 24
var trace_path := "res://tests/fixtures/phase2-behaviour-trace.json"

func _initialize() -> void:
    var path := trace_path
    var record := false
    for arg in OS.get_cmdline_user_args():
        if arg == "--record":
            record = true
        if arg.begins_with("--trace="):
            path = arg.get_slice("=", 1)
    var reference: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
    if reference == null and not record:
        push_error("Missing Phase 2 reference fixture")
        quit(1)
        return
    var world = Simulation.new(20261120)
    if trace_population != 160:
        var cells: Array[Vector2i] = []
        for y in range(world.HEIGHT):
            for x in range(world.WIDTH):
                if world.is_walkable(x, y):
                    cells.append(Vector2i(x,y))
        world.citizens.clear()
        world.citizen_ai_by_id.clear()
        world.next_id = 1
        world.capitals = [Vector2i(-1,-1),Vector2i(-1,-1)]
        for i in range(trace_population):
            var cell: Vector2i = cells[(i * 73) % cells.size()]
            world.add_citizen(cell.x,cell.y,i%2)
        if world.has_method("prepare_save_bytes"):
            world.ai_context.set("routine_budget", 1500)
    var results: Array = []
    for i in range(1, trace_ticks + 1):
        if trace_population == 160 and i % 36 == 0 and i <= 216:
            var powers := [0, 2, 4, 1, 3, 5]
            world.apply_power(powers[i / 36 - 1], 40, 60)
        if trace_population == 160 and i == 240:
            Brush.paint_segment(world, 0, Vector2i(35, 63), Vector2i(44, 63), 1)
        world.step()
        if i % trace_stride != 0:
            continue
        var data: Dictionary = world.snapshot()
        if data["version"] == 4:
            data = world.call("snapshot", true)
        data.erase("routine_budget")
        for id in data["citizen_ai_by_id"]:
            var state: Dictionary = data["citizen_ai_by_id"][id]
            state.erase("risk_revision")
            state.erase("utility_rows")
            state["utilities"] = AI.inspect(world.citizen_ai_by_id[id])["utilities"]
        results.append(JSON.stringify(data).sha256_text())
    if reference != null:
        if results != reference:
            push_error("Phase 2 behavioural reference diverged")
            for i in range(results.size()):
                if results[i] != reference[i]:
                    print("FIRST_DIVERGENCE_TICK ", (i + 1) * trace_stride)
                    break
            quit(1)
            return
    else:
        var file := FileAccess.open(path, FileAccess.WRITE)
        file.store_string(JSON.stringify(results))
        file.close()
    print("AI_BEHAVIOURAL_TRACE_PASSED checkpoints=", results.size())
    quit(0)
