extends SceneTree
const World = preload("res://scripts/simulation.gd")
const Demo = preload("res://scripts/construction/demo_world.gd")
const DemoGame = preload("res://scripts/construction/demo_game.gd")
var ok := true
var results: Array = []
func _initialize() -> void:
    call_deferred("run")
func percentile(values: Array, fraction: float) -> float:
    values.sort()
    return float(values[mini(values.size()-1,int(values.size()*fraction))]) / 1000.0
func run() -> void:
    for speed in [1,2,4]:
        var game = DemoGame.new()
        root.add_child(game)
        game.set_process(false)
        game.simulation_speed = speed
        var times: Array = []
        var start: int = game.world.tick
        for frame in range(240):
            var begin := Time.get_ticks_usec()
            game._process(1.0/30.0)
            times.append(Time.get_ticks_usec()-begin)
        var ticks: int = game.world.tick-start
        results.append({"scenario":"actual_frontend_20_citizens","speed":speed,"frames":240,"ticks":ticks,"frame_cpu_p50_ms":percentile(times,0.5),"frame_cpu_p95_ms":percentile(times,0.95)})
        ok = ok and game.world.inventory.ledger_ok() and ticks > 0
        root.remove_child(game)
        game.free()
    for population in [100,500]:
        var w = Demo.create()
        for i in range(population-20):
            w.add_citizen(16,16,0)
        var times: Array = []
        for tick in range(240):
            var begin := Time.get_ticks_usec()
            w.step()
            times.append(Time.get_ticks_usec()-begin)
        results.append({"scenario":"full_world","population":population,"ticks":240,"step_cpu_p50_ms":percentile(times,0.5),"step_cpu_p95_ms":percentile(times,0.95),"ledger":w.inventory.ledger_ok()})
        ok = ok and w.inventory.ledger_ok()
    var profiled = Demo.create()
    for i in range(480):
        profiled.add_citizen(16,16,0)
    var dispatch_times: Array = []
    var construction_times: Array = []
    for tick in range(120):
        profiled.tick += 1
        profiled.lifecycle.on_tick(profiled)
        profiled.ai_context.begin_tick(profiled)
        var begin := Time.get_ticks_usec()
        profiled.construction.prune(profiled)
        construction_times.append(Time.get_ticks_usec()-begin)
        profiled.toolmaking.prune(profiled)
        profiled.households.reconcile(profiled)
        profiled.food.on_tick(profiled)
        profiled.food.on_tick_households(profiled)
        profiled.construction.plan(profiled)
        profiled.occupations.on_tick(profiled)
        begin = Time.get_ticks_usec()
        for citizen_id in profiled.ai_context.update_slots[posmod(-profiled.tick,3)]:
            var person: Dictionary = profiled.ai_context.people[citizen_id]
            if int(person["hp"]) <= 0:
                continue
            World.AI.step(profiled,person,profiled.ai_context.minds[citizen_id],true)
            person["age"] += 1
        dispatch_times.append(Time.get_ticks_usec()-begin)
        profiled.demography.on_tick(profiled)
    results.append({"scenario":"profile_500_citizens","ticks":120,"citizen_dispatch_p95_ms":percentile(dispatch_times,0.95),"construction_prune_p95_ms":percentile(construction_times,0.95)})
    var dense = World.new(7001,false)
    dense.terrain.fill(World.MEADOW)
    dense.capitals[0] = Vector2i(60,100)
    dense.add_citizen(60,100,0)
    # Synthetic completed entities isolate maintenance/index overhead; no minted supplies.
    for i in range(3000):
        var x := 1+i%75
        var y := 1+int(i/75)
        dense.terrain[dense.index_of(x,y)] = World.TOWN
        var house := {"id":i+1,"nation":0,"x":x,"y":y,"built_tick":0,"capacity":6}
        dense.construction.lifecycle.migrate(house)
        dense.construction.houses.append(house)
    dense.construction.next_building_id = 3001
    dense.construction.rebuild_indexes()
    for i in range(128):
        var result: Dictionary = dense.construction.request_construction(dense,{"settlement_id":0,"location":[1+i%64,70+int(i/64)]})
        ok = ok and result["ok"]
    var times: Array = []
    for tick in range(600):
        dense.tick += 1
        dense.ai_context.begin_tick(dense)
        var begin := Time.get_ticks_usec()
        dense.construction.prune(dense)
        times.append(Time.get_ticks_usec()-begin)
    results.append({"scenario":"construction_service_only","completed_buildings":3000,"active_sites":128,"ticks":600,"service_cpu_p50_ms":percentile(times,0.5),"service_cpu_p95_ms":percentile(times,0.95)})
    ok = ok and dense.construction.projects.size() == 128 and dense.inventory.ledger_ok()
    var fixture = Demo.create()
    for cycle in range(60):
        var result: Dictionary = fixture.construction.request_construction(fixture,{"settlement_id":0,"location":[16,18]})
        ok = ok and result["ok"]
        ok = ok and fixture.construction.cancel(fixture,int(result.get("site_id",0))) and fixture.inventory.ledger_ok()
    results.append({"scenario":"repeat_cancel","cycles":60,"remaining_sites":fixture.construction.projects.size()})
    var out := {"engine":Engine.get_version_info()["string"],"platform":"Linux headless CPU; not Android FPS","results":results,"passed":ok}
    var path := "res://docs/construction-phase-a-benchmark.json"
    var file := FileAccess.open(path,FileAccess.WRITE)
    file.store_string(JSON.stringify(out,"  ")+"\n")
    print(JSON.stringify(out))
    if ok:
        print("CONSTRUCTION_BENCHMARK_PASSED")
    quit(0 if ok else 1)
