extends RefCounted
const Site = preload("res://scripts/construction/site_state.gd")
var cursor = 0
var pending: Dictionary = {}

func migrate(house: Dictionary) -> void:
    if house.has("condition"):
        return
    house.merge({"definition_id": "primitive_shelter", "orientation": 0, "original_age": 1,
        "condition": 100, "max_health": 100, "quality": 100, "abandoned": false,
        "function": "shelter", "original_nation": int(house["nation"]), "builder_id": 0,
        "materials": {}, "history": [], "last_condition_tick": int(house.get("built_tick", 0)),
        "original_terrain": [2]}, false)
    if str(house.get("type", "")) == "tool_area":
        house["function"] = "tool_area"

func complete(engine: RefCounted, world: RefCounted, person: Dictionary, site: Dictionary, row: Dictionary) -> void:
    var house = {"id": int(site["id"]), "nation": int(site["nation"]), "original_nation": int(site["nation"]),
        "settlement_id": world.settlements.sid(site), "builder_id": int(person["id"]), "definition_id": row["id"], "type": "home" if row["function"] == "shelter" else row["function"], "function": row["function"],
        "x": int(site["x"]), "y": int(site["y"]), "orientation": int(site["orientation"]),
        "capacity": int(row["occupancy_capacity"]), "built_tick": int(world.tick), "original_age": engine.catalogue.local_age(world, world.settlements.sid(site)),
        "materials": site["consumed"].duplicate(true), "quality": int(site["quality"]),
        "condition": int(row["structural"]["max_health"]), "max_health": int(row["structural"]["max_health"]),
        "abandoned": false, "history": site["history"].duplicate(true), "last_condition_tick": int(world.tick),
        "original_terrain": site["original_terrain"].duplicate()}
    if site.has("previous_building"):
        var previous: Dictionary = site["previous_building"]
        for field in ["built_tick", "original_age", "original_nation", "builder_id"]:
            house[field] = previous[field]
        house["history"] = previous["history"].duplicate(true)
        for item in previous["materials"]:
            house["materials"][item] = int(house["materials"].get(item, 0)) + int(previous["materials"][item])
        Site.history(house, world.tick, str(site["transition"]) + "_completed", {"from": previous["definition_id"], "to": row["id"]})
    Site.history(house, world.tick, "completed")
    world.inventory.release_reservation("site:" + str(site["id"]))
    world.inventory.balances.erase("site:" + str(site["id"]))
    engine.remove_site(int(site["id"]))
    engine.houses.append(house)
    engine.buildings_by_id[int(house["id"])] = house
    engine.placement.claim(row, house)
    engine.indexed_houses = engine.houses.size()
    for cell in engine.placement.footprint(row, Vector2i(int(house["x"]), int(house["y"])), int(house["orientation"])):
        world.set_terrain_cell(cell.x, cell.y, world.TOWN)
    world.regional_economy.on_building_changed(world, Vector2i(int(house["x"]),int(house["y"])))
    world.households.dirty = true

func damage(engine: RefCounted, world: RefCounted, id: int, amount: int, cause: String) -> bool:
    var house: Dictionary = engine.building_by_id(id)
    if house.is_empty() or amount <= 0:
        return false
    migrate(house)
    house["condition"] = maxi(0, int(house["condition"]) - amount)
    world.terrain_changed.emit(Vector2i(int(house["x"]),int(house["y"])))
    Site.history(house, world.tick, "damage", {"amount": amount, "cause": cause})
    if int(house["condition"]) == 0:
        return remove(engine, world, id, false, "collapse")
    return true

func abandon(engine: RefCounted, world: RefCounted, id: int, value: bool = true) -> bool:
    var house: Dictionary = engine.building_by_id(id)
    if house.is_empty():
        return false
    migrate(house)
    house["abandoned"] = value
    world.terrain_changed.emit(Vector2i(int(house["x"]),int(house["y"])))
    var row: Dictionary = engine.catalogue.definition(str(house["definition_id"]))
    house["capacity"] = 0 if value else int(row.get("occupancy_capacity", 0))
    Site.history(house, world.tick, "abandoned" if value else "reoccupied")
    world.households.dirty = true
    return true

