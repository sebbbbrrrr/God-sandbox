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
var reservations: Dictionary = {}
var reserved_totals: Dictionary = {} # holder -> item totals; no linear scan per transfer

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
    return balances.get("settlement:" + str(nation), {})

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
            if number not in [0, 1] and world.settlements.get_record(number).is_empty():
                return {}
            var cell: Vector2i = world.settlements.center(world, number)
            # Unfounded nations still have an empty, persistable reserve; their
            # off-map capital naturally denies proximity-based transfers.
            return {"kind": "settlement", "owner_id": number, "nation": world.settlements.nation(number), "settlement_id": number,
                "cell": cell}
        "citizen":
            if number <= 0:
                return {}
            var person := _person(world, number)
            if person.is_empty():
                return {}
            return {"kind": "citizen", "owner_id": number, "nation": int(person["nation"]), "settlement_id": world.settlements.sid(person),
                "cell": Vector2i(int(person["x"]), int(person["y"]))}
        "site":
            var site: Dictionary = world.construction.site_by_id(number)
            if site.is_empty():
                return {}
            return {"kind": "site", "owner_id": number, "nation": int(site["nation"]), "settlement_id": world.settlements.sid(site),
                "cell": Vector2i(int(site["x"]), int(site["y"]))}
        "store":
            var house: Dictionary = world.construction.building_by_id(number)
            if house.is_empty() or str(house.get("function",""))!="storage": return {}
            return {"kind":"store","owner_id":number,"nation":int(house["nation"]),"settlement_id":world.settlements.sid(house),"cell":Vector2i(int(house["x"]),int(house["y"]))}
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
        "settlement", "site", "store":
            return int(holder["settlement_id"]) == int(actor["settlement_id"])
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
func transfer(world: RefCounted, source: String, target: String,
        units: Dictionary, actor_id: int, exact_serial: String = "", reservation_id: String = "") -> bool:
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
    if reservation_id != "":
        var claim: Dictionary = reservations.get(reservation_id, {})
        if str(claim.get("holder", "")) != source or target != "citizen:" + str(actor_id):
            return false
        var site: Dictionary = world.construction.site_by_id(int(reservation_id.trim_prefix("site:")))
        if site.is_empty() or world.settlements.sid(site) != int(actor["settlement_id"]):
            return false
        for item_id in units:
            if int(claim.get("units", {}).get(item_id, 0)) < int(units[item_id]):
                return false
    var original: Dictionary = balances.get(source, {})
    var target_items: Dictionary = balances.get(target, {})
    var updated: Dictionary = target_items.duplicate()
    for item_id in units:
        var qty := int(units[item_id])
        var allowed := available(source, str(item_id))
        if reservation_id != "":
            allowed += int(reservations[reservation_id]["units"].get(item_id, 0))
        if allowed < qty or int(updated.get(item_id, 0)) > MAX_STACK - qty:
            return false
        updated[item_id] = int(updated.get(item_id, 0)) + qty
    if str(to["kind"]) == "store":
        var units_total := 0
        for count in updated.values(): units_total += int(count)
        var building: Dictionary = world.construction.building_by_id(int(to["owner_id"]))
        var definition: Dictionary = world.construction.catalogue.definition(str(building.get("definition_id","")))
        if units_total>int(definition.get("storage_capacity",64)): return false
    if str(to["kind"]) == "citizen" and _weight(updated) > MAX_CARRY_KG:
        return false
    if not world.toolmaking.can_move(source, units, exact_serial):
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
    if reservation_id != "":
        for item_id in units:
            reservations[reservation_id]["units"][item_id] -= int(units[item_id])
            reserved_totals[source][item_id] -= int(units[item_id])
    world.toolmaking.move_instances(source, target, units, exact_serial)
    _log(world, "transfer", source, target, units)
    return true

