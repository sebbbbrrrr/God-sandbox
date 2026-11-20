extends RefCounted
# D3: actual tool yard, experimental discovery, autonomous manufacture,
# equipped single-instance tools, wear, recovery and material-paid repair.
# All material movement goes through PhysicalInventory; no timer production.
const Nav = preload("res://scripts/ai/navigation.gd")
const Calendar = preload("res://scripts/ai/sim_calendar.gd")
const VERSION := 1
const MAX_INSTANCES := 500
const MAX_JOBS := 20
const MAX_HISTORY := 10
const WORKSITE_WOOD := 2
const WORKSITE_STONE := 1
const GOALS := ["hammerstone", "stone_axe", "stone_pick", "flint_knife"]
const REPAIR_INPUTS := {"stone_axe": "stone", "stone_pick": "stone",
    "flint_knife": "flint", "hammerstone": "stone"}

var jobs: Dictionary = {} # citizen id -> persistent physical task
var instances: Dictionary = {} # serial id -> {item_id, holder, condition...}
var equipped: Dictionary = {} # citizen id -> serial id; never extra units
var next_serial := 1
var crafted_total := 0
var repaired_total := 0
var experiments_total := 0

func _person(world: RefCounted, id: int) -> Dictionary:
    return world.inventory._person(world, id)

func _living_adolescent(world: RefCounted, person: Dictionary) -> bool:
    return int(person.get("hp", 0)) > 0 and \
        world.calendar.age_years(int(person.get("birth_tick", world.tick)), world.tick) >= 13

func _site(world: RefCounted, nation: int) -> bool:
    return world.occupations.facility_present(world, nation, "tool_area")

func _knowledge(world: RefCounted, nation: int) -> bool:
    return world.occupations.has_capability(world, nation, "stone_working")

func _has_worker(nation: int) -> bool:
    for job in jobs.values():
        if int(job.get("nation", -1)) == nation:
            return true
    return false

func _total_in_nation(world: RefCounted, nation: int, item_id: String) -> int:
    var amount: int = world.inventory.held("settlement:" + str(nation), item_id)
    for serial in instances:
        var instance: Dictionary = instances[serial]
        if str(instance["item_id"]) != item_id:
            continue
        var holder := str(instance["holder"])
        if not holder.begins_with("citizen:"):
            continue
        var person := _person(world, int(holder.trim_prefix("citizen:")))
        if not person.is_empty() and int(person["nation"]) == nation:
            amount += 1
    return amount

func can_register(item_id: String, quantity: int) -> bool:
    return quantity > 0 and quantity <= 5 and instances.size() + quantity <= MAX_INSTANCES

func _managed(item_id: String) -> bool:
    return item_id in REPAIR_INPUTS

func _matching_serials(holder: String, item_id: String) -> Array[String]:
    var ids: Array[String] = []
    for serial in instances:
        if str(instances[serial]["holder"]) == holder and \
                str(instances[serial]["item_id"]) == item_id:
            ids.append(str(serial))
    # Prefer intact tools so workers never check out broken inventory first.
    ids.sort_custom(func(a: String, b: String) -> bool:
        if int(instances[a]["condition"]) != int(instances[b]["condition"]):
            return int(instances[a]["condition"]) > int(instances[b]["condition"])
        return int(a) < int(b))
    return ids

func can_move(holder: String, units: Dictionary) -> bool:
    for item_id in units:
        if _managed(str(item_id)) and _matching_serials(holder, str(item_id)).size() < int(units[item_id]):
            return false
    return true

func on_crafted(world: RefCounted, holder: String, item_id: String, quantity: int, artisan: int) -> void:
    if not _managed(item_id):
        return
    var definition: Dictionary = world.inventory.catalogue.item(item_id)
    var maximum := maxi(1, int(definition["physical"]["durability"]))
    for i in range(quantity):
        var serial := str(next_serial)
        next_serial += 1
        var instance: Dictionary = world.inventory.catalogue.new_instance(
            item_id, int(serial), artisan, 50 + mini(30, world.occupations.skill_tier(
                _person(world, artisan), "stone_toolmaker") * 5))
        instance["condition"] = maximum
        instance["max_condition"] = maximum
        instance["holder"] = holder
        instance["crafted_tick"] = int(world.tick)
        instance["origin_settlement"] = str(_person(world, artisan).get("nation", -1))
        instances[serial] = instance

func _unassign(serial: String) -> void:
    for id in equipped.keys():
        if str(equipped[id]) == serial:
            equipped.erase(id)

