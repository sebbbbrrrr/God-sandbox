extends RefCounted
class_name SandboxSimulation
signal terrain_changed(cell: Vector2i)

const SaveStore = preload("res://scripts/ai/save_store.gd")
const SaveCodec = preload("res://scripts/ai/save_codec.gd")
const AI = preload("res://scripts/ai/citizen_ai.gd")
const Construction = preload("res://scripts/ai/construction_economy.gd")
const Calendar = preload("res://scripts/ai/sim_calendar.gd")
const Lifecycle = preload("res://scripts/ai/citizen_lifecycle.gd")
const Households = preload("res://scripts/ai/households.gd")
const Food = preload("res://scripts/ai/food_survival.gd")
const Demography = preload("res://scripts/ai/autonomous_demography.gd")
const Occupations = preload("res://scripts/ai/era_occupations.gd")
const Inventory = preload("res://scripts/items/physical_inventory.gd")
const Toolmaking = preload("res://scripts/items/autonomous_toolmaking.gd")
const SettlementLifecycle = preload("res://scripts/civilisation/settlement_lifecycle.gd")
const LocalLogistics = preload("res://scripts/civilisation/local_logistics.gd")
const Settlements = preload("res://scripts/civilisation/settlement_registry.gd")
const Founding = preload("res://scripts/civilisation/founding_expeditions.gd")
const SettlementPlanner = preload("res://scripts/civilisation/settlement_planner.gd")
const RegionalEconomy = preload("res://scripts/civilisation/road_trade_economy.gd")

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
# Render-only strata. Citizen decisions and material economics still use terrain.
var visual_elevation := PackedByteArray()
var citizens: Array[Dictionary] = []
var citizen_ai_by_id: Dictionary = {}
var ai_context := AI.Perception.new()
var construction := Construction.new()
var calendar := Calendar.new()
var lifecycle := Lifecycle.new()
var households := Households.new()
var food := Food.new()
var demography := Demography.new()
var occupations := Occupations.new()
var inventory := Inventory.new()
var toolmaking := Toolmaking.new()
var regional_economy := RegionalEconomy.new()
var settlement_lifecycle := SettlementLifecycle.new()
var local_logistics := LocalLogistics.new()
var settlements := Settlements.new()
var founding := Founding.new()
var settlement_planner := SettlementPlanner.new()
var next_id := 1
var rng: RandomNumberGenerator
var capitals := [Vector2i(-1, -1), Vector2i(-1, -1)]

func _init(world_seed: int = 424242, initialize_world: bool = true) -> void:
    seed = world_seed
    rng = RandomNumberGenerator.new()
    rng.seed = seed
    terrain.resize(WIDTH * HEIGHT)
    visual_elevation.resize(WIDTH * HEIGHT)
    # Legacy stockpile access aliases the authoritative settlement balances.
    for nation in range(2):
        construction.stockpiles[nation] = inventory.stockpile(nation)
    if initialize_world:
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
            visual_elevation[y * WIDTH + x] = 0 if type == OCEAN else (3 if type == MOUNTAIN else (2 if v > 0.50 else (1 if v > 0.38 else 0)))

func index_of(x: int, y: int) -> int:
    if x < 0 or y < 0 or x >= WIDTH or y >= HEIGHT:
        return -1
    return y * WIDTH + x

func at(x: int, y: int) -> int:
    var i := index_of(x, y)
    if i == -1:
        return OCEAN
    return terrain[i]

func height_at(x: int, y: int) -> int:
    var idx := index_of(x, y)
    return int(visual_elevation[idx]) if idx >= 0 else 0

func is_walkable(x: int, y: int) -> bool:
    var i := index_of(x, y)
    return i >= 0 and terrain[i] != OCEAN and terrain[i] != MOUNTAIN

