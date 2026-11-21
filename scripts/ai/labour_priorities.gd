extends RefCounted
# Deterministic labour priorities. These are derived from authoritative jobs,
# stores and household demand: no second workforce registry or saved shadow state.
# Keep recruitment bounded for Android and leave ongoing cargo/jobs uninterrupted.

static func pressures(world: RefCounted, sid: int) -> Dictionary:
    # Housing capacity is an O(buildings) query; compute it once per
    # settlement per simulation tick, not once for every idle citizen.
    var engine = world.construction
    if int(engine.labour_cache_tick) != int(world.tick):
        engine.labour_cache_tick = int(world.tick)
        engine.labour_pressure_cache.clear()
    if engine.labour_pressure_cache.has(sid):
        return engine.labour_pressure_cache[sid]
    var population: int = maxi(0, world.settlements.population(sid))
    var food_units: int = world.food.total(world.food.store(sid))
    var shelter: int = world.settlements.housing(world, sid)
    var pressure := {
        "food_emergency": food_units < maxi(4, population),
        "food_low": food_units < maxi(8, population * 3),
        "unsheltered": maxi(0, population - shelter),
        "population": population,
        "food_units": food_units
    }
    engine.labour_pressure_cache[sid] = pressure
    return pressure

static func project_score(world: RefCounted, site: Dictionary,
        origin: Vector2i, pressure: Dictionary) -> int:
    var destination := Vector2i(int(site["x"]), int(site["y"]))
    var kind := str(site.get("demand", {}).get("function", ""))
    if kind == "":
        kind = str(world.construction.catalogue.definition(
            str(site["definition_id"])).get("function", ""))
    var urgency: int = int(site.get("priority", 50)) * 100
    if kind == "shelter" and int(pressure["unsheltered"]) > 0:
        urgency += 1800 + mini(20, int(pressure["unsheltered"])) * 20
    elif kind == "farm" and bool(pressure["food_low"]):
        urgency += 1600
    elif kind in ["storage", "forestry", "quarry"] and bool(pressure["food_emergency"]):
        urgency -= 600
    # Avoid starving old sites when a constant stream of new requests appears.
    urgency += mini(400, maxi(0, int(world.tick) - int(site.get(
        "last_progress_tick", world.tick))) / 12)
    return urgency - (absi(origin.x - destination.x) + absi(origin.y - destination.y)) * 4

static func can_deliver_food(world: RefCounted, sid: int, family_id: int) -> bool:
    var population: int = maxi(1, world.settlements.population(sid))
    var available: int = world.food.total(world.food.store(sid))
    # Reserve enough food for direct emergency meals at the depot.
    if available < maxi(3, population / 3):
        return false
    var couriers: int = 0
    for job in world.food.jobs.values():
        if str(job.get("kind", "")) != "deliver" or int(job.get("nation", -1)) != sid:
            continue
        if int(job.get("family_id", 0)) == family_id:
            return false # one actual delivery per household; no duplicated trips
        couriers += 1
    return couriers < clampi((population + 15) / 16, 1, 6)

static func claim_count(jobs: Dictionary, source: Array,
        kinds: Array) -> int:
    var claimed: int = 0
    for job in jobs.values():
        if str(job.get("kind", "")) in kinds and job.get("source", []) == source and \
                str(job.get("phase", "")) == "source":
            claimed += 1
    return claimed
