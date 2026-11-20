extends SceneTree

const Simulation = preload("res://scripts/simulation.gd")
const AI = preload("res://scripts/ai/citizen_ai.gd")
const Brush = preload("res://scripts/terrain_brush.gd")
var failures := 0
var assertions := 0

func _initialize() -> void:
    identity_and_emotion()
    memory_and_learning()
    social_and_knowledge()
    goals_and_navigation()
    persistence()
    additional_scenarios()
    if failures == 0:
        print("COGNITION_TESTS_PASSED assertions=", assertions)
    quit(0 if failures == 0 else 1)

func check(condition: bool, label: String) -> void:
    assertions += 1
    if not condition:
        failures += 1
        push_error("FAILED: " + label)
    else:
        print("PASS: " + label)

func fixture(count: int = 2) -> RefCounted:
    var world = Simulation.new(10101, false)
    world.terrain.fill(Simulation.MEADOW)
    world.citizens.clear()
    world.citizen_ai_by_id.clear()
    world.next_id = 1
    world.capitals = [Vector2i(-1, -1), Vector2i(-1, -1)]
    for i in range(count):
        world.add_citizen(30 + i, 30, i % 2)
    world.ai_context.begin_tick(world)
    return world

func identity_and_emotion() -> void:
    var a := AI.create_state(99, 1, 0)
    var b := AI.create_state(99, 1, 0)
    var c := AI.create_state(99, 2, 0)
    check(a == b and a["personality"] != c["personality"], "deterministic distinct identities and initial affect")
    var world := fixture()
    var person: Dictionary = world.citizens[0]
    var state: Dictionary = world.citizen_ai_by_id["1"]
    var distant: Dictionary = world.citizens[1]
    distant["x"] = 70
    distant["y"] = 70
    world.ai_context.begin_tick(world)
    world.apply_power(1, 30, 30)
    check(person["hp"] == 70 and int(state["emotions"]["stress"]) > 0 and int(state["emotions"]["anger"]) > 0, "real fire damage appraises stress and anger")
    check(world.citizen_ai_by_id["2"]["memories"].is_empty(), "unobserved distant fire gives no memory")
    var distress: int = state["emotions"]["stress"]
    world.apply_power(3, 30, 30)
    check(person["hp"] == 100 and int(state["emotions"]["stress"]) < distress, "actual healing reduces distress")
    AI.event(world, person, "damage", Vector2i(30, 30), 40, 2)
    check(AI.Relations.find(state, 2).is_empty() and state["memories"][-1]["participants"].is_empty(), "unseen actor identity is not inferred")
    var cautious := AI.create_state(99, 1, 0)
    var bold := cautious.duplicate(true)
    cautious["personality"]["caution"] = 100
    bold["personality"]["caution"] = 0
    AI.Emotions.react(cautious, "danger", 40, 0)
    AI.Emotions.react(bold, "danger", 40, 0)
    check(int(cautious["emotions"]["fear"]) > int(bold["emotions"]["fear"]), "personality modulates appraisal")
    AI.Emotions.advance(cautious, 6000)
    check(cautious["emotions"] == AI.Emotions.create(cautious["personality"]), "all emotions recover to baseline without permanent locking")
    var split := bold.duplicate(true)
    for tick in range(1, 241):
        AI.Emotions.advance(split, tick)
    AI.Emotions.advance(bold, 240)
    check(split["emotions"] == bold["emotions"], "emotion decay independent of update batching")