# Physically settled barter: a living merchant must arrive with their actual
# cargo. Both legs move in one validated transaction; no cross-nation access
# is granted to the ordinary transfer API.
func exchange_at_market(world: RefCounted, citizen_id: int, foreign_nation: int,
        offer: Dictionary, payment: Dictionary) -> bool:
    if world.settlements.get_record(foreign_nation).is_empty() and foreign_nation not in [0,1]:
        return false
    if not _bundle_valid(offer) or not _bundle_valid(payment):
        return false
    if not world.regional_economy.authorizes_exchange(citizen_id, foreign_nation, offer, payment):
        return false
    var person := _person(world, citizen_id)
    if person.is_empty() or int(person.get("hp", 0)) <= 0 or world.settlements.sid(person) == foreign_nation:
        return false
    var cargo_id := "citizen:" + str(citizen_id)
    var depot_id := "settlement:" + str(foreign_nation)
    var depot: Vector2i = world.settlements.center(world,foreign_nation)
    if _distance(Vector2i(int(person["x"]), int(person["y"])), depot) > 1:
        return false
    var carried: Dictionary = balances.get(cargo_id, {})
    var market: Dictionary = balances.get(depot_id, {})
    var new_cargo: Dictionary = carried.duplicate()
    for item_id in offer:
        if available(cargo_id, str(item_id)) < int(offer[item_id]):
            return false
        new_cargo[item_id] = int(new_cargo.get(item_id, 0)) - int(offer[item_id])
    for item_id in payment:
        if available(depot_id, str(item_id)) < int(payment[item_id]):
            return false
        if int(new_cargo.get(item_id, 0)) > MAX_STACK - int(payment[item_id]):
            return false
        new_cargo[item_id] = int(new_cargo.get(item_id, 0)) + int(payment[item_id])
    if _weight(new_cargo) > MAX_CARRY_KG:
        return false
    for item_id in offer:
        if int(market.get(item_id, 0)) > MAX_STACK - int(offer[item_id]):
            return false
    if not world.toolmaking.can_move(cargo_id, offer) or not world.toolmaking.can_move(depot_id, payment):
        return false
    for item_id in offer:
        carried[item_id] = int(carried.get(item_id, 0)) - int(offer[item_id])
        if int(carried[item_id]) == 0:
            carried.erase(item_id)
        market[item_id] = int(market.get(item_id, 0)) + int(offer[item_id])
    for item_id in payment:
        market[item_id] = int(market[item_id]) - int(payment[item_id])
        if int(market[item_id]) == 0:
            market.erase(item_id)
        carried[item_id] = int(carried.get(item_id, 0)) + int(payment[item_id])
    world.toolmaking.move_instances(cargo_id, depot_id, offer)
    world.toolmaking.move_instances(depot_id, cargo_id, payment)
    _log(world, "barter_export", cargo_id, depot_id, offer)
    _log(world, "barter_import", depot_id, cargo_id, payment)
    return true

