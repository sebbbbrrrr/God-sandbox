extends SceneTree

const Simulation = preload("res://scripts/simulation.gd")
const AI = preload("res://scripts/ai/citizen_ai.gd")

func _initialize() -> void:
    var population := 160
    var ticks := 600
    var dense := false
    var routine_budget := 96
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--population="):
            population = clampi(int(arg.get_slice("=", 1)), 1, 1500)
        elif arg.begins_with("--ticks="):
            ticks = maxi(60, int(arg.get_slice("=", 1)))
        elif arg.begins_with("--routine-budget="):
            routine_budget = clampi(int(arg.get_slice("=", 1)), 1, 1500)
        elif arg == "--dense":
            dense = true
    var before_memory: int = OS.get_static_memory_usage()
    var world = Simulation.new(20261120)
    world.ai_context.routine_budget = routine_budget
    var cells: Array[Vector2i] = []
    for y in range(world.HEIGHT):
        for x in range(world.WIDTH):
            if world.is_walkable(x, y):
                cells.append(Vector2i(x, y))
    world.citizens.clear()
    world.citizen_ai_by_id.clear()
    world.next_id = 1
    world.capitals = [Vector2i(-1, -1), Vector2i(-1, -1)]
    for i in range(population):
        var cell: Vector2i = cells[0 if dense else (i * 73) % cells.size()]
        world.add_citizen(cell.x, cell.y, i % 2)
    var warmup_deferred := 0
    for i in range(120):
        world.step()
        warmup_deferred += int(world.ai_context.metrics.get("deferred_decisions", 0))
    var times: Array[int] = []
    var path_nodes := 0
    var decisions := 0
    var interactions := 0
    var max_nodes := 0
    var max_requests := 0
    var max_candidates := 0
    var memory_samples: Array = []
    var max_routine := 0
    var deferred := 0
    var early_total := 0
    var late_total := 0
    var valid := true
    for i in range(ticks):
        var start := Time.get_ticks_usec()
        world.step()
        times.append(Time.get_ticks_usec() - start)
        if i < ticks / 3:
            early_total += times[-1]
        if i >= ticks - ticks / 3:
            late_total += times[-1]
        if i % 150 == 149:
            memory_samples.append({"tick":world.tick, "bytes":OS.get_static_memory_usage() - before_memory})
        var stats: Dictionary = world.ai_context.metrics
        max_routine = maxi(max_routine, int(stats.get("routine_decisions", 0)))
        deferred += int(stats.get("deferred_decisions", 0))
        valid = valid and int(stats.get("routine_decisions", 0)) <= world.ai_context.routine_budget
        path_nodes += int(stats["path_nodes"])
        decisions += int(stats["decisions"])
        interactions += int(stats["interactions"])
        max_nodes = maxi(max_nodes, stats["path_nodes"])
        max_requests = maxi(max_requests, stats["path_requests"])
        max_candidates = maxi(max_candidates, stats["social_candidates"])
        valid = valid and int(stats["path_requests"]) <= AI.Perception.MAX_PATH_REQUESTS and int(stats["path_nodes"]) <= AI.Perception.MAX_PATH_REQUESTS * AI.Nav.MAX_NODES
        valid = valid and int(stats["social_candidates"]) <= int(stats["decisions"]) * AI.Perception.MAX_CANDIDATES
    var cognition_memory: int = OS.get_static_memory_usage() - before_memory
    var total := 0
    for value in times:
        total += value
    times.sort()
    var ties := 0
    var memories := 0
    var beliefs := 0
    var goals := {}
    for state in world.citizen_ai_by_id.values():
        ties += state["relationships"].size()
        memories += state["memories"].size()
        beliefs += state["beliefs"].size()
        goals[state["goal"]] = int(goals.get(state["goal"], 0)) + 1
        valid = valid and state["relationships"].size() <= AI.Relations.CAPACITY and state["memories"].size() <= AI.Memory.CAPACITY and state["beliefs"].size() <= AI.Perception.BELIEF_CAPACITY
    # A populated cognition state must also survive actual JSON save/resume.
    var save_start := Time.get_ticks_usec()
    var prepared: Dictionary = world.snapshot()
    var snapshot_ms := float(Time.get_ticks_usec() - save_start) / 1000.0
    var encode_start := Time.get_ticks_usec()
    var save_json := JSON.stringify(prepared)
    var encode_ms := float(Time.get_ticks_usec() - encode_start) / 1000.0
    var save_ms := float(Time.get_ticks_usec() - save_start) / 1000.0
    var load_start := Time.get_ticks_usec()
    var restored = Simulation.from_snapshot(JSON.parse_string(save_json))
    var load_ms := float(Time.get_ticks_usec() - load_start) / 1000.0
    valid = valid and restored != null and restored.snapshot() == world.snapshot()
    var binary := {}
    if world.has_method("prepare_save_bytes"):
        var binary_start := Time.get_ticks_usec()
        var bytes: PackedByteArray = world.prepare_save_bytes()
        var binary_prepare_ms := float(Time.get_ticks_usec() - binary_start) / 1000.0
        var path := "user://ai-benchmark.save"
        binary_start = Time.get_ticks_usec()
        var write: Error = world.SaveStore.replace(path, bytes)
        var disk_ms := float(Time.get_ticks_usec() - binary_start) / 1000.0
        binary_start = Time.get_ticks_usec()
        var loaded: RefCounted = world.load_file(path)
        var binary_load_ms := float(Time.get_ticks_usec() - binary_start) / 1000.0
        valid = valid and write == OK and loaded != null and loaded.snapshot() == prepared
        binary = {"prepare_ms":binary_prepare_ms, "write_flush_replace_ms":disk_ms, "load_ms":binary_load_ms, "bytes":bytes.size()}
        DirAccess.remove_absolute(path)
    if restored != null:
        for i in range(30):
            world.step()
            restored.step()
        valid = valid and restored.snapshot() == world.snapshot()
    var result := {"routine_budget":routine_budget, "warmup_deferred_decisions":warmup_deferred, "memory_samples":memory_samples, "max_routine_decisions":max_routine, "deferred_decisions":deferred, "binary_atomic":binary,
        "early_third_mean_ms":float(early_total) / (ticks / 3) / 1000.0, "late_third_mean_ms":float(late_total) / (ticks / 3) / 1000.0,
        "snapshot_ms":snapshot_ms, "json_encode_ms":encode_ms, "population": population, "dense": dense, "warmup_ticks": 120, "measured_ticks": ticks,
        "mean_ms": float(total) / ticks / 1000.0, "p50_ms": float(times[ticks / 2]) / 1000.0,
        "p95_ms": float(times[mini(ticks - 1, ticks * 95 / 100)]) / 1000.0,
        "p99_ms": float(times[mini(ticks - 1, ticks * 99 / 100)]) / 1000.0,
        "max_ms": float(times[-1]) / 1000.0, "world_static_delta_bytes": cognition_memory,
        "json_save_bytes": save_json.to_utf8_buffer().size(), "json_save_ms": save_ms, "json_load_ms": load_ms, "relationships": ties,
        "memories": memories, "beliefs": beliefs, "decisions": decisions,
        "interactions": interactions, "path_nodes": path_nodes,
        "max_path_nodes_per_tick": max_nodes, "max_path_requests_per_tick": max_requests,
        "max_social_candidates_per_tick": max_candidates, "goals": goals, "bounds_and_replay_passed": valid}
    print("AI_BENCHMARK ", JSON.stringify(result))
    quit(0 if valid else 1)
