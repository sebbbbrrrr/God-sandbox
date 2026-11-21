extends SceneTree
const World = preload("res://scripts/simulation.gd")
const Demo = preload("res://scripts/civilisation/settlement_demo_world.gd")

func percentile(samples: Array, fraction: float) -> float:
    samples.sort()
    return float(samples[mini(samples.size() - 1, int(samples.size() * fraction))])

func _initialize() -> void:
    var report := {"engine": Engine.get_version_info()["string"], "platform": OS.get_name(),
        "hardware": OS.get_processor_name(), "android_device_tested": false, "scenarios": []}
    var passed := true
    for population in [160, 500, 1500]:
        var world = Demo.create()
        world.citizens.clear()
        world.citizen_ai_by_id.clear()
        world.households = World.Households.new()
        world.occupations = World.Occupations.new()
        world.ai_context = World.AI.Perception.new()
        world.next_id = 1
        world.settlements.ensure_legacy(world)
        var centers := [Vector2i(20, 34), Vector2i(44, 34), Vector2i(68, 34),
            Vector2i(20, 66), Vector2i(44, 66), Vector2i(68, 66)]
        world.capitals[0] = centers[0]
        var ids: Array = [0]
        for i in range(1, centers.size()):
            ids.append(world.settlements.register_camp(world, 0, centers[i], 0))
        for id in ids:
            world.settlements.get_record(int(id))["status"] = "active"
        for i in range(population):
            var which := i % centers.size()
            var cell: Vector2i = centers[which]
            world.add_citizen(cell.x, cell.y, 0)
            world.citizens[-1]["settlement_id"] = int(ids[which])
        var durations: Array = []
        var max_tick := 0
        var peak := 0
        for i in range(240):
            var started := Time.get_ticks_usec()
            world.step()
            var elapsed := Time.get_ticks_usec() - started
            durations.append(float(elapsed) / 1000.0)
            if elapsed > peak:
                peak = elapsed
                max_tick = world.tick
        var measure := {"citizens": population, "seeded_settlements": centers.size(), "ticks": 240,
            "p50_ms": percentile(durations, 0.5), "p95_ms": percentile(durations, 0.95),
            "p99_ms": percentile(durations,0.99), "save_bytes":world.prepare_save_bytes().size(),
            "static_memory_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC)),
            "inventory_events":world.inventory.events.size(),"occupation_events":world.occupations.career_events.size(),
            "max_ms": percentile(durations, 1.0), "peak_tick": max_tick,
            "result_settlements": world.settlements.records.size(), "sites": world.construction.projects.size(),
            "completed_buildings": world.construction.houses.size(),
            "inventory_conserved": world.inventory.ledger_ok(), "food_conserved": world.food.ledger_ok()}
        report["scenarios"].append(measure)
        passed = passed and bool(measure["inventory_conserved"]) and bool(measure["food_conserved"])
        print(JSON.stringify(measure))
    report["passed"] = passed
    var file := FileAccess.open("res://docs/architecture/performance.json", FileAccess.WRITE)
    file.store_string(JSON.stringify(report, "  ") + "\n")
    quit(0 if passed else 1)