# D3: finite wood, stone, flint and plant-fibre sources; shared biome depletion.
# Both the terrain precondition and the citizen's proximity are mandatory.
func extract(world: RefCounted, citizen_id: int, item_id: String, source: Vector2i, quantity: int = 1) -> bool:
    if item_id not in ["wood", "stone", "flint", "plant_fibre", "clay", "sand", "reeds", "copper_ore", "tin_ore"] or quantity <= 0 or quantity > 4:
        return false
    var person := _person(world, citizen_id)
    if person.is_empty() or int(person.get("hp", 0)) <= 0:
        return false
    if item_id in ["copper_ore","tin_ore"] and not world.construction.mining_access(world,person,source): return false
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
    world.settlement_planner.invalidate(source)
    world.construction.depleted[cell_key] = int(world.construction.depleted.get(cell_key, 0)) + quantity
    minted[item_id] = int(minted.get(item_id, 0)) + quantity
    if item_id in ["copper_ore","tin_ore"]:
        world.occupations.grant_capability(world,world.settlements.sid(person),"copper_mining","experiment")
        world.occupations.on_real_work(world,person,"copper_miner",quantity)
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
        if available(holder_id, str(item_id)) < int(units[item_id]):
            return false
    if not world.toolmaking.can_move(holder_id, units):
        return false
    for item_id in units:
        inventory[item_id] = int(inventory[item_id]) - int(units[item_id])
        if int(inventory[item_id]) == 0:
            inventory.erase(item_id)
        consumed[item_id] = int(consumed.get(item_id, 0)) + int(units[item_id])
    world.toolmaking.lose_instances(holder_id, units)
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
    var can_drop: bool = index >= 0 and world.at(int(person["x"]), int(person["y"])) != world.OCEAN
    if can_drop and not balances.has(target) and balances.size() >= MAX_STORES:
        can_drop = false
    if can_drop and not balances.has(target):
        balances[target] = {}
    for item_id in inventory.keys():
        var qty := int(inventory[item_id])
        if can_drop and int(balances[target].get(item_id, 0)) <= MAX_STACK - qty:
            balances[target][item_id] = int(balances[target].get(item_id, 0)) + qty
            world.toolmaking.move_instances(holder_id, target, {item_id: qty})
        else:
            destroyed[item_id] = int(destroyed.get(item_id, 0)) + qty
            world.toolmaking.lose_instances(holder_id, {item_id: qty})
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
        world.toolmaking.lose_instances(holder_id, contents)
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

# A real knapping experiment consumes flint and a sacrificial hammer stone.
# Only a physically built tool area can establish the stone-working capability.
func prototype_knapping(world: RefCounted, actor_id: int, from_cargo: bool = false) -> bool:
    var person := _person(world, actor_id)
    if person.is_empty() or int(person.get("hp", 0)) <= 0:
        return false
    var nation: int = world.settlements.sid(person)
    var holder := "citizen:"+str(actor_id) if from_cargo else "settlement:"+str(nation)
    var depot: Vector2i = world.toolmaking.station(world,nation) if from_cargo else world.settlements.center(world,nation)
    if depot.x < 0 or _distance(depot, Vector2i(int(person["x"]), int(person["y"]))) > 1 or \
            world.calendar.age_years(int(person.get("birth_tick", world.tick)), world.tick) < 13 or \
            not world.occupations.facility_present(world, nation, "tool_area") or \
            world.occupations.has_capability(world, nation, "stone_working"):
        return false
    var store: Dictionary = balances.get(holder,{})
    if available(holder, "flint") < 1 or available(holder, "stone") < 1 or \
            int(store.get("knapped_flint", 0)) >= MAX_STACK:
        return false
    if not world.occupations.grant_capability(world, nation, "stone_working", "experiment"):
        return false
    # Conditions above ensure this is an all-or-nothing physical transform.
    for ingredient in ["flint", "stone"]:
        store[ingredient] = int(store[ingredient]) - 1
        if int(store[ingredient]) == 0 and (from_cargo or ingredient != "stone"):
            store.erase(ingredient)
        consumed[ingredient] = int(consumed.get(ingredient, 0)) + 1
    store["knapped_flint"] = int(store.get("knapped_flint", 0)) + 1
    minted["knapped_flint"] = int(minted.get("knapped_flint", 0)) + 1
    _log(world, "experiment:knapping", holder,
        holder, {"flint": 1, "stone": 1, "knapped_flint": 1})
    world.occupations.on_real_work(world, person, "stone_toolmaker")
    return true