func set_terrain_cell(x: int, y: int, type: int) -> bool:
    var idx := index_of(x, y)
    if idx < 0 or type < OCEAN or type > TOWN or terrain[idx] == type:
        return false
    var was_ocean: bool = terrain[idx] == OCEAN
    terrain[idx] = type
    if type == OCEAN:
        visual_elevation[idx] = 0
    elif type == MOUNTAIN:
        visual_elevation[idx] = 3
    elif was_ocean:
        visual_elevation[idx] = 1
    construction.on_terrain_changed(self, x, y)
    regional_economy.on_terrain_changed(self, x, y)
    settlement_planner.invalidate(Vector2i(x, y))
    inventory.on_terrain_changed(self, x, y)
    households.dirty = true
    food.on_terrain_changed(self, x, y)
    ai_context.terrain_dirty = true
    ai_context.local_views.clear()
    terrain_changed.emit(Vector2i(x, y))
    return true

# Compatibility for the separate visual branch's editor/capture tests.
# The authoritative setter remains set_terrain_cell and invokes every
# construction, inventory, food and AI terrain-change hook.
func set_terrain(x: int, y: int, type: int) -> void:
    set_terrain_cell(x, y, type)

func add_citizen(x: int, y: int, nation: int) -> bool:
    if not is_walkable(x, y) or citizens.size() >= MAX_PEOPLE:
        return false
    if capitals[nation].x < 0:
        capitals[nation] = Vector2i(x, y)
    var local_id := nation
    var local_distance := 7
    for key in settlements.records:
        if settlements.nation(int(key)) != nation: continue
        var location: Vector2i = settlements.center(self,int(key))
        var distance := absi(x-location.x)+absi(y-location.y)
        if distance<local_distance:
            local_id = int(key)
            local_distance = distance
    citizens.append({
        "id": next_id,
        "nation": nation, "settlement_id": local_id,
        "x": x,
        "y": y,
        "hp": 100,
        "age": 0,
        "hunger": 0, "next_food_tick": tick + 120 + next_id % 40
    })
    lifecycle.initialise_founder(citizens[-1], seed, tick)
    households.on_citizen_added(self, citizens[-1])
    demography.initialize_citizen(self, citizens[-1])
    occupations.register_citizen(citizens[-1], tick)
    citizen_ai_by_id[str(next_id)] = AI.create_state(seed, next_id, tick)
    ai_context.added(citizens[-1], citizen_ai_by_id[str(next_id)])
    next_id += 1
    return true

# Internal lifecycle API for later household/food planners; no autonomous births
# are scheduled until nutrition and dependent care exist.
func register_birth(x: int, y: int, nation: int, parent_a: int, parent_b: int) -> bool:
    if parent_a <= 0 or parent_b <= 0 or parent_a == parent_b or not is_walkable(x, y):
        return false
    if citizens.size() >= MAX_PEOPLE:
        return false
    var adults: Array[Dictionary] = []
    for citizen in citizens:
        if int(citizen["id"]) in [parent_a, parent_b]:
            if int(citizen["hp"]) <= 0 or int(citizen["nation"]) != nation or calendar.age_years(int(citizen["birth_tick"]), tick) < 18:
                return false
            if absi(int(citizen["x"]) - x) + absi(int(citizen["y"]) - y) > 3:
                return false
            adults.append(citizen)
    if adults.size() != 2 or int(adults[0]["household_id"]) != int(adults[1]["household_id"]):
        return false
    var family: Dictionary = households.family_for(int(adults[0]["household_id"]))
    if family.is_empty() or int(family["home_id"]) <= 0:
        return false
    var house: Dictionary = households.house_by_id(self, int(family["home_id"]))
    if house.is_empty() or int(house["nation"]) != nation or absi(int(house["x"]) - x) + absi(int(house["y"]) - y) > 3:
        return false
    if not households.has_room(self, int(family["home_id"]), 1):
        return false
    # Nutrition must support both parents and the newborn; environmental
    # pressure, not the current calendar year or a fixed religion, is decisive.
    if int(adults[0].get("hunger", 0)) >= 40 or int(adults[1].get("hunger", 0)) >= 40:
        return false
    if food.total(food.pantry_for(int(family["id"]))) < 2:
        return false
    if not add_citizen(x, y, nation):
        return false
    lifecycle.register_newborn(self, citizens[-1], parent_a, parent_b)
    if not households.join_newborn(self, citizens[-1], adults[0], adults[1]):
        return false # prevalidated capacity; never continue a partially joined family
    var gestator: Dictionary = adults[0] if bool(adults[0].get("can_gestate", false)) else adults[1]
    demography.record_family_birth(self, citizens[-1], int(gestator["id"]))
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
    lifecycle.on_tick(self)
    ai_context.begin_tick(self)
    settlements.rebuild_membership(self)
    founding.tick(self)
    local_logistics.tick(self)
    if tick % 15 == 3:
        settlement_planner.update_one(self)
    construction.prune(self)
    toolmaking.prune(self)
    households.reconcile(self)
    food.on_tick(self)
    food.on_tick_households(self)
    construction.plan(self)
    regional_economy.on_tick(self)
    occupations.on_tick(self)
    for id in ai_context.update_slots[posmod(-tick, 3)]:
        var citizen: Dictionary = ai_context.people[id]
        if citizen["hp"] <= 0:
            continue
        AI.step(self, citizen, ai_context.minds[id], true)
        citizen["age"] += 1
    # Birth registration/death archival is authoritative but does not alter
    # the active AI update_slots during their traversal.
    demography.on_tick(self)