func memory_and_learning() -> void:
    var state := AI.create_state(99, 1, 0)
    AI.Memory.remember(state, "damage", Vector2i(20, 20), 0, [], 90, -70, 95)
    AI.Memory.remember(state, "greeting", Vector2i(10, 10), 0, [2], 10, 10, 5)
    AI.Memory.advance(state, 600)
    check(state["memories"].size() == 2 and int(state["memories"][0]["confidence"]) > int(state["memories"][1]["confidence"]), "important memories fade more slowly")
    AI.Memory.remember(state, "damage", Vector2i(20, 20), 610, [], 90, -70, 95)
    AI.Memory.remember(state, "damage", Vector2i(20, 20), 620, [], 90, -70, 95)
    check(int(state["memories"][-1]["repetitions"]) == 2, "repeated recent episodes reinforce rather than duplicate")
    check(AI.Memory.risk(state, Vector2i(20, 20)) > 0 and AI.Memory.risk(state, Vector2i(60, 60)) == 0, "episodic danger affects only relevant locations")
    for i in range(40):
        AI.Memory.remember(state, "greeting", Vector2i(i, 5), 630 + i, [2], 1, 1, 1)
    var important_retained := false
    for record in state["memories"]:
        if record["kind"] == "damage":
            important_retained = true
    check(state["memories"].size() == AI.Memory.CAPACITY and important_retained, "bounded deterministic priority eviction retains salient episodes")
    var replay := state.duplicate(true)
    AI.Memory.advance(state, 100000)
    AI.Memory.advance(replay, 100000)
    check(state["memories"].is_empty() and state == replay, "deterministic forgetting eventually releases old memories")
    for i in range(100):
        AI.Learning.reinforce(state, "explore", -10)
        AI.Learning.reinforce(state, "socialize", 10)
    check(state["learned"]["explore"] == -60 and state["learned"]["socialize"] == 60, "reinforcement remains bounded")
    AI.Learning.advance(state, 60000)
    check(state["learned"]["explore"] == 0 and state["learned"]["socialize"] == 0, "learned preferences recover over time")

func social_and_knowledge() -> void:
    var world := fixture(3)
    var a: Dictionary = world.citizen_ai_by_id["1"]
    var b: Dictionary = world.citizen_ai_by_id["2"]
    a["personality"]["sociability"] = 100
    b["personality"]["sociability"] = 50
    var contacted := 0
    for i in range(6):
        world.tick = i * 60
        if AI.interact(world, world.citizens[0], world.citizens[1]):
            contacted += 1
    var ab := AI.Relations.find(a, 2)
    var ba := AI.Relations.find(b, 1)
    check(contacted == 6 and int(ab["trust"]) > 0 and int(ab["affinity"]) > 0, "repeated actual encounters grow friendship and trust")
    check(int(ab["affinity"]) > int(ba["affinity"]), "directional affinity reflects individual social preference")
    world.tick += 60
    a["emotions"]["stress"] = 80
    b["emotions"]["stress"] = 0
    var trust_a: int = ab["trust"]
    var trust_b: int = ba["trust"]
    AI.interact(world, world.citizens[0], world.citizens[1])
    check(int(ab["trust"]) - trust_a > int(ba["trust"]) - trust_b, "receiving real support builds asymmetric trust")
    check(int(a["emotions"]["stress"]) < 80, "supporting encounter actually reduces stress")
    world.tick += 60
    var affinity_before_conflict: int = ab["affinity"]
    a["personality"]["aggression"] = 100
    a["emotions"]["anger"] = 100
    AI.interact(world, world.citizens[0], world.citizens[1])
    check(int(ab["rivalry"]) > 0 and int(ab["affinity"]) < affinity_before_conflict, "hostile encounter develops rivalry from actual distress")
    check(not AI.interact(world, world.citizens[0], world.citizens[1]), "encounter cooldown prevents repeated same-tick rewards")
    var isolated := AI.create_state(3, 4, 0)
    AI.advance_needs(isolated, 900)
    check(int(isolated["needs"]["social"]) > 0 and isolated["relationships"].is_empty(), "isolation does not manufacture social contacts")
    for id in range(10, 100):
        AI.Relations.encounter(a, id, Vector2i(1, 1), world.tick, "friendly")
    check(a["relationships"].size() == AI.Relations.CAPACITY, "relationships remain bounded")
    a["beliefs"].clear()
    b["beliefs"].clear()
    AI.Perception.observe(a, Vector2i(60, 60), Simulation.ASH, 10)
    check(b["beliefs"].is_empty(), "direct observation stays private before communication")
    AI.Perception.share(a, b, 1, 80, 20)
    check(b["beliefs"].size() == 1 and b["beliefs"][0]["source"] == "shared" and b["beliefs"][0]["source_id"] == 1 and int(b["beliefs"][0]["confidence"]) < 100, "shared information preserves provenance and reduced confidence")
    AI.Perception.observe(b, Vector2i(60, 60), Simulation.MEADOW, 30, true)
    AI.Perception.share(a, b, 1, 100, 40)
    check(int(b["beliefs"][0]["terrain"]) == Simulation.MEADOW and b["beliefs"][0]["source"] == "direct", "fresh direct contradiction overrides stale rumour")
    for i in range(60):
        AI.Perception.observe(a, Vector2i(i, 20), Simulation.FOREST, i)
    check(a["beliefs"].size() == AI.Perception.BELIEF_CAPACITY, "knowledge is bounded")
    var barrier := fixture()
    barrier.terrain[barrier.index_of(31, 30)] = Simulation.MOUNTAIN
    barrier.citizens[1]["x"] = 32
    check(not AI.Perception.visible(barrier, Vector2i(30, 30), Vector2i(32, 30)), "mountain blocks direct perception")