# D3: atomic physical workshop craft. The catalogue validates age, local
# knowledge, real career and materials; an actual citizen spends work time.
func craft_at(world: RefCounted, item_id: String, actor_id: int, from_cargo: bool = false) -> bool:
    if item_id not in ["knapped_flint", "cordage", "hammerstone",
            "flint_knife", "stone_axe", "stone_pick"]:
        return false
    var person := _person(world, actor_id)
    if person.is_empty() or int(person.get("hp", 0)) <= 0:
        return false
    var nation: int = world.settlements.sid(person)
    var holder := "citizen:"+str(actor_id) if from_cargo else "settlement:"+str(nation)
    var depot: Vector2i = world.toolmaking.station(world,nation) if from_cargo else world.settlements.center(world,nation)
    if depot.x < 0 or _distance(depot, Vector2i(int(person["x"]), int(person["y"]))) > 1 or \
            not world.occupations.enabled(world, nation, "stone_toolmaker"):
        return false
    var record: Dictionary = catalogue.item(item_id)
    var recipe: Variant = record.get("recipe", null)
    if not recipe is Dictionary:
        return false
    var store: Dictionary = balances.get(holder,{})
    var context: Dictionary = catalogue.context_for_citizen(world, person, item_id)
    var spendable := store.duplicate()
    for ingredient in spendable:
        spendable[ingredient] = available(holder, str(ingredient))
    if not catalogue.can_craft(item_id, spendable, context):
        return false
    if item_id == "knapped_flint":
        var ability_context: Dictionary = catalogue.context_for_citizen(world, person, "knapping", true)
        if not catalogue.can_use_ability("knapping", store, ability_context) or \
                not world.toolmaking.workshop_tool_ready(nation, "hammerstone",holder):
            return false
    var qty := int(recipe["output"])
    if qty <= 0 or qty > 5 or int(store.get(item_id, 0)) > MAX_STACK - qty:
        return false
    if str(record.get("category", "")) == "tool" and not world.toolmaking.can_register(item_id, qty):
        return false
    # All checks precede mutation; preserve compatibility aliases for zeros.
    for ingredient in recipe["inputs"]:
        var amount: int = int(recipe["inputs"][ingredient])
        store[ingredient] = int(store[ingredient]) - amount
        if int(store[ingredient]) == 0 and (from_cargo or ingredient not in ["wood", "stone"]):
            store.erase(ingredient)
        consumed[ingredient] = int(consumed.get(ingredient, 0)) + amount
    store[item_id] = int(store.get(item_id, 0)) + qty
    minted[item_id] = int(minted.get(item_id, 0)) + qty
    world.toolmaking.on_crafted(world, holder,
        item_id, qty, actor_id)
    if item_id == "knapped_flint":
        world.toolmaking.wear_workshop(world, nation, "hammerstone",holder)
    _log(world, "craft:" + item_id, holder,
        holder, {item_id: qty})
    world.occupations.on_real_work(world, person, "stone_toolmaker")
    return true