# 0 raise land, 1 fire, 2 forest, 3 bless, 4 spawn, 5 ocean
func apply_power(power: int, x: int, y: int) -> bool:
    var idx := index_of(x, y)
    if idx == -1:
        return false
    ai_context.local_views.clear()
    ai_context.terrain_dirty = true
    match power:
        0:
            set_terrain_cell(x, y, MEADOW)
        1:
            if terrain[idx] == OCEAN:
                return false
            set_terrain_cell(x, y, ASH)
            for citizen in citizens:
                if abs(citizen["x"] - x) <= 1 and abs(citizen["y"] - y) <= 1:
                    citizen["hp"] = maxi(0, citizen["hp"] - 30)
                    AI.event(self, citizen, "damage", Vector2i(x, y), 30)
                    if int(citizen["hp"]) <= 0:
                        lifecycle.record_death(self, citizen, "fire")
                elif abs(citizen["x"] - x) <= AI.Perception.RADIUS and abs(citizen["y"] - y) <= AI.Perception.RADIUS and AI.Perception.visible(self, Vector2i(citizen["x"], citizen["y"]), Vector2i(x, y)):
                    AI.event(self, citizen, "witness_damage", Vector2i(x, y), 20)
        2:
            if terrain[idx] == OCEAN:
                return false
            set_terrain_cell(x, y, FOREST)
        3:
            for citizen in citizens:
                # Bless heals the living; it does not silently undo a recorded death.
                if int(citizen["hp"]) <= 0:
                    continue
                if abs(citizen["x"] - x) <= 2 and abs(citizen["y"] - y) <= 2:
                    var restored_hp: int = 100 - int(citizen["hp"])
                    citizen["hp"] = 100
                    if restored_hp > 0:
                        AI.event(self, citizen, "healed", Vector2i(x, y), restored_hp)
        4:
            return add_citizen(x, y, citizens.size() % 2)
        5:
            set_terrain_cell(x, y, OCEAN)
        _:
            return false
    return true

func snapshot(legacy: bool = false) -> Dictionary:
    settlements.ensure_legacy(self)
    return {
        "version": 3 if legacy else 4, "seed": seed, "tick": tick, "next_id": next_id,
        "ai_version": 2 if legacy else 3, "citizen_ai_by_id": citizen_ai_by_id.duplicate(true) if legacy else SaveCodec.encode(citizen_ai_by_id),
        "terrain": Marshalls.raw_to_base64(terrain),
        "visual_elevation": Marshalls.raw_to_base64(visual_elevation), "citizens": citizens.duplicate(true),
        "capitals": [[capitals[0].x, capitals[0].y], [capitals[1].x, capitals[1].y]],
        "rng_state": str(rng.state), "routine_budget": ai_context.routine_budget,
        "construction": construction.snapshot(),
        "calendar": calendar.snapshot(), "lifecycle": lifecycle.snapshot(),
        "households": households.snapshot(),
        "food": food.snapshot(), "demography": demography.snapshot(),
        "occupations": occupations.snapshot(), "inventory": inventory.snapshot(),
        "toolmaking": toolmaking.snapshot(), "regional_economy": regional_economy.snapshot(),
        "local_logistics":local_logistics.snapshot(), "settlements": settlements.snapshot(), "founding": founding.snapshot(),
        "settlement_planner_cursor": settlement_planner.cursor
    }