func move_instances(source: String, target: String, units: Dictionary) -> void:
    for item_id in units:
        if not _managed(str(item_id)):
            continue
        var ids := _matching_serials(source, str(item_id))
        for i in range(mini(ids.size(), int(units[item_id]))):
            var serial := ids[i]
            var instance: Dictionary = instances[serial]
            _unassign(serial)
            instance["holder"] = target
            if target.begins_with("citizen:"):
                instance["owner_id"] = int(target.trim_prefix("citizen:"))

func lose_instances(holder: String, units: Dictionary) -> void:
    for item_id in units:
        if not _managed(str(item_id)):
            continue
        var ids := _matching_serials(holder, str(item_id))
        for i in range(mini(ids.size(), int(units[item_id]))):
            _unassign(ids[i])
            instances.erase(ids[i])

func tool_for(world: RefCounted, person: Dictionary, material: String) -> String:
    var id := str(person["id"])
    var serial := str(equipped.get(id, ""))
    if serial == "" or not instances.has(serial):
        return ""
    var instance: Dictionary = instances[serial]
    var expected := "stone_axe" if material == "wood" else "stone_pick" if material == "stone" else ""
    if expected == "" or str(instance["item_id"]) != expected or int(instance["condition"]) <= 0 or \
            str(instance["holder"]) != "citizen:" + id:
        return ""
    var ability := "woodcutting" if material == "wood" else "quarrying"
    var inventory: Dictionary = world.inventory.citizen_inventory(int(person["id"]))
    var context: Dictionary = world.inventory.catalogue.context_for_citizen(world, person, ability, true)
    return serial if world.inventory.catalogue.can_use_ability(ability, inventory, context) else ""

func wear(world: RefCounted, person: Dictionary, material: String) -> void:
    var serial := tool_for(world, person, material)
    if serial == "":
        return
    var instance: Dictionary = instances[serial]
    instance["condition"] = maxi(0, int(instance["condition"]) - 12)
    var history: Array = instance["history"]
    history.append({"tick": int(world.tick), "work": material, "condition": int(instance["condition"])})
    if history.size() > MAX_HISTORY:
        history.pop_front()
    if int(instance["condition"]) <= 0:
        _unassign(serial)

func _put_away(world: RefCounted, person: Dictionary) -> void:
    var pid := str(person["id"])
    var depot: Vector2i = world.capitals[int(person["nation"])]
    if Nav.manhattan(Vector2i(int(person["x"]), int(person["y"])), depot) > 1:
        return
    for serial in _matching_serials("citizen:" + pid, "stone_axe") + \
            _matching_serials("citizen:" + pid, "stone_pick"):
        var instance: Dictionary = instances[serial]
        if int(instance["condition"]) <= 40:
            world.inventory.transfer(world, "citizen:" + pid,
                "settlement:" + str(person["nation"]), {str(instance["item_id"]): 1}, int(person["id"]))

# Existing resource gatherers only borrow a durable tool at the real depot.
func try_equip(world: RefCounted, person: Dictionary, material: String) -> void:
    if material not in ["wood", "stone"] or not _living_adolescent(world, person):
        return
    var pid := str(person["id"])
    var held := "citizen:" + pid
    var depot: Vector2i = world.capitals[int(person["nation"])]
    if Nav.manhattan(Vector2i(int(person["x"]), int(person["y"])), depot) > 1:
        return
    _put_away(world, person)
    if tool_for(world, person, material) != "":
        return
    var wanted := "stone_axe" if material == "wood" else "stone_pick"
    var depot_id := "settlement:" + str(person["nation"])
    var ids := _matching_serials(depot_id, wanted)
    var viable := ""
    for serial in ids:
        if int(instances[serial]["condition"]) > 40:
            viable = serial
            break
    if viable == "":
        return
    if world.inventory.transfer(world, depot_id, held, {wanted: 1}, int(person["id"])):
        var moved_ids := _matching_serials(held, wanted)
        if viable in moved_ids:
            equipped[pid] = viable
        elif not moved_ids.is_empty():
            equipped[pid] = moved_ids[0]

func _begin(world: RefCounted, person: Dictionary, mind: Dictionary, kind: String,
        extra: Dictionary = {}) -> bool:
    if jobs.size() >= MAX_JOBS:
        return false
    var record := {"kind": kind, "nation": int(person["nation"]),
        "phase": "depot", "remaining": 2}
    for key in extra:
        record[key] = extra[key]
    jobs[str(person["id"])] = record
    mind["route"] = []
    mind["next_path_tick"] = int(world.tick)
    return _do_job(world, person, mind)