# An atomic recipe transformation at one real completed building. The caller
# supplies no inventory or capability flags. This never handles tool instances.
func craft_in_building(world: RefCounted, actor_id: int, house: Dictionary, process: Dictionary) -> bool:
    var person := _person(world,actor_id)
    if person.is_empty() or world.construction.building_by_id(int(house.get("id",0))) != house:
        return false
    if not world.construction.operations.can_run(world,person,house,process): return false
    var item := str(process.get("item",""))
    var record: Dictionary = catalogue.item(item)
    if str(record.get("category","")) == "tool" and not world.toolmaking.can_register(item,int(record["recipe"]["output"])): return false
    var row: Dictionary = world.construction.catalogue.definition(str(house["definition_id"]))
    var entry: Array = row.get("entrances",[[0,0]])[0]
    var at := Vector2i(int(house["x"])+int(entry[0]),int(house["y"])+int(entry[1]))
    if _distance(Vector2i(int(person["x"]),int(person["y"])),at)>1: return false
    var holder := "citizen:"+str(actor_id)
    var store: Dictionary = balances.get(holder,{})
    var spendable := store.duplicate()
    for ingredient in spendable: spendable[ingredient] = available(holder,str(ingredient))
    var qualified := catalogue.can_craft(item,spendable,catalogue.context_for_citizen(world,person,item))
    if not qualified and not world.construction.operations.prototype_allowed(world,person,process): return false
    if not catalogue._has_materials(spendable,record["recipe"]["inputs"]): return false
    var recipe: Dictionary = record["recipe"]
    var result := store.duplicate()
    for ingredient in recipe["inputs"]: result[ingredient] = int(result[ingredient])-int(recipe["inputs"][ingredient])
    result[item] = int(result.get(item,0))+int(recipe["output"])
    if int(result[item]) > MAX_STACK or _weight(result)>MAX_CARRY_KG: return false
    for ingredient in recipe["inputs"]:
        var amount := int(recipe["inputs"][ingredient])
        store[ingredient] = int(store[ingredient])-amount
        if int(store[ingredient]) == 0: store.erase(ingredient)
        consumed[ingredient] = int(consumed.get(ingredient,0))+amount
    store[item] = int(store.get(item,0))+int(recipe["output"])
    minted[item] = int(minted.get(item,0))+int(recipe["output"])
    world.toolmaking.on_crafted(world,holder,item,int(recipe["output"]),actor_id)
    var discovery := str(process.get("prototype",{}).get("discover",process.get("discover_on_completion","")))
    if discovery!="" and not world.occupations.has_capability(world,world.settlements.sid(person),discovery):
        world.occupations.grant_capability(world,world.settlements.sid(person),discovery,"experiment")
        world.occupations.append_event(world,person,"facility_discovery",{"technology":discovery,"building_id":int(house["id"]),"inputs":recipe["inputs"].duplicate(true)})
    _log(world,"building_process",holder,holder,{item:int(recipe["output"])})
    world.occupations.on_real_work(world,person,str(recipe["skill"]))
    house["operating_cycles"] = int(house.get("operating_cycles",0))+1
    house["last_operation_tick"] = world.tick
    return true

# Explicit one-way transfer between the existing edible and material ledgers.
# Food grain is spent as an ingredient; it cannot remain edible or become seed
# twice. Allocation requires a present operator, never a renderer/clock.
func allocate_food_grain(world: RefCounted, actor_id: int, requested: int) -> bool:
    var person := _person(world,actor_id)
    if person.is_empty() or int(person["hp"])<=0 or requested<=0 or requested>20: return false
    var sid: int = world.settlements.sid(person)
    if _distance(Vector2i(int(person["x"]),int(person["y"])),world.settlements.center(world,sid))>1: return false
    var holder := "settlement:"+str(sid)
    var need := maxi(0,requested-available(holder,"grain"))
    if need==0: return true
    var food: Dictionary = world.food.store(sid)
    if int(food.get("grain",0))<need: return false
    var store: Dictionary = balances.get(holder,{})
    if int(store.get("grain",0))>MAX_STACK-need: return false
    food["grain"] -= need
    world.food.consumed["grain"] += need
    store["grain"] = int(store.get("grain",0))+need
    minted["grain"] = int(minted.get("grain",0))+need
    _log(world,"food_grain_allocation",holder,holder,{"grain":need})
    return true

func snapshot() -> Dictionary:
    return {"version": VERSION, "balances": balances.duplicate(true),
        "minted": minted.duplicate(true), "consumed": consumed.duplicate(true),
        "destroyed": destroyed.duplicate(true), "events": events.duplicate(true),
        "reservations": reservations.duplicate(true)}

