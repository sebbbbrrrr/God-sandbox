extends RefCounted
# D2: bounded, location-aware custody ledger for catalogue items.
# No renderer, AI decision or clock tick may create item units.
# Holder IDs: settlement:<nation>, citizen:<id>, ground:<tile_index>.
const Catalogue = preload("res://scripts/items/item_catalogue.gd")
const VERSION := 1
const MAX_STORES := 2000
const MAX_STACK := 1000000
const MAX_EVENTS := 96
const MAX_CARRY_KG := 20.0

var catalogue = Catalogue.new()
var balances: Dictionary = {}
var minted: Dictionary = {}
var consumed: Dictionary = {}
var destroyed: Dictionary = {}
var events: Array[Dictionary] = []

func _init() -> void:
    ensure_settlements()

func ensure_settlements() -> void:
    for nation in range(2):
        var key := "settlement:" + str(nation)
        if not balances.has(key):
            balances[key] = {"wood": 0, "stone": 0}

# Legacy construction.stockpiles[] is a read-through compatibility reference
# to this same dictionary, not an independently updated inventory.
func stockpile(nation: int) -> Dictionary:
    if nation not in [0, 1]:
        return {}
    return balances["settlement:" + str(nation)]

func held(holder: String, item_id: String) -> int:
    return int(balances.get(holder, {}).get(item_id, 0))

func citizen_inventory(citizen_id: int) -> Dictionary:
    return balances.get("citizen:" + str(citizen_id), {}).duplicate(true)

func settlement_inventory(nation: int) -> Dictionary:
    return stockpile(nation).duplicate(true)

func ground_inventory(world: RefCounted, x: int, y: int) -> Dictionary:
    var index: int = world.index_of(x, y)
    return balances.get("ground:" + str(index), {}).duplicate(true) if index >= 0 else {}

func _person(world: RefCounted, citizen_id: int) -> Dictionary:
    var from_context: Dictionary = world.ai_context.people.get(citizen_id, {})
    if not from_context.is_empty():
        return from_context
    for citizen in world.citizens:
        if int(citizen["id"]) == citizen_id:
            return citizen
    return {}

func _holder(world: RefCounted, holder_id: String) -> Dictionary:
    var fields := holder_id.split(":")
    if fields.size() != 2 or not fields[1].is_valid_int() or str(int(fields[1])) != fields[1]:
        return {}
    var number := int(fields[1])
    match fields[0]:
        "settlement":
            if number not in [0, 1]:
                return {}
            var cell: Vector2i = world.capitals[number]
            if cell.x < 0:
                return {}
            return {"kind": "settlement", "owner_id": number, "nation": number,
                "cell": cell}
        "citizen":
            if number <= 0:
                return {}
            var person := _person(world, number)
            if person.is_empty():
                return {}
            return {"kind": "citizen", "owner_id": number, "nation": int(person["nation"]),
                "cell": Vector2i(int(person["x"]), int(person["y"]))}
        "ground":
            if number < 0 or number >= world.WIDTH * world.HEIGHT:
                return {}
            var cell := Vector2i(number % world.WIDTH, number / world.WIDTH)
            return {"kind": "ground", "owner_id": -1, "nation": -1, "cell": cell}
    return {}

func ownership(world: RefCounted, holder_id: String) -> Dictionary:
    var info := _holder(world, holder_id)
    if info.is_empty():
        return {}
    return {"kind": info["kind"], "owner_id": info["owner_id"], "nation": info["nation"]}

func _distance(a: Vector2i, b: Vector2i) -> int:
    return absi(a.x - b.x) + absi(a.y - b.y)

func _access(holder: Dictionary, actor: Dictionary, as_source: bool) -> bool:
    match str(holder["kind"]):
        "citizen":
            # A citizen may give possessions they carry. Same-nation handovers
            # require the recipient to be present (receiver consent is D3 AI).
            return int(holder["owner_id"]) == int(actor["owner_id"]) if as_source else \
                int(holder["nation"]) == int(actor["nation"])
        "settlement":
            return int(holder["nation"]) == int(actor["nation"])
        "ground":
            return true
    return false