func _walk(world: RefCounted, person: Dictionary, mind: Dictionary, target: Vector2i) -> bool:
    var origin := Vector2i(int(person["x"]), int(person["y"]))
    if Nav.manhattan(origin, target) <= 0:
        return true
    var next: Vector2i = Nav.next_step(world, person, mind, target)
    if next != origin:
        person["x"] = next.x
        person["y"] = next.y
        world.ai_context.moved(person, origin)
    return next == target

func _end(person: Dictionary, mind: Dictionary) -> void:
    jobs.erase(str(person["id"]))
    mind["route"] = []

func _gather(world: RefCounted, person: Dictionary, mind: Dictionary, material: String) -> bool:
    var found: Dictionary = world.construction.source_for(world, person, material)
    if found.is_empty():
        return false
    return _begin(world, person, mind, "gather", {
        "phase": "source", "material": material, "source": found["source"],
        "target": found["target"], "amount": 0})

func _need(world: RefCounted, nation: int, recipe_item: String, depth: int = 0) -> String:
    # Returns the first unfinished dependency, or the requested craft itself.
    # All dependencies are consumed from the same physically located depot.
    if depth > 5:
        return ""
    var definition: Dictionary = world.inventory.catalogue.item(recipe_item)
    var recipe: Variant = definition.get("recipe", null)
    if not recipe is Dictionary:
        return ""
    var stores: Dictionary = world.inventory.stockpile(nation)
    var inputs: Dictionary = recipe["inputs"]
    for ingredient in inputs:
        if int(stores.get(ingredient, 0)) >= int(inputs[ingredient]):
            continue
        var row: Dictionary = world.inventory.catalogue.item(str(ingredient))
        if str(row.get("acquisition", "")) == "gather":
            return str(ingredient)
        if row.get("recipe", null) is Dictionary:
            return _need(world, nation, str(ingredient), depth + 1)
        return ""
    return recipe_item

func _select(world: RefCounted, person: Dictionary, mind: Dictionary) -> bool:
    var nation := int(person["nation"])
    var stores: Dictionary = world.inventory.stockpile(nation)
    if not _site(world, nation):
        for material in ["wood", "stone"]:
            var required := WORKSITE_WOOD if material == "wood" else WORKSITE_STONE
            if int(stores.get(material, 0)) < required:
                return _gather(world, person, mind, material)
        return _begin(world, person, mind, "build", {"remaining": 4})
    if not _knowledge(world, nation):
        for material in ["flint", "stone"]:
            if int(stores.get(material, 0)) < 1:
                return _gather(world, person, mind, material)
        return _begin(world, person, mind, "experiment", {"remaining": 3})
    # Repair damaged warehouse tools rather than constantly replacing them.
    for serial in instances:
        var row: Dictionary = instances[serial]
        if str(row["holder"]) != "settlement:" + str(nation) or int(row["condition"]) > 40:
            continue
        var material: String = str(REPAIR_INPUTS.get(str(row["item_id"]), "stone"))
        if int(stores.get(material, 0)) <= 0:
            return _gather(world, person, mind, material)
        return _begin(world, person, mind, "repair", {"serial": serial, "remaining": 3})
    for product in GOALS:
        if _total_in_nation(world, nation, product) > 0:
            continue
        var required := _need(world, nation, product)
        if required == "":
            continue
        if world.inventory.catalogue.item(required).get("acquisition", "") == "gather":
            return _gather(world, person, mind, required)
        return _begin(world, person, mind, "craft",
            {"item_id": required, "remaining": 3})
    return false

