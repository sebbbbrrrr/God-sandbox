extends RefCounted
const Nav = preload("res://scripts/ai/navigation.gd")
const MAX_ACTIVE := 2
const MAX_PARTY := 8
const MIN_ADULTS := 2
const ATTEMPT_INTERVAL := 240
const TIMEOUT := 1200
var expeditions: Dictionary = {}
var assignments: Dictionary = {} # derived citizen -> expedition (never another AI)
var cooldowns: Dictionary = {}
var next_id := 1
var cursor := 0

func active_count() -> int:
    var count := 0
    for row in expeditions.values():
        if str(row["phase"]) in ["travel", "camp", "return"]:
            count += 1
    return count

func pressure(world: RefCounted, id: int) -> int:
    var population: int = world.settlements.population(id)
    if population < 8:
        return 0
    var housing: int = world.settlements.housing(world, id)
    var center: Vector2i = world.settlements.center(world, id)
    if center.x < 0:
        return 0
    var local: Dictionary = world.settlement_planner.survey(world, center)
    var result := maxi(0, population - housing) * 6
    result += maxi(0, population - int(local["food"]) / 3) * 3
    if int(local["wood"]) < 4 or int(local["stone"]) < 1:
        result += 20
    return clampi(result, 0, 100)

func eligible_family(world: RefCounted, family: Dictionary, source: int) -> bool:
    if int(family.get("settlement_id", family["nation"])) != source or world.food.total(world.food.pantry_for(int(family["id"]))) > 0:
        return false
    var adults := 0
    for member in family["members"]:
        var person: Dictionary = world.ai_context.people.get(int(member), {})
        if person.is_empty() or int(person["hp"]) <= 0:
            continue
        var key := str(member)
        # Infants need an explicit travelling-care extension; never leave one
        # behind or bypass the current stationary infant-care controller.
        if str(person["life_stage"]) == "infant" or int(person["hp"]) < 70 or int(person["hunger"]) >= 36 \
                or assignments.has(key) or world.construction.jobs.has(key) or world.food.jobs.has(key) \
                or world.toolmaking.jobs.has(key) or world.regional_economy.road_jobs.has(key) \
                or world.regional_economy.trade_jobs.has(key) or world.demography.pregnancies.has(key):
            return false
        if not world.lifecycle.is_dependent(person):
            adults += 1
        elif world.households.living_person(world, int(person.get("guardian_id", 0))).is_empty():
            return false
        for link in world.occupations.apprenticeships.values():
            if int(link.get("teacher_id", 0)) == int(member) or int(link.get("student_id", 0)) == int(member):
                return false # don't override an existing teaching commitment
    return adults > 0

func try_start(world: RefCounted, source: int) -> Dictionary:
    if active_count() >= MAX_ACTIVE or world.settlements.records.size() >= world.settlements.MAX_SETTLEMENTS \
            or world.tick < int(cooldowns.get(str(source), 0)) or pressure(world, source) < 48:
        return {}
    cooldowns[str(source)] = world.tick + ATTEMPT_INTERVAL
    var families: Array = []
    var members: Array = []
    var adults := 0
    var candidates: Array = []
    for family in world.households.families:
        if eligible_family(world, family, source):
            var steward: Dictionary = world.households.living_person(world, int(family["steward_id"]))
            if steward.is_empty():
                continue
            var mind: Dictionary = world.citizen_ai_by_id[str(steward["id"])]
            var traits: Dictionary = mind["personality"]
            var score := int(traits["curiosity"]) + int(traits["diligence"]) / 2 - int(traits["caution"]) / 2
            score += 40 if int(family["home_id"]) == 0 else 0
            candidates.append({"family": family, "score": score, "id": int(family["id"])})
    candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["score"]) > int(b["score"]) or (int(a["score"]) == int(b["score"]) and int(a["id"]) < int(b["id"])))
    for candidate in candidates:
        var family: Dictionary = candidate["family"]
        # Cohorts are whole households. Existing strong personal grievances
        # can veto joining a founder; no political/cultural traits are invented.
        var steward_id := int(family["steward_id"])
        var compatible := true
        if not members.is_empty():
            for tie in world.citizen_ai_by_id[str(members[0])]["relationships"]:
                if int(tie["id"]) == steward_id and int(tie.get("rivalry", 0)) >= 60:
                    compatible = false
        if not compatible:
            continue
        var size: int = world.households.member_count(world, family)
        if size <= 0 or members.size() + size > MAX_PARTY or world.settlements.population(source) - members.size() - size < 4:
            continue
        families.append(int(family["id"]))
        for member in family["members"]:
            var person: Dictionary = world.ai_context.people.get(int(member), {})
            if not person.is_empty() and int(person["hp"]) > 0:
                members.append(int(member))
                if not world.lifecycle.is_dependent(person):
                    adults += 1
        if adults >= MIN_ADULTS and members.size() >= 3:
            break
    if adults < MIN_ADULTS:
        return {}
    var origin: Vector2i = world.settlements.center(world, source)
    var target: Vector2i = world.settlement_planner.choose_site(world, origin)
    if target.x < 0:
        return {}
    var id := next_id
    next_id += 1
    var row := {"id": id, "source": source, "target": [target.x, target.y],
        "members": members, "families": families, "founder_id": int(members[0]),
        "phase": "travel", "started_tick": world.tick, "settlement_id": -1,
        "reason": "population_and_resource_pressure", "last_progress_tick": world.tick}
    expeditions[str(id)] = row
    for member in members:
        assignments[str(member)] = id
        var mind: Dictionary = world.citizen_ai_by_id[str(member)]
        mind["route"] = []
        mind["next_path_tick"] = world.tick
    world.settlements.event(world, source, "founding_party_departed")
    return row