func goals_and_navigation() -> void:
    var world := fixture()
    var person: Dictionary = world.citizens[0]
    var state: Dictionary = world.citizen_ai_by_id["1"]
    state["needs"]["fatigue"] = 100
    AI.Decisions.choose(world, person, state, [], false)
    check(state["goal"] == "rest", "utility prioritizes acute fatigue")
    state["needs"]["fatigue"] = 0
    state["emotions"]["fear"] = 0
    state["needs"]["social"] = 100
    state["personality"]["sociability"] = 100
    state["commit_until"] = 0
    AI.Decisions.choose(world, person, state, [world.citizens[1]], false)
    check(state["goal"] == "socialize" and state["target_id"] == 2, "companionship goal targets actual locally known person")
    state["needs"]["social"] = 0
    state["personality"]["curiosity"] = 100
    state["goal"] = "explore"
    state["commit_until"] = 100
    state["target"] = [34, 30]
    AI.Decisions.choose(world, person, state, [], false)
    check(state["goal"] == "explore" and state["target"] == [34, 30], "goal commitment preserves viable target")
    var learned := state.duplicate(true)
    AI.Perception.observe(state, Vector2i(32, 30), Simulation.FOREST, 0)
    learned["beliefs"] = state["beliefs"].duplicate(true)
    state["learned"]["explore"] = 60
    learned["learned"]["explore"] = -60
    learned["commit_until"] = 0
    AI.Decisions.choose(world, person, state, [], false)
    AI.Decisions.choose(world, person, learned, [], false)
    check(state["goal"] == "explore" and learned["goal"] != state["goal"], "experienced outcomes change executable goal preference")
    var position := Vector2i(person["x"], person["y"])
    world.apply_power(1, position.x, position.y)
    AI.step(world, person, state)
    check(state["goal"] == "seek_safety", "immediate danger interrupts commitment")
    for i in range(20):
        world.step()
    check(not AI.danger_near(world, Vector2i(person["x"], person["y"])), "citizen escapes observed fire")
    var path_world := fixture(1)
    var mind: Dictionary = path_world.citizen_ai_by_id["1"]
    var start := Vector2i(30, 30)
    var finish := Vector2i(34, 30)
    for y in range(27, 33):
        path_world.terrain[path_world.index_of(32, y)] = Simulation.OCEAN
    var path := AI.Nav.plan(path_world, mind, start, finish)
    var location := start
    var legal := not path.is_empty()
    for step in path:
        var cell := Vector2i(step[0], step[1])
        legal = legal and path_world.is_walkable(cell.x, cell.y) and AI.Nav.manhattan(location, cell) == 1
        location = cell
    check(legal and location == finish, "bounded pathfinding finds alternative around barrier")
    var mover: Dictionary = path_world.citizens[0]
    mind["route"] = [[31, 30], [32, 30]]
    mind["next_path_tick"] = 999
    Brush.paint_segment(path_world, 5, Vector2i(31, 30), Vector2i(31, 30), 0)
    var next := AI.Nav.next_step(path_world, mover, mind, Vector2i(34, 30))
    check(next != Vector2i(31, 30) and mind["route"].is_empty(), "direct brush flood invalidates cached next step")
    path_world.terrain.fill(Simulation.MEADOW)
    AI.Memory.remember(mind, "damage", Vector2i(31, 30), 0, [], 100, -100, 100)
    path_world.ai_context.begin_tick(path_world)
    mind["next_path_tick"] = 0
    var avoided := AI.Nav.plan(path_world, mind, start, finish)
    check(not avoided.is_empty() and avoided[0] != [31, 30], "navigation avoids remembered injury location")
    var flood_world := fixture(1)
    var victim: Dictionary = flood_world.citizens[0]
    flood_world.apply_power(5, 30, 30)
    for i in range(3):
        flood_world.step()
    check(flood_world.is_walkable(victim["x"], victim["y"]), "flooded citizen escapes to adjacent walkable ground")
    flood_world.terrain.fill(Simulation.OCEAN)
    var before := Vector2i(victim["x"], victim["y"])
    for i in range(6):
        flood_world.step()
    check(Vector2i(victim["x"], victim["y"]) == before, "trapped citizen stays put rather than teleporting")