func _weight(items: Dictionary) -> float:
    var total := 0.0
    for item_id in items:
        var definition: Dictionary = catalogue.items.get(str(item_id), {})
        if definition.is_empty():
            return INF
        total += float(definition["physical"].get("mass_kg", 0.0)) * int(items[item_id])
    return total

func _bundle_valid(units: Dictionary) -> bool:
    if units.is_empty() or units.size() > 96:
        return false
    for item_id in units:
        if not item_id is String or not catalogue.items.has(item_id):
            return false
        if typeof(units[item_id]) != TYPE_INT or int(units[item_id]) <= 0 or int(units[item_id]) > MAX_STACK:
            return false
    return true

func _log(world: RefCounted, action: String, source: String, target: String, units: Dictionary) -> void:
    events.append({"tick": int(world.tick), "action": action, "from": source,
        "to": target, "units": units.duplicate(true)})
    if events.size() > MAX_EVENTS:
        events.pop_front()

# All-or-nothing transaction. Physical custody and actor permissions are
# checked at the time of transfer; neither side may be remotely accessed.
func transfer(world: RefCounted, source: String, target: String, units: Dictionary, actor_id: int) -> bool:
    if source == target or not _bundle_valid(units):
        return false
    var actor_person := _person(world, actor_id)
    if actor_person.is_empty() or int(actor_person.get("hp", 0)) <= 0:
        return false
    var actor := _holder(world, "citizen:" + str(actor_id))
    var from := _holder(world, source)
    var to := _holder(world, target)
    if actor.is_empty() or from.is_empty() or to.is_empty():
        return false
    if _distance(actor["cell"], from["cell"]) > 1 or _distance(actor["cell"], to["cell"]) > 1:
        return false
    if not _access(from, actor, true) or not _access(to, actor, false):
        return false
    var original: Dictionary = balances.get(source, {})
    var target_items: Dictionary = balances.get(target, {})
    var updated: Dictionary = target_items.duplicate()
    for item_id in units:
        var qty := int(units[item_id])
        if int(original.get(item_id, 0)) < qty or int(updated.get(item_id, 0)) > MAX_STACK - qty:
            return false
        updated[item_id] = int(updated.get(item_id, 0)) + qty
    if str(to["kind"]) == "citizen" and _weight(updated) > MAX_CARRY_KG:
        return false
    if not balances.has(target) and balances.size() >= MAX_STORES:
        return false
    if not balances.has(target):
        balances[target] = {}
    var dst: Dictionary = balances[target]
    for item_id in units:
        var qty := int(units[item_id])
        original[item_id] = int(original[item_id]) - qty
        if int(original[item_id]) == 0 and not (source.begins_with("settlement:") and item_id in ["wood", "stone"]):
            original.erase(item_id)
        dst[item_id] = int(dst.get(item_id, 0)) + qty
    _log(world, "transfer", source, target, units)
    return true

# The only first-slice environmental source: finite wood and stone cells.
# Both the terrain precondition and the citizen's proximity are mandatory.
func extract(world: RefCounted, citizen_id: int, item_id: String, source: Vector2i, quantity: int = 1) -> bool:
    if item_id not in ["wood", "stone"] or quantity <= 0 or quantity > 4:
        return false
    var person := _person(world, citizen_id)
    if person.is_empty() or int(person.get("hp", 0)) <= 0:
        return false
    var holder_id := "citizen:" + str(citizen_id)
    var actor := _holder(world, holder_id)
    if actor.is_empty() or _distance(actor["cell"], source) > 1:
        return false
    if world.construction.left_at(world, source.x, source.y, item_id) < quantity:
        return false
    var inventory: Dictionary = balances.get(holder_id, {})
    var next_items := inventory.duplicate()
    if int(next_items.get(item_id, 0)) > MAX_STACK - quantity:
        return false
    next_items[item_id] = int(next_items.get(item_id, 0)) + quantity
    if _weight(next_items) > MAX_CARRY_KG or (not balances.has(holder_id) and balances.size() >= MAX_STORES):
        return false
    if not balances.has(holder_id):
        balances[holder_id] = {}
    balances[holder_id][item_id] = int(balances[holder_id].get(item_id, 0)) + quantity
    var index: int = world.index_of(source.x, source.y)
    var cell_key := str(index)
    world.construction.depleted[cell_key] = int(world.construction.depleted.get(cell_key, 0)) + quantity
    minted[item_id] = int(minted.get(item_id, 0)) + quantity
    _log(world, "extract", "terrain:" + cell_key, holder_id, {item_id: quantity})
    return true