func _valid_counts(source: Variant) -> bool:
    if not source is Dictionary or source.size() > catalogue.items.size():
        return false
    for item_id in source:
        if not item_id is String or not catalogue.items.has(item_id):
            return false
        if not _integer_count(source[item_id]) or int(source[item_id]) < 0 or int(source[item_id]) > MAX_STACK * MAX_STORES:
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
            if not _integer_count(contents[item_id]) or qty < 0 or qty > MAX_STACK or (qty == 0 and not (holder_id.begins_with("settlement:") and item_id in ["wood", "stone"])):
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
    reservations = raw.get("reservations", {}).duplicate(true)
    reserved_totals.clear()
    for key in reservations:
        if not str(key).begins_with("site:"):
            return false
        var claim: Variant = reservations[key]
        if not claim is Dictionary or not _valid_counts(claim.get("units")) or \
                world.construction.site_by_id(int(str(key).trim_prefix("site:"))).is_empty():
            return false
        var holder := str(claim.get("holder", ""))
        if not holder.begins_with("settlement:") or _holder(world, holder).is_empty():
            return false
        if not reserved_totals.has(holder):
            reserved_totals[holder] = {}
        for item in claim["units"]:
            reserved_totals[holder][item] = int(reserved_totals[holder].get(item, 0)) + int(claim["units"][item])
            if int(reserved_totals[holder][item]) > held(holder, str(item)):
                return false
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

# Reservations protect shared physical stock from construction, crafting and UI withdrawals.
func available(holder: String, item: String) -> int:
    return held(holder, item) - int(reserved_totals.get(holder, {}).get(item, 0))

func reserve(key: String, holder: String, units: Dictionary) -> bool:
    if reservations.has(key) or not holder.begins_with("settlement:") or not _bundle_valid(units):
        return false
    for item in units:
        if available(holder, str(item)) < int(units[item]):
            return false
    reservations[key] = {"holder": holder, "units": units.duplicate(true)}
    if not reserved_totals.has(holder):
        reserved_totals[holder] = {}
    for item in units:
        reserved_totals[holder][item] = int(reserved_totals[holder].get(item, 0)) + int(units[item])
    return true

func release_reservation(key: String) -> void:
    var claim: Dictionary = reservations.get(key, {})
    if claim.is_empty():
        return
    var holder := str(claim["holder"])
    for item in claim["units"]:
        reserved_totals[holder][item] -= int(claim["units"][item])
    reservations.erase(key)

# Closing a site leaves unused goods at its actual location, never in a remote depot.
func close_site(world: RefCounted, site: Dictionary, salvage: Dictionary) -> bool:
    var holder := "site:" + str(site["id"])
    var ground := "ground:" + str(world.index_of(int(site["x"]), int(site["y"])))
    var loose: Dictionary = balances.get(holder, {})
    var combined := loose.duplicate()
    for item in salvage:
        if int(salvage[item]) < 0 or int(salvage[item]) > int(consumed.get(item,0)):
            return false
        combined[item] = int(combined.get(item,0)) + int(salvage[item])
    if not combined.is_empty() and not balances.has(ground) and balances.size() >= MAX_STORES:
        return false
    for item in combined:
        if int(combined[item]) + held(ground,str(item)) > MAX_STACK:
            return false
    # All preconditions precede mutation, including salvage capacity checks.
    release_reservation(holder)
    if not combined.is_empty() and not balances.has(ground):
        balances[ground] = {}
    for item in combined:
        balances[ground][item] = int(balances[ground].get(item,0)) + int(combined[item])
    for item in salvage:
        consumed[item] = int(consumed[item]) - int(salvage[item])
    balances.erase(holder)
    _log(world,"site_recovery",holder,ground,combined)
    return true

# Godot JSON decodes integral numbers as floats; reject fractional/nonfinite input.
func _integer_count(value: Variant) -> bool:
    return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value) and value == floor(value))

func close_storage(world: RefCounted, house: Dictionary) -> void:
    var holder := "store:"+str(house["id"])
    var goods: Dictionary = balances.get(holder,{})
    if goods.is_empty(): return
    var index: int = world.index_of(int(house["x"]),int(house["y"]))
    var ground := "ground:"+str(index)
    if not balances.has(ground): balances[ground] = {}
    for good in goods:
        var count := int(goods[good])
        balances[ground][good] = int(balances[ground].get(good,0))+count
        world.toolmaking.move_instances(holder,ground,{str(good):count})
    _log(world,"storage_collapse",holder,ground,goods)
    balances.erase(holder)