func persistence() -> void:
    var a := fixture(3)
    for i in range(180):
        if i == 35:
            a.apply_power(1, a.citizens[0]["x"], a.citizens[0]["y"])
        a.step()
    var frozen_legacy: Dictionary = a.snapshot(true)
    var frozen: Dictionary = a.snapshot()
    var immutable := var_to_bytes(frozen)
    var json_data: Dictionary = JSON.parse_string(JSON.stringify(frozen))
    var b = Simulation.from_snapshot(json_data)
    check(b != null and a.snapshot() == b.snapshot(), "JSON snapshot restores all cognition and exact RNG state")
    for i in range(180):
        if i == 40:
            for world in [a, b]:
                world.apply_power(3, world.citizens[0]["x"], world.citizens[0]["y"])
        a.step()
        b.step()
    check(a.snapshot() == b.snapshot(), "JSON save continuation stays deterministic with powers and settlement growth")
    check(var_to_bytes(frozen) == immutable, "captured snapshots cannot mutate with live world")
    var legacy: Dictionary = frozen_legacy.duplicate(true)
    legacy["version"] = 1
    legacy.erase("citizen_ai_by_id")
    legacy.erase("ai_version")
    var migrated = Simulation.from_snapshot(legacy)
    check(migrated != null and migrated.citizens == frozen["citizens"] and migrated.terrain == Marshalls.base64_to_raw(frozen["terrain"]) and str(migrated.rng.state) == frozen["rng_state"], "v1 migration preserves physical world and RNG")
    legacy = frozen_legacy.duplicate(true)
    legacy["version"] = 2
    legacy["ai_version"] = 1
    for id in legacy["citizen_ai_by_id"]:
        var original: Dictionary = legacy["citizen_ai_by_id"][id]
        legacy["citizen_ai_by_id"][id] = {"personality": original["personality"], "needs": original["needs"], "goal": "explore", "last_decision": 170, "last_needs_tick": 180,
            "memories": [{"kind": "danger", "cell": [30, 30], "tick": 100}], "danger_cell": [30, 30]}
    migrated = Simulation.from_snapshot(legacy)
    check(migrated != null and migrated.citizen_ai_by_id["1"]["memories"][0]["participants"] == [] and migrated.citizen_ai_by_id["1"]["personality"] == frozen_legacy["citizen_ai_by_id"]["1"]["personality"], "v2 basic danger memories and identity migrate to structured schema")
    var clean := AI.validate_state({"emotions": [], "relationships": [null, {"id": 2, "trust": 9999}], "memories": [false, {"cell": "invalid"}], "beliefs": [null], "route": [null], "personality": {"caution": -100}}, 1, 1, 100)
    check(clean["emotions"].size() == 7 and clean["relationships"][0]["trust"] == 100 and clean["memories"].is_empty() and clean["personality"]["caution"] == 0, "malformed nested cognition safely sanitizes and clamps")
    var duplicate: Dictionary = frozen.duplicate(true)
    duplicate["citizens"][1]["id"] = duplicate["citizens"][0]["id"]
    check(Simulation.from_snapshot(duplicate) == null, "duplicate persistent citizen identity is rejected")
    var inspected := AI.inspect(a.citizen_ai_by_id["1"])
    inspected["emotions"]["fear"] = -999
    check(a.citizen_ai_by_id["1"]["emotions"]["fear"] >= 0, "inspection returns detached read-only data")