func request_action(engine: RefCounted, world: RefCounted, id: int, kind: String) -> bool:
    var house: Dictionary = engine.building_by_id(id)
    if house.is_empty() or kind not in ["repair", "demolish"] or house.has("pending_action"):
        return false
    migrate(house)
    house["pending_action"] = kind
    pending[id] = true
    Site.history(house, world.tick, kind + "_requested")
    return true

func assign(engine: RefCounted, world: RefCounted, person: Dictionary) -> bool:
    for key in pending:
        var house: Dictionary = engine.building_by_id(int(key))
        if house.is_empty():
            continue
        if world.settlements.sid(house) != world.settlements.sid(person) or not house.has("pending_action") or int(house.get("worker", 0)) > 0:
            continue
        var row: Dictionary = engine.catalogue.definition(str(house.get("definition_id", "primitive_shelter")))
        if not engine.catalogue.worker_eligible(world, person, row):
            continue
        var kind = str(house["pending_action"])
        house["worker"] = int(person["id"])
        pending.erase(int(house["id"]))
        engine.jobs[str(person["id"])] = {"kind": kind, "nation": int(person["nation"]), "settlement_id": world.settlements.sid(person), "building_id": int(house["id"]),
            "phase": "depot" if kind == "repair" else "site", "cargo": {}, "wood": 0, "stone": 0,
            "remaining": int(row[kind if kind == "repair" else "demolition"]["labour"]), "last_active_tick": int(world.tick)}
        return true
    return false

func work(engine: RefCounted, world: RefCounted, person: Dictionary, mind: Dictionary, task: Dictionary) -> bool:
    var house: Dictionary = engine.building_by_id(int(task["building_id"]))
    var id = str(person["id"])
    if house.is_empty():
        task["kind"] = "build"
        task["phase"] = "return"
        return true
    var row: Dictionary = engine.catalogue.definition(str(house["definition_id"]))
    if str(task["phase"]) == "depot":
        if engine.walk(world, person, mind, world.settlements.center(world, world.settlements.sid(person))):
            var materials: Dictionary = row["repair"]["materials"]
            if world.inventory.transfer(world, "settlement:" + str(world.settlements.sid(person)), "citizen:" + id, materials, int(person["id"])):
                task["cargo"] = materials.duplicate(true)
                task["phase"] = "site"
                mind["route"] = []
        return true
    if not engine.walk(world, person, mind, Vector2i(int(house["x"]), int(house["y"]))):
        return true
    task["remaining"] -= 1
    if int(task["remaining"]) > 0:
        return true
    if str(task["kind"]) == "repair":
        if not world.inventory.consume(world, "citizen:" + id, task["cargo"], int(person["id"]), "building_repair"):
            return false
        house["condition"] = mini(int(house["max_health"]), int(house["condition"]) + int(row["repair"]["restore_health"]))
        Site.history(house, world.tick, "repaired", {"worker_id": int(person["id"]), "materials": task["cargo"].duplicate(true)})
        house.erase("pending_action")
        pending.erase(int(house["id"]))
        house.erase("worker")
    else:
        remove(engine, world, int(house["id"]), true, "demolished")
    engine.tasks.finish(engine, id, mind)
    return true

