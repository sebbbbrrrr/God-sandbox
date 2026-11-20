extends RefCounted
# Long-lived, deterministic demographics. Legacy "age" remains an update
# counter; canonical biological age is derived only from birth_tick.
const Calendar = preload("res://scripts/ai/sim_calendar.gd")
const Nav = preload("res://scripts/ai/navigation.gd")
const MAX_EVENTS := 192

var events: Array[Dictionary] = []
var next_event_id := 1

static func stage_for_age(age_years: int) -> String:
    if age_years < 3:
        return "infant"
    if age_years < 13:
        return "child"
    if age_years < 18:
        return "adolescent"
    if age_years < 60:
        return "adult"
    return "elder"

static func founder_age(world_seed: int, person_id: int) -> int:
    return 18 + posmod(world_seed * 17 + person_id * 43, 30)

static func founder_birth_tick(world_seed: int, person_id: int, tick: int) -> int:
    var years: int = founder_age(world_seed, person_id)
    var stagger: int = posmod(world_seed * 11 + person_id * 37, Calendar.TICKS_PER_YEAR)
    return tick - years * Calendar.TICKS_PER_YEAR - stagger

func initialise_founder(person: Dictionary, world_seed: int, tick: int) -> void:
    person["birth_tick"] = founder_birth_tick(world_seed, int(person["id"]), tick)
    person["life_stage"] = stage_for_age(founder_age(world_seed, int(person["id"])))
    person["parent_ids"] = []
    person["death_tick"] = -1
    person["death_cause"] = ""

func migrate_citizen(person: Dictionary, world_seed: int, tick: int) -> void:
    # Never map legacy age counter ticks to biological years.
    if not person.has("birth_tick"):
        initialise_founder(person, world_seed, tick)
        if int(person["hp"]) <= 0:
            person["death_tick"] = tick
            person["death_cause"] = "legacy_unknown"
        return
    person["birth_tick"] = mini(tick, int(person["birth_tick"]))
    var age: int = Calendar.new().age_years(int(person["birth_tick"]), tick)
    person["life_stage"] = stage_for_age(age)
    var parent_ids: Variant = person.get("parent_ids", [])
    person["parent_ids"] = parent_ids.duplicate(true) if parent_ids is Array else []
    person["death_tick"] = int(person.get("death_tick", -1))
    person["death_cause"] = str(person.get("death_cause", ""))
    if int(person["hp"]) <= 0 and int(person["death_tick"]) < 0:
        person["death_tick"] = tick
        person["death_cause"] = "legacy_unknown"

func append_event(world: RefCounted, person: Dictionary, kind: String, details: Dictionary = {}) -> void:
    var row := {"id": next_event_id, "tick": int(world.tick), "kind": kind,
        "citizen_id": int(person["id"]), "nation": int(person["nation"])}
    for key in details:
        row[key] = details[key]
    events.append(row)
    next_event_id += 1
    if events.size() > MAX_EVENTS:
        events.pop_front()

func record_death(world: RefCounted, person: Dictionary, cause: String) -> void:
    if int(person.get("death_tick", -1)) >= 0:
        return
    person["hp"] = 0
    person["death_tick"] = int(world.tick)
    person["death_cause"] = cause
    append_event(world, person, "died", {"cause": cause,
        "age_years": world.calendar.age_years(int(person["birth_tick"]), int(world.tick))})
    world.households.dirty = true

func update_person(world: RefCounted, person: Dictionary) -> void:
    if int(person["hp"]) <= 0:
        record_death(world, person, "injury")
        return
    var age: int = world.calendar.age_years(int(person["birth_tick"]), int(world.tick))
    var latest: String = stage_for_age(age)
    if str(person["life_stage"]) != latest:
        var previous := str(person["life_stage"])
        person["life_stage"] = latest
        append_event(world, person, "life_stage_changed",
            {"from": previous, "to": latest, "age_years": age})

func on_tick(world: RefCounted) -> void:
    # Canonical biological transitions happen on the exact birthday tick,
    # independent of staggered cognitive AI scheduling.
    on_year_boundary(world)
    for person in world.citizens:
        if int(person["hp"]) <= 0:
            record_death(world, person, "injury")
        elif (int(world.tick) - int(person["birth_tick"])) % Calendar.TICKS_PER_YEAR == 0:
            update_person(world, person)

func on_year_boundary(world: RefCounted) -> void:
    if int(world.tick) % Calendar.TICKS_PER_YEAR != 0:
        return
    var current_year: int = int(world.tick) / Calendar.TICKS_PER_YEAR
    for person in world.citizens:
        if int(person["hp"]) <= 0:
            record_death(world, person, "injury")
            continue
        var age: int = world.calendar.age_years(int(person["birth_tick"]), int(world.tick))
        if age < 65:
            continue
        # Tunable game model, not a claim about real human mortality.
        var older_years: int = age - 65
        var threshold: int = mini(1000, older_years * older_years / 4 + (100 - int(person["hp"])) / 5)
        var roll: int = posmod(int(world.seed) * 37 + int(person["id"]) * 104729 +
            current_year * 7919, 1000003) % 1000
        if age >= 120 or roll < threshold:
            record_death(world, person, "old_age")

func is_dependent(person: Dictionary) -> bool:
    return str(person.get("life_stage", "adult")) in ["infant", "child", "adolescent"]

func dependent_step(world: RefCounted, person: Dictionary, mind: Dictionary) -> bool:
    if not is_dependent(person):
        return false
    var age: int = world.calendar.age_years(int(person["birth_tick"]), int(world.tick))
    if age < 3:
        return true  # infants need carrying; no artificial independent movement
    var parents: Array = person.get("parent_ids", [])
    var guardian: Dictionary = {}
    for parent_id in parents:
        var candidate: Dictionary = world.ai_context.people.get(int(parent_id), {})
        if not candidate.is_empty() and int(candidate["hp"]) > 0 and int(candidate["nation"]) == int(person["nation"]):
            guardian = candidate
            break
    if guardian.is_empty():
        return true  # orphan care/household assignment is a later slice
    var here := Vector2i(int(person["x"]), int(person["y"]))
    var target := Vector2i(int(guardian["x"]), int(guardian["y"]))
    if Nav.manhattan(here, target) > 2:
        var next: Vector2i = Nav.next_step(world, person, mind, target)
        if next != here:
            person["x"] = next.x
            person["y"] = next.y
            world.ai_context.moved(person, here)
    return true

func register_newborn(world: RefCounted, person: Dictionary, parent_a: int, parent_b: int) -> void:
    person["birth_tick"] = int(world.tick)
    person["life_stage"] = "infant"
    person["parent_ids"] = [parent_a, parent_b]
    person["death_tick"] = -1
    person["death_cause"] = ""
    append_event(world, person, "born", {"parent_ids": [parent_a, parent_b]})

func snapshot() -> Dictionary:
    return {"version": 1, "events": events.duplicate(true), "next_event_id": next_event_id}

func load_state(raw: Variant) -> bool:
    if not raw is Dictionary:
        return false
    if int(raw.get("version", -1)) != 1:
        return false
    if not raw.get("events", []) is Array:
        return false
    var input_events: Array = raw["events"]
    if input_events.size() > MAX_EVENTS:
        return false
    for row in input_events:
        if not row is Dictionary:
            return false
        if int(row.get("id", 0)) <= 0 or int(row.get("citizen_id", 0)) <= 0:
            return false
        events.append(row.duplicate(true))
    next_event_id = maxi(1, int(raw.get("next_event_id", 1)))
    return true