# Once a citizen commits to a job they cannot duplicate it remotely.
func _do_job(world: RefCounted, person: Dictionary, mind: Dictionary) -> bool:
    var id := str(person["id"])
    var task: Dictionary = jobs.get(id, {})
    if task.is_empty():
        return false
    var nation := int(task["nation"])
    var depot: Vector2i = world.capitals[nation]
    if not _living_adolescent(world, person) or int(person["nation"]) != nation or \
            depot.x < 0 or not world.is_walkable(depot.x, depot.y):
        _end(person, mind)
        return false
    if str(task["kind"]) == "gather":
        if str(task["phase"]) == "source":
            var source := Vector2i(int(task["source"][0]), int(task["source"][1]))
            var target := Vector2i(int(task["target"][0]), int(task["target"][1]))
            if world.construction.left_at(world, source.x, source.y, str(task["material"])) <= 0 or \
                    not world.is_walkable(target.x, target.y):
                _end(person, mind)
                return false
            if _walk(world, person, mind, target) and Nav.manhattan(
                    Vector2i(int(person["x"]), int(person["y"])), source) <= 1:
                if world.inventory.extract(world, int(person["id"]), str(task["material"]), source):
                    task["amount"] = 1
                    task["phase"] = "depot"
                    mind["route"] = []
            return true
        if _walk(world, person, mind, depot):
            if world.inventory.transfer(world, "citizen:" + id,
                    "settlement:" + str(nation), {str(task["material"]): int(task["amount"])}, int(person["id"])):
                _end(person, mind)
        return true
    if not _walk(world, person, mind, depot):
        return true
    if str(task["kind"]) == "build" and str(task["phase"]) == "depot":
        if not world.inventory.transfer(world, "settlement:" + str(nation),
                "citizen:" + id, {"wood": WORKSITE_WOOD, "stone": WORKSITE_STONE}, int(person["id"])):
            _end(person, mind)
            return false
        task["phase"] = "labour"
    task["remaining"] = int(task["remaining"]) - 1
    if int(task["remaining"]) > 0:
        return true
    match str(task["kind"]):
        "build":
            if not _site(world, nation) and world.inventory.consume(world,
                    "citizen:" + id, {"wood": WORKSITE_WOOD, "stone": WORKSITE_STONE},
                    int(person["id"]), "tool_area"):
                var site: Vector2i = world.capitals[nation]
                world.construction.houses.append({"id": world.construction.next_building_id,
                    "type": "tool_area", "capacity": 0, "nation": nation,
                    "x": site.x, "y": site.y, "built_tick": int(world.tick)})
                world.construction.next_building_id += 1
                world.set_terrain_cell(site.x, site.y, world.TOWN)
                world.occupations.on_real_work(world, person, "shelter_builder")
        "experiment":
            if _site(world, nation) and not _knowledge(world, nation) and \
                    world.inventory.prototype_knapping(world, int(person["id"])):
                experiments_total += 1
        "craft":
            if _site(world, nation) and _knowledge(world, nation) and \
                    world.inventory.craft_at(world, str(task["item_id"]), int(person["id"])):
                crafted_total += 1
        "repair":
            if _site(world, nation) and _knowledge(world, nation) and \
                    repair(world, int(person["id"]), str(task["serial"])):
                repaired_total += 1
    _end(person, mind)
    return true

# Remove jobs for deceased/archived workers so another citizen can finish work.
# Cargo stays in the physical ledger and is dropped by D2 death handling.
func prune(world: RefCounted) -> void:
    for id in jobs.keys():
        var person := _person(world, int(id))
        if person.is_empty() or int(person.get("hp", 0)) <= 0:
            jobs.erase(id)

func work_step(world: RefCounted, person: Dictionary, mind: Dictionary) -> bool:
    if not _living_adolescent(world, person):
        return false
    var id := str(person["id"])
    if jobs.has(id):
        return _do_job(world, person, mind)
    # Give the independent housing/food scheduler ownership of existing jobs.
    if world.construction.jobs.has(id) or world.food.jobs.has(id):
        return false
    if int(person["id"]) % 11 != 0 and str(world.occupations.record_for(person).get("preference", "")) != "stone_toolmaker":
        return false
    if _has_worker(int(person["nation"])):
        return false
    return _select(world, person, mind)

# Knapping at the yard physically wears one local hammerstone.
func workshop_tool_ready(nation: int, item_id: String) -> bool:
    for serial in _matching_serials("settlement:" + str(nation), item_id):
        if int(instances[serial]["condition"]) > 0:
            return true
    return false

func wear_workshop(world: RefCounted, nation: int, item_id: String) -> void:
    var ids := _matching_serials("settlement:" + str(nation), item_id)
    if ids.is_empty():
        return
    var instance: Dictionary = instances[ids[0]]
    instance["condition"] = maxi(0, int(instance["condition"]) - 6)
    instance["history"].append({"tick": int(world.tick), "work": "knapping",
        "condition": int(instance["condition"])})
    if instance["history"].size() > MAX_HISTORY:
        instance["history"].pop_front()

