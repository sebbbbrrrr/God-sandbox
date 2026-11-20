extends RefCounted
## Damage, fire and visual debris for real constructed buildings.
## Authoritative simulation only. No extra world RNG, settlement planning or AI jobs.
const MAX_FIRES := 32
const MAX_RUBBLE := 192
const MAX_FIRE_UPDATES := 12
const DAMAGE_INTERVAL := 4
const RUBBLE_LIFETIME := 2400
var fires: Dictionary = {} # building id -> {started, last_damage_tick, intensity}
var rubble: Array[Dictionary] = []
var _cursor := 0

static func resistance(materials: Dictionary, era: int = 1) -> int:
    # Relative structural fire resilience based on actual invested materials.
    # Technological age alone must never magically make timber fireproof.
    var wood := int(materials.get("wood", 0)) + int(materials.get("plant_fibre", 0))
    var mineral := int(materials.get("stone", 0)) + int(materials.get("clay", 0))
    var metal := int(materials.get("iron", 0)) + int(materials.get("steel", 0))
    var total := maxi(1, wood + mineral + metal)
    return clampi(5 + int(float(mineral + metal * 2) / float(total) * 8.0), 5, 21)

static func damage_amount(house: Dictionary, intensity: int) -> int:
    var materials: Dictionary = house.get("materials", {})
    var durability := resistance(materials, int(house.get("original_age", 1)))
    return maxi(1, int(intensity) * 3 - int(durability / 4))

func ignite(engine, world, building_id: int, intensity: int = 2) -> bool:
    var house: Dictionary = engine.building_by_id(building_id)
    if house.is_empty() or intensity <= 0:
        return false
    if fires.has(building_id):
        fires[building_id]["intensity"] = maxi(intensity, int(fires[building_id]["intensity"]))
        return true
    if fires.size() >= MAX_FIRES:
        return false
    fires[building_id] = {"started": int(world.tick), "last_damage_tick": int(world.tick),
        "intensity": clampi(intensity, 1, 4)}
    return true

func ignite_at(engine, world, cell: Vector2i, intensity: int = 2) -> bool:
    var id := int(engine.placement.tiles.get(cell, 0))
    if id <= 0 or not engine.buildings_by_id.has(id):
        return false
    return ignite(engine, world, id, intensity)

# Explicit impact hooks for future tornado/flood/quake tools and weather systems.
# They never spawn damage on their own and do not create material out of nothing.
static func hazard_damage(house: Dictionary, hazard: String, strength: int) -> int:
    var durability := resistance(house.get("materials", {}),
        int(house.get("original_age", 1)))
    match hazard:
        "earthquake":
            return maxi(1, strength * 7 - int(durability / 3))
        "flood":
            return maxi(1, strength * 4 - int(durability / 2))
        "storm":
            return maxi(1, strength * 3 - int(durability / 3))
        "explosion":
            return maxi(1, strength * 9 - int(durability / 4))
    return 0

func apply_hazard_at(engine, world, cell: Vector2i, hazard: String,
        strength: int = 1) -> bool:
    if strength <= 0 or hazard not in ["earthquake", "flood", "storm", "explosion"]:
        return false
    var id := int(engine.placement.tiles.get(cell, 0))
    var house: Dictionary = engine.building_by_id(id)
    if house.is_empty():
        return false
    var amount := hazard_damage(house, hazard, clampi(strength, 1, 10))
    return engine.lifecycle.damage(engine, world, id, amount, hazard)

func record_removal(house: Dictionary, reason: String, tick: int) -> void:
    var id := int(house.get("id", 0))
    fires.erase(id)
    if reason not in ["collapse", "demolished", "terrain_destruction", "fire_collapse"]:
        return
    rubble.append({"building_id": id, "cell": [int(house["x"]), int(house["y"])],
        "definition_id": str(house.get("definition_id", "")), "cause": reason,
        "materials": house.get("materials", {}).duplicate(true),
        "tick": tick, "age": int(house.get("original_age", 1))})
    if rubble.size() > MAX_RUBBLE:
        rubble.pop_front()

func on_tick(engine, world) -> void:
    # Expire one oldest debris record per tick; do not scan every past ruin.
    if not rubble.is_empty() and int(world.tick) - int(rubble[0].get("tick", int(world.tick))) >= RUBBLE_LIFETIME:
        rubble.pop_front()
    if fires.is_empty():
        return
    var ids: Array = fires.keys()
    ids.sort()
    var inspected := mini(MAX_FIRE_UPDATES, ids.size())
    # Rotating deterministic cursor: 12 slots/tick, no starvation when 32 burn.
    for i in range(inspected):
        var id = ids[(_cursor + i) % ids.size()]
        if not fires.has(id):
            continue
        var house: Dictionary = engine.building_by_id(int(id))
        if house.is_empty():
            fires.erase(id)
            continue
        var state: Dictionary = fires[id]
        if int(world.tick) - int(state["last_damage_tick"]) < DAMAGE_INTERVAL:
            continue
        state["last_damage_tick"] = int(world.tick)
        var amount := damage_amount(house, int(state["intensity"]))
        # Existing lifecycle owns damage, archiving, footprint release and
        # household invalidation. Never bypass its resource-ledger checks.
        engine.lifecycle.damage(engine, world, int(id), amount, "fire")
        if not fires.has(id):
            continue # collapse has already removed this building
        if int(world.tick) - int(state["started"]) > 240:
            fires.erase(id)
            continue
        # Spread only on periodic pulses, to nearby real completed buildings.
        if int(world.tick) - int(state["started"]) < 16 or \
                posmod(int(world.tick) - int(state["started"]), 16) != 0:
            continue
        var candidates := 0
        for other in engine.houses:
            if candidates >= 4 or fires.size() >= MAX_FIRES:
                break
            var other_id := int(other["id"])
            if other_id == int(id) or fires.has(other_id):
                continue
            var distance := absi(int(other["x"]) - int(house["x"])) + absi(int(other["y"]) - int(house["y"]))
            if distance > 2:
                continue
            candidates += 1
            if resistance(other.get("materials", {})) <= 11 and int(state["intensity"]) >= 2:
                ignite(engine, world, other_id, maxi(1, int(state["intensity"]) - 1))

    _cursor = (_cursor + inspected) % maxi(1, ids.size())

func snapshot() -> Dictionary:
    return {"version": 1, "fires": fires.duplicate(true), "rubble": rubble.duplicate(true),
        "cursor": _cursor}

func load_state(raw: Variant, engine) -> bool:
    fires.clear()
    rubble.clear()
    _cursor = 0
    if raw == null:
        return true # old world save
    if not raw is Dictionary or int(raw.get("version", 0)) != 1:
        return false
    var saved_fires: Variant = raw.get("fires", {})
    var saved_rubble: Variant = raw.get("rubble", [])
    if not saved_fires is Dictionary or not saved_rubble is Array or saved_fires.size() > MAX_FIRES or saved_rubble.size() > MAX_RUBBLE:
        return false
    _cursor = maxi(0, int(raw.get("cursor", 0))) % maxi(1, saved_fires.size())
    for key in saved_fires:
        var id := int(key)
        var state: Variant = saved_fires[key]
        if id <= 0 or not engine.buildings_by_id.has(id) or not state is Dictionary:
            return false
        if int(state.get("intensity", 0)) not in [1, 2, 3, 4] or int(state.get("last_damage_tick", -1)) < 0:
            return false
        fires[id] = state.duplicate(true)
    for row in saved_rubble:
        if not row is Dictionary or not row.get("cell", null) is Array or row["cell"].size() != 2:
            return false
        rubble.append(row.duplicate(true))
    return true