func additional_scenarios() -> void:
    var world := fixture(1)
    var person: Dictionary = world.citizens[0]
    var state: Dictionary = world.citizen_ai_by_id["1"]
    state["personality"]["curiosity"] = 0
    state["learned"]["explore"] = -60
    state["goal"] = "rest"
    AI.Decisions.choose(world, person, state, [], false)
    var knows_settlement := false
    for option in state["utilities"]:
        knows_settlement = knows_settlement or option["goal"] == "seek_settlement"
    check(not knows_settlement, "unseen national capital is not a known settlement")
    AI.Perception.observe(state, Vector2i(32, 30), Simulation.TOWN, 0)
    AI.Decisions.choose(world, person, state, [], false)
    check(state["goal"] == "seek_settlement" and state["target"] == [32, 30], "observed settlement creates executable travel goal")
    state["beliefs"].clear()
    state["goal"] = "rest"
    state["personality"]["curiosity"] = 100
    AI.Perception.observe(state, Vector2i(32, 30), Simulation.FOREST, 0)
    AI.Decisions.choose(world, person, state, [], false)
    check(state["goal"] == "investigate", "unfamiliar observed location can win investigation utility")
    state["beliefs"].clear()
    AI.Perception.observe(state, Vector2i(28, 30), Simulation.MEADOW, 0, true)
    AI.Perception.observe(state, Vector2i(28, 30), Simulation.MEADOW, 1, true)
    state["emotions"]["fear"] = 90
    state["emotions"]["stress"] = 60
    state["goal"] = "rest"
    AI.Decisions.choose(world, person, state, [], false)
    check(state["goal"] == "return_familiar", "distress motivates returning to an actually familiar area")
    var lone := fixture(1)
    var lonely: Dictionary = lone.citizen_ai_by_id["1"]
    lonely["goal"] = "socialize"
    lonely["target"] = [30, 30]
    lonely["next_decision"] = 100
    lonely["needs"]["social"] = 90
    AI.step(lone, lone.citizens[0], lonely)
    check(lonely["needs"]["social"] == 90, "social goal without contact cannot satisfy loneliness")
    var small := fixture(1)
    small.terrain.fill(Simulation.OCEAN)
    small.terrain[small.index_of(31, 30)] = Simulation.MEADOW
    for i in range(3):
        small.step()
    check(small.citizens[0]["x"] == 31 and small.citizens[0]["y"] == 30, "safety finds the only adjacent refuge on edited island")
    var nav_world := fixture(1)
    var nav_state: Dictionary = nav_world.citizen_ai_by_id["1"]
    var unseen := Vector2i(38, 30)
    var empty_cost := AI.Nav.hazard_cost(nav_world, nav_state, unseen)
    nav_world.terrain[nav_world.index_of(unseen.x, unseen.y)] = Simulation.ASH
    nav_world.ai_context.begin_tick(nav_world)
    check(AI.Nav.hazard_cost(nav_world, nav_state, unseen) == empty_cost and nav_state["beliefs"].is_empty(), "unobserved distant fire cannot alter subjective route risk")
    var informant := AI.create_state(1, 2, 0)
    AI.Perception.observe(informant, unseen, Simulation.ASH, 1)
    AI.Perception.share(informant, nav_state, 2, 80, 2)
    nav_world.ai_context.begin_tick(nav_world)
    check(AI.Nav.hazard_cost(nav_world, nav_state, unseen) > empty_cost, "communicated danger belief changes subjective navigation risk")
    var third := AI.create_state(1, 3, 0)
    var fourth := AI.create_state(1, 4, 0)
    AI.Perception.share(nav_state, third, 1, 100, 3)
    AI.Perception.share(third, fourth, 3, 100, 4)
    check(fourth["beliefs"].is_empty(), "gossip hop and confidence limits stop unlimited diffusion")
    var society := fixture(12)
    for i in range(12):
        society.citizens[i]["x"] = 30 + i % 4
        society.citizens[i]["y"] = 30 + i / 4
    for i in range(450):
        society.step()
    var social_histories := 0
    var different := false
    var previous: Dictionary = society.citizen_ai_by_id["1"]
    for mind in society.citizen_ai_by_id.values():
        if not mind["relationships"].is_empty():
            social_histories += 1
        different = different or mind["memories"] != previous["memories"]
    check(social_histories > 1 and different, "autonomous population forms distinct event-backed social histories")
    var choice_world := fixture(3)
    var chooser: Dictionary = choice_world.citizen_ai_by_id["1"]
    choice_world.citizens[1]["x"] = 30
    choice_world.citizens[1]["y"] = 31
    choice_world.citizens[2]["x"] = 31
    var bad := AI.Relations.encounter(chooser, 2, Vector2i(30, 31), 0, "conflict")
    bad["affinity"] = -60
    bad["rivalry"] = 60
    chooser["needs"]["social"] = 100
    chooser["next_decision"] = 0
    choice_world.ai_context.begin_tick(choice_world)
    AI.step(choice_world, choice_world.citizens[0], chooser)
    check(AI.Relations.find(chooser, 3).get("trust", 0) > 0 and int(bad["trust"]) == 0, "autonomous encounters prefer acceptable company over disliked nearby citizen")
    var damaged := fixture(1)
    var injured: Dictionary = damaged.citizen_ai_by_id["1"]
    injured["goal"] = "explore"
    AI.event(damaged, damaged.citizens[0], "damage", Vector2i(30, 30), 30)
    check(int(injured["learned"]["explore"]) < 0, "actual harmful exploration outcome discourages exploration")
    var scheduled := fixture(12)
    var schedules: Dictionary = {}
    for mind in scheduled.citizen_ai_by_id.values():
        schedules[mind["next_decision"]] = true
    check(schedules.size() > 1, "initial decision deadlines are staggered by persistent identity")

    var immediate := fixture(2)
    var resumed = Simulation.from_snapshot(immediate.snapshot())
    for instance in [immediate, resumed]:
        AI.event(instance, instance.citizens[0], "support", Vector2i(30, 30), 10, 2)
    check(immediate.snapshot() == resumed.snapshot(), "identified-actor event immediately after load preserves exact cognition")
    var future: Dictionary = immediate.snapshot()
    future["ai_version"] = 999
    check(Simulation.from_snapshot(future) == null, "unsupported future AI schema is rejected without silent data loss")