func repair(world: RefCounted, artisan_id: int, serial: String) -> bool:
    if not instances.has(serial):
        return false
    var person := _person(world, artisan_id)
    if person.is_empty() or not _living_adolescent(world, person):
        return false
    var nation := int(person["nation"])
    var station: Vector2i = world.capitals[nation]
    if Nav.manhattan(Vector2i(int(person["x"]), int(person["y"])), station) > 1 or \
            not _site(world, nation) or not _knowledge(world, nation) or \
            not world.occupations.enabled(world, nation, "stone_toolmaker"):
        return false
    var entry: Dictionary = instances[serial]
    if str(entry["holder"]) != "settlement:" + str(nation) or \
            int(entry["condition"]) >= int(entry["max_condition"]):
        return false
    var material: String = str(REPAIR_INPUTS.get(str(entry["item_id"]), "stone"))
    if not world.inventory.consume(world, "settlement:" + str(nation),
            {material: 1}, artisan_id, "tool_repair"):
        return false
    entry["condition"] = mini(int(entry["max_condition"]), int(entry["condition"]) + 60)
    entry["history"].append({"tick": int(world.tick), "work": "repair",
        "condition": int(entry["condition"])})
    if entry["history"].size() > MAX_HISTORY:
        entry["history"].pop_front()
    world.occupations.on_real_work(world, person, "stone_toolmaker")
    return true

func snapshot() -> Dictionary:
    return {"version": VERSION, "jobs": jobs.duplicate(true),
        "instances": instances.duplicate(true), "equipped": equipped.duplicate(true),
        "next_serial": next_serial, "crafted_total": crafted_total,
        "repaired_total": repaired_total, "experiments_total": experiments_total}

func load_state(world: RefCounted, raw: Variant) -> bool:
    if raw == null:
        return true # D1 and D2 save compatibility
    if not raw is Dictionary or int(raw.get("version", -1)) != VERSION:
        return false
    if not raw.get("jobs") is Dictionary or raw["jobs"].size() > MAX_JOBS or \
            not raw.get("instances") is Dictionary or raw["instances"].size() > MAX_INSTANCES or \
            not raw.get("equipped") is Dictionary:
        return false
    var loaded_instances: Dictionary = {}
    var max_serial := 0
    for serial in raw["instances"]:
        if not str(serial).is_valid_int() or int(serial) <= 0:
            return false
        max_serial = maxi(max_serial, int(serial))
        var row: Variant = raw["instances"][serial]
        if not row is Dictionary or not _managed(str(row.get("item_id", ""))) or \
                str(row.get("serial", "")) != str(serial):
            return false
        var holder := str(row.get("holder", ""))
        if world.inventory._holder(world, holder).is_empty() or \
                int(row.get("condition", -1)) < 0 or int(row.get("max_condition", 0)) <= 0 or \
                int(row.get("condition", 0)) > int(row.get("max_condition", 0)):
            return false
        loaded_instances[str(serial)] = row.duplicate(true)
    var saved_instances := instances
    instances = loaded_instances
    var linked_counts: Dictionary = {}
    for serial in instances:
        var inst: Dictionary = instances[serial]
        var key := str(inst["holder"]) + "|" + str(inst["item_id"])
        linked_counts[key] = int(linked_counts.get(key, 0)) + 1
    for key in linked_counts:
        var fields := str(key).split("|")
        if int(linked_counts[key]) != world.inventory.held(fields[0], fields[1]):
            instances = saved_instances
            return false
    for holder in world.inventory.balances:
        var store: Dictionary = world.inventory.balances[holder]
        for item_id in REPAIR_INPUTS:
            if _matching_serials(str(holder), item_id).size() != int(store.get(item_id, 0)):
                instances = saved_instances
                return false
    var candidate_equipped: Dictionary = {}
    for id in raw["equipped"]:
        var serial := str(raw["equipped"][id])
        if not instances.has(serial) or \
                str(instances[serial]["holder"]) != "citizen:" + str(id) or \
                int(instances[serial]["condition"]) <= 0 or \
                _person(world, int(id)).is_empty():
            instances = saved_instances
            return false
        candidate_equipped[str(id)] = serial
    var candidate_jobs: Dictionary = {}
    for id in raw["jobs"]:
        var task: Variant = raw["jobs"][id]
        var person := _person(world, int(id))
        if not task is Dictionary or person.is_empty() or int(person["hp"]) <= 0 or \
                str(task.get("kind", "")) not in ["gather", "build", "experiment", "craft", "repair"] or \
                int(task.get("nation", -1)) != int(person["nation"]):
            instances = saved_instances
            return false
        candidate_jobs[str(id)] = task.duplicate(true)
    jobs = candidate_jobs
    equipped = candidate_equipped
    next_serial = maxi(max_serial + 1, int(raw.get("next_serial", max_serial + 1)))
    crafted_total = maxi(0, int(raw.get("crafted_total", 0)))
    repaired_total = maxi(0, int(raw.get("repaired_total", 0)))
    experiments_total = maxi(0, int(raw.get("experiments_total", 0)))
    return true
