extends RefCounted
# Stable political-independent identities. Stores remain owned by the existing
# physical inventory and food ledgers; no quantities are copied into this registry.
const MAX_SETTLEMENTS := 24
var records: Dictionary = {}
var residents: Dictionary = {} # derived sid -> living citizen IDs
var next_id := 2 # 0/1 permanently preserve the legacy capital holder names
var revision := 0

func get_record(id: int) -> Dictionary:
    return records.get(str(id), {})

func center(world: RefCounted, id: int) -> Vector2i:
    if id in [0, 1]:
        return world.capitals[id] # legacy editor/tests can still move capitals
    var row := get_record(id)
    return Vector2i(int(row.get("x", -1)), int(row.get("y", -1)))

func sid(person: Dictionary) -> int:
    return int(person.get("settlement_id", person["nation"]))

func nation(id: int) -> int:
    return int(get_record(id).get("nation", id if id in [0, 1] else -1))

func _record(id: int, political: int, cell: Vector2i, founder: int, tick: int, status: String) -> Dictionary:
    return {"id": id, "name": "Settlement %d" % (id + 1), "nation": political,
        "x": cell.x, "y": cell.y, "founder_id": founder, "founded_tick": tick,
        "status": status, "radius": 9, "knowledge": {}, "specialisation": "subsistence",
        "prosperity": 0, "stress_ticks": 0, "history": [], "plan": {}}

func ensure_legacy(world: RefCounted) -> void:
    for id in range(2):
        if not records.has(str(id)):
            records[str(id)] = _record(id, id, world.capitals[id], 0, 0, "legacy")

func register_camp(world: RefCounted, political: int, cell: Vector2i, founder: int) -> int:
    ensure_legacy(world)
    if records.size() >= MAX_SETTLEMENTS or political not in [0, 1] or not world.is_walkable(cell.x, cell.y):
        return -1
    var id := next_id
    next_id += 1
    records[str(id)] = _record(id, political, cell, founder, world.tick, "camp")
    world.inventory.balances["settlement:" + str(id)] = {"wood": 0, "stone": 0}
    world.food.store(id) # empty local store in the SAME food ledger
    event(world, id, "camp_established")
    revision += 1
    return id

func event(world: RefCounted, id: int, kind: String) -> void:
    var row := get_record(id)
    if row.is_empty():
        return
    row["history"].append({"tick": world.tick, "kind": kind})
    if row["history"].size() > 48:
        row["history"].pop_front()

func rebuild_membership(world: RefCounted) -> void:
    ensure_legacy(world)
    residents.clear()
    for key in records:
        residents[key] = []
    for person in world.citizens:
        var id := sid(person)
        person["settlement_id"] = id
        if int(person["hp"]) > 0 and residents.has(str(id)):
            residents[str(id)].append(int(person["id"]))
    for family in world.households.families:
        for member in family["members"]:
            var person: Dictionary = world.ai_context.people.get(int(member), {})
            if not person.is_empty() and int(person["hp"]) > 0:
                family["settlement_id"] = sid(person)
                break

func population(id: int) -> int:
    return residents.get(str(id), []).size()

func housing(world: RefCounted, id: int) -> int:
    var capacity := 0
    for house in world.construction.houses:
        if sid(house) == id:
            capacity += int(house.get("capacity", 0))
    return capacity

func move_households(world: RefCounted, household_ids: Array, destination: int) -> void:
    # Called only AFTER every survivor physically arrives. Nonempty pantries
    # are ineligible for this slice; no remote pantry relocation is possible.
    for id in household_ids:
        var family: Dictionary = world.households.family_for(int(id))
        if family.is_empty():
            continue
        family["settlement_id"] = destination
        family["home_id"] = 0
        for member in family["members"]:
            var person: Dictionary = world.ai_context.people.get(int(member), {})
            if person.is_empty() or int(person["hp"]) <= 0:
                continue
            person["settlement_id"] = destination
            person["home_id"] = 0
            var mind: Dictionary = world.citizen_ai_by_id[str(member)]
            mind["route"] = []
            mind["next_path_tick"] = world.tick
    world.households.dirty = true
    rebuild_membership(world)
    revision += 1

func snapshot() -> Dictionary:
    return {"version": 1, "records": records.duplicate(true), "next_id": next_id, "revision": revision}

func load_state(world: RefCounted, raw: Variant) -> bool:
    if raw == null:
        ensure_legacy(world)
        return true
    if not raw is Dictionary or int(raw.get("version", 0)) != 1 or not raw.get("records") is Dictionary:
        return false
    if raw["records"].size() < 2 or raw["records"].size() > MAX_SETTLEMENTS:
        return false
    var highest := 1
    for key in raw["records"]:
        var row: Variant = raw["records"][key]
        if not row is Dictionary or not str(key).is_valid_int() or str(int(key)) != str(key):
            return false
        var id := int(key)
        if id < 0 or int(row.get("id", -1)) != id or int(row.get("nation", -1)) not in [0, 1]:
            return false
        if id > 1 and world.index_of(int(row.get("x", -1)), int(row.get("y", -1))) < 0:
            return false
        if str(row.get("status", "")) not in ["legacy", "camp", "active", "struggling", "abandoned", "failed"]:
            return false
        if not row.get("history") is Array or row["history"].size() > 48 or not row.get("plan") is Dictionary or not row.get("knowledge") is Dictionary:
            return false
        highest = maxi(highest, id)
    if not raw["records"].has("0") or not raw["records"].has("1") or int(raw.get("next_id", 0)) <= highest:
        return false
    records = raw["records"].duplicate(true)
    next_id = int(raw["next_id"])
    revision = int(raw.get("revision", 0))
    return true

func validate(world: RefCounted) -> bool:
    for person in world.citizens:
        if get_record(sid(person)).is_empty() or nation(sid(person)) != int(person["nation"]):
            return false
    for group in [world.construction.houses, world.construction.projects]:
        for entity in group:
            if get_record(sid(entity)).is_empty() or nation(sid(entity)) != int(entity["nation"]):
                return false
    for family in world.households.families:
        var expected := -1
        for member in family["members"]:
            var person: Dictionary = world.ai_context.people.get(int(member), {})
            if person.is_empty() or int(person["hp"]) <= 0:
                continue
            if expected >= 0 and sid(person) != expected:
                return false
            expected = sid(person)
        if expected >= 0 and int(family.get("settlement_id", family["nation"])) != expected:
            return false
    return true
