extends SceneTree
# Fast, deterministic animation-contract QA; runnable without a display.
const World = preload("res://scripts/simulation.gd")
const Visuals = preload("res://scripts/construction/citizen_work_visuals.gd")
const Construction = preload("res://scripts/construction/construction_visuals.gd")
const Walk = preload("res://scripts/citizen_walk.gd")
const Game = preload("res://scripts/unified_game.gd")
var passed := true
var count := 0

func check(value: bool, title: String) -> void:
    count += 1
    if not value:
        passed = false
        push_error("FAIL: " + title)
    else:
        print("PASS: " + title)

func _initialize() -> void:
    var world = World.new(6001, false)
    var row: Dictionary = world.construction.catalogue.definition("primitive_shelter")
    var example := {"definition_id":"primitive_shelter", "stage":0, "stage_work":0}
    var before := JSON.stringify(example)
    var foundations := ["clear", "dig", "stake", "level"]
    var frames := ["saw", "mason", "lift", "hammer", "join", "brace"]
    var finish := ["roof", "thatch", "plaster", "door", "paint", "sweep"]
    check(Visuals._build_action(world, example, 0.0) in foundations, "site preparation action")
    example["stage"] = 1
    for i in range(6):
        example["stage_work"] = i
        check(Visuals._build_action(world, example, 0.0) in frames, "structural action %d" % i)
    example["stage"] = 2
    for i in range(6):
        example["stage_work"] = i
        check(Visuals._build_action(world, example, 0.0) in finish, "finishing action %d" % i)
    example["stage"] = 0
    example["stage_work"] = 0
    check(JSON.stringify(example) == before, "animations do not alter simulation stage state")
    check(Game.SIM_TICK_SECONDS == 1.0, "1x is one real second per authoritative tick")
    check(is_equal_approx(Walk.new().walk_seconds, 0.85), "default walking presentation interpolates slowly")
    check(not row.is_empty(), "animated stage matches live construction catalogue")
    check(Construction != null, "construction site visuals parse and preload")
    print("CONSTRUCTION_ANIMATION_CHECKS=", count)
    quit(0 if passed else 1)