static func from_snapshot(data: Dictionary) -> SandboxSimulation:
    # JSON numbers arrive as doubles. Restore canonical integer identities/counts
    # before building holder keys; binary/native snapshots need no extra copy.
    if typeof(data.get("tick", 0)) == TYPE_FLOAT:
        data = Construction.Catalogue.normalize(data.duplicate(true))
    var version := int(data.get("version", -1))
    if version not in [1, 2, 3, 4] or (version == 3 and int(data.get("ai_version", -1)) != 2) or (version == 4 and int(data.get("ai_version", -1)) != 3):
        return null
    var raw := Marshalls.base64_to_raw(str(data.get("terrain", "")))
    if raw.size() != WIDTH * HEIGHT:
        return null
    var result := SandboxSimulation.new(int(data.get("seed", 424242)), false)
    result.terrain = raw
    var saved_heights := Marshalls.base64_to_raw(str(data.get("visual_elevation", "")))
    for index in range(raw.size()):
        if saved_heights.size() == WIDTH * HEIGHT:
            result.visual_elevation[index] = 0 if raw[index] == OCEAN else clampi(int(saved_heights[index]), 0, 3)
        else:
            result.visual_elevation[index] = 3 if raw[index] == MOUNTAIN else 0
    result.tick = maxi(0, int(data.get("tick", 0)))
    result.citizens.clear()
    result.citizen_ai_by_id.clear()
    var saved_people: Variant = data.get("citizens", [])
    if not saved_people is Array:
        return null
    var ids: Dictionary = {}
    for person in saved_people:
        if typeof(person) != TYPE_DICTIONARY or result.citizens.size() >= MAX_PEOPLE:
            break
        var x := int(person.get("x", -1))
        var y := int(person.get("y", -1))
        var incoming_id: int = int(person.get("id", 0))
        if incoming_id <= 0 or ids.has(incoming_id):
            return null
        ids[incoming_id] = true
        if result.index_of(x, y) >= 0:
            var restored_citizen: Dictionary = {
                "id": int(person.get("id", 0)), "nation": clampi(int(person.get("nation", 0)), 0, 1),
                "x": x, "y": y, "hp": clampi(int(person.get("hp", 100)), 0, 100),
                "age": maxi(0, int(person.get("age", 0))),
                "hunger": clampi(int(person.get("hunger", 0)), 0, 100),
                "next_food_tick": int(person.get("next_food_tick", result.tick + 120 + incoming_id % 40)),
                "can_gestate": bool(person.get("can_gestate", Demography.can_gestate_for(result.seed, incoming_id))),
                "last_birth_tick": int(person.get("last_birth_tick", -Calendar.TICKS_PER_YEAR * 100)),
                "last_partner_decision": int(person.get("last_partner_decision", result.tick)),
                "occupation_id": str(person.get("occupation_id", "")),
                "settlement_id": int(person.get("settlement_id", person.get("nation", 0)))
            }
            if person.has("birth_tick"):
                restored_citizen["birth_tick"] = int(person["birth_tick"])
                restored_citizen["parent_ids"] = person.get("parent_ids", [])
                restored_citizen["life_stage"] = person.get("life_stage", "adult")
                restored_citizen["death_tick"] = person.get("death_tick", -1)
                restored_citizen["death_cause"] = person.get("death_cause", "")
            restored_citizen["household_id"] = int(person.get("household_id", 0))
            restored_citizen["home_id"] = int(person.get("home_id", 0))
            restored_citizen["guardian_id"] = int(person.get("guardian_id", 0))
            restored_citizen["carried_by"] = int(person.get("carried_by", 0))
            restored_citizen["last_care_tick"] = int(person.get("last_care_tick", result.tick))
            restored_citizen["care_visits"] = int(person.get("care_visits", 0))
            result.lifecycle.migrate_citizen(restored_citizen, result.seed, result.tick)
            result.citizens.append(restored_citizen)
    var stored_ai: Dictionary = data.get("citizen_ai_by_id", {}) if version >= 2 and data.get("citizen_ai_by_id", {}) is Dictionary else {}
    if version == 4:
        var expanded: Variant = SaveCodec.decode(data.get("citizen_ai_by_id"))
        if expanded == null:
            return null
        stored_ai = expanded
    var highest_id := 0
    for person in result.citizens:
        var person_id: int = int(person["id"])
        highest_id = maxi(highest_id, person_id)
        result.citizen_ai_by_id[str(person_id)] = AI.validate_state(
            stored_ai.get(str(person_id), null), result.seed, person_id, result.tick)
    for person in result.citizens:
        var mind: Dictionary = result.citizen_ai_by_id[str(person["id"])]
        for i in range(mind["relationships"].size() - 1, -1, -1):
            var other_id: int = mind["relationships"][i]["id"]
            if other_id == int(person["id"]) or not result.citizen_ai_by_id.has(str(other_id)):
                mind["relationships"].remove_at(i)
        if not result.citizen_ai_by_id.has(str(mind["target_id"])):
            mind["target_id"] = 0
    result.next_id = maxi(highest_id + 1, int(data.get("next_id", highest_id + 1)))
    var saved_capitals: Array = data.get("capitals", [])
    if saved_capitals.size() == 2:
        for i in range(2):
            if saved_capitals[i] is Array and saved_capitals[i].size() == 2:
                result.capitals[i] = Vector2i(int(saved_capitals[i][0]), int(saved_capitals[i][1]))
    result.rng.state = int(data.get("rng_state", result.rng.state))
    result.ai_context.routine_budget = clampi(int(data.get("routine_budget", 96)), 1, MAX_PEOPLE)
    if data.has("calendar") and not result.calendar.accepts_snapshot(data["calendar"]):
        return null
    if data.has("lifecycle") and not result.lifecycle.load_state(data["lifecycle"]):
        return null
    if not result.settlements.load_state(result, data.get("settlements", null)):
        return null
    result.settlement_planner.cursor = int(data.get("settlement_planner_cursor", 0))
    if not result.construction.load_state(data.get("construction", {})):
        return null
    result.ai_context.begin_tick(result)
    # v1-v4 worlds are accepted. Only absent D2 state permits migration;
    # corrupted present ledgers must fail closed rather than mint duplicates.
    if data.has("inventory"):
        if not result.inventory.load_state(result, data["inventory"]):
            return null
    else:
        result.inventory.import_legacy(result)
    for nation in range(2):
        result.construction.stockpiles[nation] = result.inventory.stockpile(nation)
    for key in result.settlements.records:
        if int(key) > 1:
            result.construction.local_stockpiles[key] = result.inventory.stockpile(int(key))
    if not result.inventory.ledger_ok():
        return null
    if not result.households.load_state(result, data.get("households", null)):
        return null
    if not result.food.load_state(data.get("food", null)):
        return null
    if not result.demography.load_state(result, data.get("demography", null)):
        return null
    if not result.occupations.load_state(result, data.get("occupations", null)):
        return null
    if not result.toolmaking.load_state(result, data.get("toolmaking", null)):
        return null
    if not result.construction.validate_restored(result):
        return null
    if not result.regional_economy.load_state(result, data.get("regional_economy", null)):
        return null
    if not result.settlements.validate(result) or not result.founding.load_state(result, data.get("founding", null)):
        return null
    if not result.local_logistics.load_state(result,data.get("local_logistics",null)): return null
    result.settlements.rebuild_membership(result)
    for key in result.food.local_depots:
        if result.settlements.get_record(int(key)).is_empty():
            return null
    return result

# Preparation runs on the simulation thread; the returned buffer owns all saved data.
func prepare_save_bytes() -> PackedByteArray:
    return SaveStore.prepare(self)

func save_atomic(path: String) -> Error:
    return SaveStore.replace(path, prepare_save_bytes())

static func load_file(path: String) -> SandboxSimulation:
    if not FileAccess.file_exists(path):
        return null
    var data: Variant = SaveStore.decode(FileAccess.get_file_as_bytes(path))
    return from_snapshot(data) if data is Dictionary else null