func _survivors(world: RefCounted, row: Dictionary) -> Array:
    var result: Array = []
    for member in row["members"]:
        var person: Dictionary = world.ai_context.people.get(int(member), {})
        if not person.is_empty() and int(person["hp"]) > 0:
            result.append(person)
    return result

func _release(row: Dictionary) -> void:
    for member in row["members"]:
        assignments.erase(str(member))

func fail(world: RefCounted, row: Dictionary, reason: String) -> void:
    if str(row["phase"]) not in ["travel", "camp"]:
        return
    row["reason"] = reason
    if str(row["phase"]) == "travel":
        row["phase"] = "return" # membership still belongs to source; walk back
        row["started_tick"] = world.tick
        for member in row["members"]:
            if world.citizen_ai_by_id.has(str(member)):
                world.citizen_ai_by_id[str(member)]["route"] = []
    else:
        # Already resident at the camp. Keep cargo and buildings where they
        # physically are; lifecycle records the failed founding attempt.
        row["phase"] = "failed"
        var id := int(row["settlement_id"])
        world.settlements.get_record(id)["status"] = "struggling"
        world.settlements.event(world, id, "founding_failed:" + reason)
        _release(row)

func travel_step(world: RefCounted, person: Dictionary, mind: Dictionary) -> bool:
    var key := str(person["id"])
    if not assignments.has(key):
        return false
    var row: Dictionary = expeditions[str(assignments[key])]
    if str(row["phase"]) not in ["travel", "return"]:
        return false
    # Prioritised AFTER urgent safety, care and eating, BEFORE optional work.
    # Food jobs that predate the decision are excluded by eligibility.
    var target: Vector2i = world.settlements.center(world, int(row["source"])) if str(row["phase"]) == "return" else Vector2i(int(row["target"][0]), int(row["target"][1]))
    var here := Vector2i(int(person["x"]), int(person["y"]))
    if Nav.manhattan(here, target) <= 2:
        return true
    # Don't outrun household children; existing dependent AI follows guardians.
    var family: Dictionary = world.households.family_for(int(person["household_id"]))
    for member in family.get("members", []):
        var child: Dictionary = world.ai_context.people.get(int(member), {})
        if not child.is_empty() and int(child["hp"]) > 0 and world.lifecycle.is_dependent(child) \
                and Nav.manhattan(here, Vector2i(int(child["x"]), int(child["y"]))) > 3:
            return true
    world.construction.walk(world, person, mind, target)
    if here != Vector2i(int(person["x"]), int(person["y"])):
        row["last_progress_tick"] = world.tick
    return true