# Construction consumes carried materials at the actual house site.
func consume(world: RefCounted, holder_id: String, units: Dictionary, actor_id: int, reason: String) -> bool:
    if not _bundle_valid(units):
        return false
    var person := _person(world, actor_id)
    if person.is_empty() or int(person.get("hp", 0)) <= 0:
        return false
    var actor := _holder(world, "citizen:" + str(actor_id))
    var owner := _holder(world, holder_id)
    if actor.is_empty() or owner.is_empty() or not _access(owner, actor, true) or \
            _distance(actor["cell"], owner["cell"]) > 1:
        return false
    var inventory: Dictionary = balances.get(holder_id, {})
    for item_id in units:
        if int(inventory.get(item_id, 0)) < int(units[item_id]):
            return false
    for item_id in units:
        inventory[item_id] = int(inventory[item_id]) - int(units[item_id])
        if int(inventory[item_id]) == 0:
            inventory.erase(item_id)
        consumed[item_id] = int(consumed.get(item_id, 0)) + int(units[item_id])
    _log(world, "consume:" + reason.substr(0, 24), holder_id, "", units)
    return true

# Death leaves physically located, retrievable items, not phantom refunds.
func drop_on_death(world: RefCounted, person: Dictionary) -> void:
    var holder_id := "citizen:" + str(person["id"])
    var inventory: Dictionary = balances.get(holder_id, {})
    if inventory.is_empty():
        return
    var index: int = world.index_of(int(person["x"]), int(person["y"]))
    var target := "ground:" + str(index)
    var can_drop := index >= 0 and world.at(int(person["x"]), int(person["y"])) != world.OCEAN
    if can_drop and not balances.has(target) and balances.size() >= MAX_STORES:
        can_drop = false
    if can_drop and not balances.has(target):
        balances[target] = {}
    for item_id in inventory.keys():
        var qty := int(inventory[item_id])
        if can_drop and int(balances[target].get(item_id, 0)) <= MAX_STACK - qty:
            balances[target][item_id] = int(balances[target].get(item_id, 0)) + qty
        else:
            destroyed[item_id] = int(destroyed.get(item_id, 0)) + qty
        _log(world, "death_drop" if can_drop else "death_loss", holder_id, target if can_drop else "", {item_id: qty})
    balances.erase(holder_id)

# Dead citizens retain no invisible inventories. Deaths can occur outside jobs.
func reconcile_deaths(world: RefCounted) -> void:
    for holder_id in balances.keys():
        if not str(holder_id).begins_with("citizen:"):
            continue
        var citizen_id := int(str(holder_id).trim_prefix("citizen:"))
        var person := _person(world, citizen_id)
        if not person.is_empty() and int(person.get("hp", 0)) <= 0:
            drop_on_death(world, person)

func on_terrain_changed(world: RefCounted, x: int, y: int) -> void:
    if world.at(x, y) not in [world.OCEAN, world.ASH]:
        return
    var holder_id := "ground:" + str(world.index_of(x, y))
    var contents: Dictionary = balances.get(holder_id, {})
    for item_id in contents:
        destroyed[item_id] = int(destroyed.get(item_id, 0)) + int(contents[item_id])
    if not contents.is_empty():
        _log(world, "terrain_loss", holder_id, "", contents)
    balances.erase(holder_id)

