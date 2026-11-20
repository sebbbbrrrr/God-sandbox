extends RefCounted
class_name SandboxSimulation

const AI = preload("res://scripts/ai/citizen_ai.gd")

# Small deterministic simulation: all authoritative decisions happen at a fixed step.
# Rendering never modifies state. The next phase moves the hotspots into native C++.
const WIDTH := 96
const HEIGHT := 128
const OCEAN := 0
const BEACH := 1
const MEADOW := 2
const FOREST := 3
const MOUNTAIN := 4
const ASH := 5
const TOWN := 6
const INITIAL_PEOPLE := 160
const MAX_PEOPLE := 1500

var seed: int
var tick: int = 0
var terrain := PackedByteArray()
var citizens: Array[Dictionary] = []
var citizen_ai_by_id: Dictionary = {}
var next_id := 1
var rng: RandomNumberGenerator
var capitals := [Vector2i(-1, -1), Vector2i(-1, -1)]

func _init(world_seed: int = 424242) -> void:
    seed = world_seed
    rng = RandomNumberGenerator.new()
    rng.seed = seed
    terrain.resize(WIDTH * HEIGHT)
    generate_world()
    spawn_initial_population()

func generate_world() -> void:
    var elevation := FastNoiseLite.new()
    elevation.seed = seed
    elevation.frequency = 0.027
    elevation.fractal_type = FastNoiseLite.FRACTAL_FBM
    elevation.fractal_octaves = 4
    var moisture := FastNoiseLite.new()
    moisture.seed = seed + 32749
    moisture.frequency = 0.045
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var px := (float(x) / WIDTH - 0.5) * 2.0
            var py := (float(y) / HEIGHT - 0.5) * 2.0
            var edge := sqrt(px * px + py * py) * 0.48
            var v := 0.50 + elevation.get_noise_2d(x, y) * 0.50 - edge
            var wet := moisture.get_noise_2d(x, y)
            var type := OCEAN
            if v > 0.25:
                type = BEACH
            if v > 0.30:
                type = MEADOW
            if v > 0.40 and wet > -0.08:
                type = FOREST
            if v > 0.63:
                type = MOUNTAIN
            terrain[y * WIDTH + x] = type

func index_of(x: int, y: int) -> int:
    if x < 0 or y < 0 or x >= WIDTH or y >= HEIGHT:
        return -1
    return y * WIDTH + x

func at(x: int, y: int) -> int:
    var i := index_of(x, y)
    if i == -1:
        return OCEAN
    return terrain[i]

func is_walkable(x: int, y: int) -> bool:
    var i := index_of(x, y)
    return i >= 0 and terrain[i] != OCEAN and terrain[i] != MOUNTAIN

func add_citizen(x: int, y: int, nation: int) -> bool:
    if not is_walkable(x, y) or citizens.size() >= MAX_PEOPLE:
        return false
    citizens.append({
        "id": next_id,
        "nation": nation,
        "x": x,
        "y": y,
        "hp": 100,
        "age": 0
    })
    citizen_ai_by_id[str(next_id)] = AI.create_state(seed, next_id, tick)
    next_id += 1
    return true

func spawn_initial_population() -> void:
    for i in range(INITIAL_PEOPLE):
        var nation := i % 2
        var cx := WIDTH / 3 if nation == 0 else WIDTH * 2 / 3
        var cy := HEIGHT / 2
        for attempt in range(1200):
            var x := clampi(int(cx) + rng.randi_range(-15, 15), 0, WIDTH - 1)
            var y := clampi(int(cy) + rng.randi_range(-19, 19), 0, HEIGHT - 1)
            if add_citizen(x, y, nation):
                if capitals[nation].x == -1:
                    capitals[nation] = Vector2i(x, y)
                break

func step() -> void:
    tick += 1
    for citizen in citizens:
        if citizen["hp"] <= 0:
            continue
        if (tick + citizen["id"]) % 3 != 0:
            continue
        var id_key := str(citizen["id"])
        if not citizen_ai_by_id.has(id_key):
            citizen_ai_by_id[id_key] = AI.create_state(seed, int(citizen["id"]), tick)
        AI.step(self, citizen, citizen_ai_by_id[id_key])
        citizen["age"] += 1
    if tick % 150 == 0:
        grow_settlements()