func tick(world: RefCounted) -> void:
    for row in expeditions.values():
        var phase := str(row["phase"])
        if phase not in ["travel", "camp", "return"]:
            continue
        var survivors := _survivors(world, row)
        if survivors.is_empty():
            row["phase"] = "failed"
            row["reason"] = "no_survivors"
            var camp: Dictionary = world.settlements.get_record(int(row["settlement_id"]))
            if not camp.is_empty():
                camp["status"] = "failed"
                world.settlements.event(world, int(row["settlement_id"]), "founding_failed:no_survivors")
            _release(row)
            continue
        if phase == "return":
            var home: Vector2i = world.settlements.center(world, int(row["source"]))
            var arrived := true
            for person in survivors:
                arrived = arrived and Nav.manhattan(home, Vector2i(int(person["x"]), int(person["y"]))) <= 3
            if arrived or world.tick - int(row["started_tick"]) >= TIMEOUT:
                row["phase"] = "failed"
                _release(row)
            continue
        var target := Vector2i(int(row["target"][0]), int(row["target"][1]))
        if not world.is_walkable(target.x, target.y) or Nav.danger_near(world, target) \
                or world.tick - int(row["started_tick"]) >= TIMEOUT:
            fail(world, row, "hazard_or_timeout")
            continue
        var adults := 0
        var arrived := true
        for person in survivors:
            if not world.lifecycle.is_dependent(person):
                adults += 1
            arrived = arrived and Nav.manhattan(target, Vector2i(int(person["x"]), int(person["y"]))) <= 3
        if adults < MIN_ADULTS:
            fail(world, row, "essential_workers_lost")
            continue
        if phase == "travel" and arrived:
            # Revalidate depleted resources before committing land and identity.
            if not world.settlement_planner.suitable(world, target, false):
                fail(world, row, "unsuitable_on_arrival")
                continue
            var source: int = int(row["source"])
            var id: int = world.settlements.register_camp(world, world.settlements.nation(source), target, int(row["founder_id"]))
            if id < 0:
                fail(world, row, "registry_capacity")
                continue
            row["settlement_id"] = id
            row["phase"] = "camp"
            world.settlements.move_households(world, row["families"], id)
            _release(row) # ordinary local gathering/construction AI takes over
            world.construction.request_construction(world, {"settlement_id": id, "function": "shelter", "priority": 95})
        elif phase == "camp":
            var id := int(row["settlement_id"])
            if world.settlements.housing(world, id) >= survivors.size() and world.food.total(world.food.store(id)) >= survivors.size():
                world.settlements.get_record(id)["status"] = "active"
                world.settlements.get_record(id)["founded_tick"] = world.tick
                world.settlements.event(world, id, "permanent_settlement_founded")
                row["phase"] = "complete"
    # One origin decision per interval, staggered across settlements.
    if world.tick % 60 == 7 and active_count() < MAX_ACTIVE:
        var keys: Array = world.settlements.records.keys()
        keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
        if not keys.is_empty():
            cursor %= keys.size()
            var id := int(keys[cursor])
            cursor += 1
            if str(world.settlements.get_record(id)["status"]) in ["legacy", "active", "struggling"]:
                try_start(world, id)
    # Bounded history; active expeditions are never discarded.
    if expeditions.size() > 48:
        for key in expeditions.keys():
            if str(expeditions[key]["phase"]) in ["complete", "failed"]:
                expeditions.erase(key)
                break

func snapshot() -> Dictionary:
    return {"version": 1, "expeditions": expeditions.duplicate(true), "cooldowns": cooldowns.duplicate(true),
        "next_id": next_id, "cursor": cursor}

func load_state(world: RefCounted, raw: Variant) -> bool:
    if raw == null:
        return true
    if not raw is Dictionary or int(raw.get("version", 0)) != 1 or not raw.get("expeditions") is Dictionary \
            or not raw.get("cooldowns") is Dictionary or raw["expeditions"].size() > 49:
        return false
    expeditions = raw["expeditions"].duplicate(true)
    cooldowns = raw["cooldowns"].duplicate(true)
    next_id = int(raw.get("next_id", 1))
    cursor = int(raw.get("cursor", 0))
    assignments.clear()
    for key in expeditions:
        var row: Variant = expeditions[key]
        if not row is Dictionary or int(row.get("id", 0)) != int(key) or int(key) <= 0 or int(key) >= next_id:
            return false
        if not row.get("members") is Array or row["members"].size() > MAX_PARTY or not row.get("families") is Array \
                or not row.get("target") is Array or row["target"].size() != 2 \
                or world.settlements.get_record(int(row.get("source", -1))).is_empty() \
                or str(row.get("phase", "")) not in ["travel", "camp", "return", "complete", "failed"]:
            return false
        if world.index_of(int(row["target"][0]), int(row["target"][1])) < 0:
            return false
        if str(row["phase"]) in ["camp", "complete"] and world.settlements.get_record(int(row.get("settlement_id", -1))).is_empty():
            return false
        if str(row["phase"]) in ["travel", "return"]:
            for member in row["members"]:
                if assignments.has(str(member)) or not world.ai_context.people.has(int(member)):
                    return false
                assignments[str(member)] = int(key)
    return active_count() <= MAX_ACTIVE