func remove(engine: RefCounted, world: RefCounted, id: int, salvage: bool, reason: String) -> bool:
    var house: Dictionary = engine.building_by_id(id)
    if house.is_empty():
        return false
    migrate(house)
    var row: Dictionary = engine.catalogue.definition(str(house["definition_id"]))
    var recovered = {}
    if salvage:
        for material in house["materials"]:
            var count = floori(float(house["materials"][material]) * float(row["demolition"]["salvage_ratio"]))
            if count > 0:
                recovered[material] = count
    if not world.inventory.close_site(world, house, recovered):
        return false
    Site.history(house, world.tick, reason)
    engine.archived.append(house.duplicate(true))
    if engine.archived.size() > 128:
        engine.archived.pop_front()
    world.inventory.close_storage(world,house)
    pending.erase(id)
    engine.buildings_by_id.erase(id)
    engine.placement.release(id)
    engine.houses.erase(house)
    engine.indexed_houses = engine.houses.size()
    # Release first, then paint; callbacks must not destroy a second time.
    var cells: Array = engine.placement.footprint(row, Vector2i(int(house["x"]), int(house["y"])), int(house["orientation"]))
    for i in range(cells.size()):
        var cell: Vector2i = cells[i]
        if world.at(cell.x, cell.y) == world.TOWN:
            var original = int(house["original_terrain"][i]) if i < house["original_terrain"].size() else world.MEADOW
            world.set_terrain_cell(cell.x, cell.y, original)
    world.households.dirty = true
    engine.revision += 1
    return true

func tick(engine: RefCounted, world: RefCounted) -> void:
    # 16 buildings/tick. Elapsed intervals accumulate exactly, never disappear.
    for i in range(mini(16, engine.houses.size())):
        if engine.houses.is_empty():
            break
        cursor %= engine.houses.size()
        var house: Dictionary = engine.houses[cursor]
        cursor += 1
        migrate(house)
        if world.at(int(house["x"]),int(house["y"])) != world.TOWN:
            remove(engine,world,int(house["id"]),false,"terrain_destruction")
            continue
        var row: Dictionary = engine.catalogue.definition(str(house["definition_id"]))
        var interval = int(row.get("structural", {}).get("deterioration_interval", 3600))
        var periods = (int(world.tick) - int(house["last_condition_tick"])) / interval
        if periods > 0:
            house["last_condition_tick"] += periods * interval
            damage(engine, world, int(house["id"]), periods * int(row["structural"]["deterioration"]), "weathering")
        # Repair demand only; actual worker labour and paid materials perform it.
        if int(house["condition"]) < 75 and not house["abandoned"] and not house.has("pending_action"):
            request_action(engine, world, int(house["id"]), "repair")

# Renovations/conversions reuse the very same sites, shipments, tasks and stages.
func begin_transition(engine: RefCounted, world: RefCounted, id: int, target: String, kind: String) -> bool:
    var house: Dictionary = engine.building_by_id(id)
    if house.is_empty() or kind not in ["upgrade", "conversion"] or house.has("pending_action"):
        return false
    migrate(house)
    var before: Dictionary = engine.catalogue.definition(str(house["definition_id"]))
    var paths: Array = before["upgrades" if kind == "upgrade" else "conversions"]
    var row: Dictionary = engine.catalogue.definition(target)
    if target not in paths or not engine.catalogue.eligible(world,world.settlements.sid(house),row) or engine.eligible_workers(world,world.settlements.sid(house),row) == 0:
        return false
    var cell := Vector2i(int(house["x"]),int(house["y"]))
    if engine.placement.validate(world,row,cell,int(house["orientation"]),id) != "" or engine.projects.size() >= engine.MAX_SITES:
        return false
    var site: Dictionary = Site.create(id,int(house["nation"]),row,cell,int(house["orientation"]),world.tick)
    site["settlement_id"] = world.settlements.sid(house)
    site["previous_building"] = house.duplicate(true)
    site["transition"] = kind
    site["priority"] = 60
    var old_cells: Array = engine.placement.footprint(before,cell,int(house["orientation"]))
    for point in engine.placement.footprint(row,cell,int(house["orientation"])):
        var old_index: int = old_cells.find(point)
        site["original_terrain"].append(house["original_terrain"][old_index] if old_index >= 0 and old_index < house["original_terrain"].size() else world.at(point.x,point.y))
    engine.houses.erase(house)
    world.inventory.close_storage(world,house)
    pending.erase(id)
    engine.buildings_by_id.erase(id)
    engine.placement.release(id)
    engine.projects.append(site)
    engine.sites_by_id[id] = site
    engine.placement.claim(row,site)
    engine.indexed_houses = engine.houses.size()
    engine.reserve_available(world,site)
    world.households.dirty = true
    engine.revision += 1
    return true