func grow_settlements() -> void:
    for nation in range(2):
        var center: Vector2i = capitals[nation]
        if center.x < 0:
            continue
        var bx := clampi(center.x + rng.randi_range(-5, 5), 0, WIDTH - 1)
        var by := clampi(center.y + rng.randi_range(-5, 5), 0, HEIGHT - 1)
        if is_walkable(bx, by) and at(bx, by) != BEACH:
            terrain[index_of(bx, by)] = TOWN
        if citizens.size() < MAX_PEOPLE:
            add_citizen(center.x, center.y, nation)

# 0 raise land, 1 fire, 2 forest, 3 bless, 4 spawn, 5 ocean
func apply_power(power: int, x: int, y: int) -> bool:
    var idx := index_of(x, y)
    if idx == -1:
        return false
    match power:
        0:
            terrain[idx] = MEADOW
        1:
            if terrain[idx] == OCEAN:
                return false
            terrain[idx] = ASH
            for citizen in citizens:
                if abs(citizen["x"] - x) <= 1 and abs(citizen["y"] - y) <= 1:
                    citizen["hp"] = maxi(0, citizen["hp"] - 30)
        2:
            if terrain[idx] == OCEAN:
                return false
            terrain[idx] = FOREST
        3:
            for citizen in citizens:
                if abs(citizen["x"] - x) <= 2 and abs(citizen["y"] - y) <= 2:
                    citizen["hp"] = 100
        4:
            return add_citizen(x, y, citizens.size() % 2)
        5:
            terrain[idx] = OCEAN
        _:
            return false
    return true

func snapshot() -> Dictionary:
    return {
        "version": 2, "seed": seed, "tick": tick, "next_id": next_id,
        "ai_version": 1, "citizen_ai_by_id": citizen_ai_by_id,
        "terrain": Marshalls.raw_to_base64(terrain), "citizens": citizens,
        "capitals": [[capitals[0].x, capitals[0].y], [capitals[1].x, capitals[1].y]],
        "rng_state": rng.state
    }

static func from_snapshot(data: Dictionary) -> SandboxSimulation:
    var version := int(data.get("version", -1))
    if version != 1 and version != 2:
        return null
    var raw := Marshalls.base64_to_raw(str(data.get("terrain", "")))
    if raw.size() != WIDTH * HEIGHT:
        return null
    var result := SandboxSimulation.new(int(data.get("seed", 424242)))
    result.terrain = raw
    result.tick = maxi(0, int(data.get("tick", 0)))
    result.citizens.clear()
    result.citizen_ai_by_id.clear()
    var saved_people: Array = data.get("citizens", [])
    for person in saved_people:
        if typeof(person) != TYPE_DICTIONARY or result.citizens.size() >= MAX_PEOPLE:
            break
        var x := int(person.get("x", -1))
        var y := int(person.get("y", -1))
        if result.index_of(x, y) >= 0:
            result.citizens.append({
                "id": int(person.get("id", 0)), "nation": clampi(int(person.get("nation", 0)), 0, 1),
                "x": x, "y": y, "hp": clampi(int(person.get("hp", 100)), 0, 100),
                "age": maxi(0, int(person.get("age", 0)))
            })
    var stored_ai: Dictionary = data.get("citizen_ai_by_id", {}) if version == 2 and data.get("citizen_ai_by_id", {}) is Dictionary else {}
    var highest_id := 0
    for person in result.citizens:
        var person_id: int = int(person["id"])
        highest_id = maxi(highest_id, person_id)
        result.citizen_ai_by_id[str(person_id)] = AI.validate_state(
            stored_ai.get(str(person_id), null), result.seed, person_id, result.tick)
    result.next_id = maxi(highest_id + 1, int(data.get("next_id", highest_id + 1)))
    var saved_capitals: Array = data.get("capitals", [])
    if saved_capitals.size() == 2:
        for i in range(2):
            if saved_capitals[i] is Array and saved_capitals[i].size() == 2:
                result.capitals[i] = Vector2i(int(saved_capitals[i][0]), int(saved_capitals[i][1]))
    result.rng.state = int(data.get("rng_state", result.rng.state))
    return result