# Migration imports existing construction stockpiles and job cargo once.
# Old saves have no provenance ledger: retained units become opening credits.
func import_legacy(world: RefCounted) -> void:
    ensure_settlements()
    for nation in range(2):
        var old: Dictionary = world.construction.stockpiles[nation]
        for item_id in ["wood", "stone"]:
            var qty := maxi(0, int(old.get(item_id, 0)))
            if qty > 0:
                stockpile(nation)[item_id] = qty
                minted[item_id] = int(minted.get(item_id, 0)) + qty
    for id in world.construction.jobs:
        var person := _person(world, int(id))
        if person.is_empty():
            continue
        var task: Dictionary = world.construction.jobs[id]
        for item_id in ["wood", "stone"]:
            var qty := maxi(0, int(task.get(item_id, 0)))
            if qty > 0:
                var holder := "citizen:" + str(id)
                if not balances.has(holder):
                    balances[holder] = {}
                balances[holder][item_id] = int(balances[holder].get(item_id, 0)) + qty
                minted[item_id] = int(minted.get(item_id, 0)) + qty

func snapshot() -> Dictionary:
    return {"version": VERSION, "balances": balances.duplicate(true),
        "minted": minted.duplicate(true), "consumed": consumed.duplicate(true),
        "destroyed": destroyed.duplicate(true), "events": events.duplicate(true)}

func _valid_counts(source: Variant) -> bool:
    if not source is Dictionary or source.size() > catalogue.items.size():
        return false
    for item_id in source:
        if not item_id is String or not catalogue.items.has(item_id):
            return false
        if typeof(source[item_id]) != TYPE_INT or int(source[item_id]) < 0 or int(source[item_id]) > MAX_STACK * MAX_STORES:
            return false
    return true

func load_state(world: RefCounted, raw: Variant) -> bool:
    if not raw is Dictionary or int(raw.get("version", -1)) != VERSION:
        return false
    var input: Variant = raw.get("balances", null)
    if not input is Dictionary or input.size() > MAX_STORES:
        return false
    var candidate: Dictionary = {}
    for holder_id in input:
        if not holder_id is String or _holder(world, holder_id).is_empty():
            return false
        var contents: Variant = input[holder_id]
        if not contents is Dictionary or contents.size() > 96:
            return false
        for item_id in contents:
            if not item_id is String or not catalogue.items.has(item_id):
                return false
            var qty := int(contents[item_id])
            if typeof(contents[item_id]) != TYPE_INT or qty < 0 or qty > MAX_STACK or (qty == 0 and not (holder_id.begins_with("settlement:") and item_id in ["wood", "stone"])):
                return false
        if holder_id.begins_with("citizen:") and _weight(contents) > MAX_CARRY_KG:
            return false
        candidate[holder_id] = contents.duplicate(true)
    for kind in ["minted", "consumed", "destroyed"]:
        if not _valid_counts(raw.get(kind, null)):
            return false
    var audit: Variant = raw.get("events", null)
    if not audit is Array or audit.size() > MAX_EVENTS:
        return false
    for entry in audit:
        if not entry is Dictionary:
            return false
    var previous := snapshot()
    balances = candidate
    ensure_settlements()
    minted = raw["minted"].duplicate(true)
    consumed = raw["consumed"].duplicate(true)
    destroyed = raw["destroyed"].duplicate(true)
    events.clear()
    for row in audit:
        events.append(row.duplicate(true))
    if not ledger_ok():
        balances = previous["balances"]
        minted = previous["minted"]
        consumed = previous["consumed"]
        destroyed = previous["destroyed"]
        events = previous["events"]
        return false
    return true

func ledger_ok() -> bool:
    var held_totals: Dictionary = {}
    for store in balances.values():
        if not store is Dictionary:
            return false
        for item_id in store:
            if not catalogue.items.has(item_id) or int(store[item_id]) < 0:
                return false
            if int(store[item_id]) > 0:
                held_totals[item_id] = int(held_totals.get(item_id, 0)) + int(store[item_id])
    var keys := {}
    for bucket in [held_totals, minted, consumed, destroyed]:
        for item_id in bucket:
            keys[item_id] = true
    for item_id in keys:
        if int(minted.get(item_id, 0)) != int(held_totals.get(item_id, 0)) + \
                int(consumed.get(item_id, 0)) + int(destroyed.get(item_id, 0)):
            return false
    return true
