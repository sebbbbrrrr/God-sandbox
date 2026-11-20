extends RefCounted
# Phase B2: intentional, materially bounded families and reproduction.
# No global birth rate, instant children, nation-wide marriage rule or
# automatic fertility change from a historical era or faith label.
const Calendar = preload("res://scripts/ai/sim_calendar.gd")
const Relations = preload("res://scripts/ai/relationships.gd")
const Nav = preload("res://scripts/ai/navigation.gd")
const PLAN_INTERVAL := 180
const GESTATION_TICKS := 1800
const MIN_SPACING_TICKS := Calendar.TICKS_PER_YEAR * 2
const MAX_DELAY_TICKS := Calendar.TICKS_PER_YEAR
const MAX_DEPENDENTS := 4
const MIN_STABLE_PANTRY := 6
const MAX_TOMBSTONES := 1000

var partners: Dictionary = {} # citizen ID -> committed partner ID
var pregnancies: Dictionary = {} # gestational citizen ID -> due dates/parentage
var last_birth: Dictionary = {}
var family_birth_counts: Dictionary = {} # retained children born in household
var household_preferences: Dictionary = {} # opt-in local individual/cultural family goals
var family_security: Dictionary = {} # rolling observed pantry and health state
var tombstones: Array[Dictionary] = []
var births_total := 0
var deaths_archived := 0

static func can_gestate_for(seed: int, id: int) -> bool:
    # Capability is independent of personality, education, nationality and religion.
    # It is a gameplay reproductive-role flag, not a citizen gender.
    return posmod(seed + id, 2) == 0

func initialize_citizen(world: RefCounted, citizen: Dictionary) -> void:
    citizen["can_gestate"] = can_gestate_for(int(world.seed), int(citizen["id"]))
    citizen["last_birth_tick"] = -Calendar.TICKS_PER_YEAR * 100
    citizen["last_partner_decision"] = int(world.tick)

func migrate_citizen(world: RefCounted, citizen: Dictionary) -> void:
    citizen["can_gestate"] = bool(citizen.get("can_gestate",
        can_gestate_for(int(world.seed), int(citizen["id"]))))
    citizen["last_birth_tick"] = int(citizen.get("last_birth_tick",
        -Calendar.TICKS_PER_YEAR * 100))
    citizen["last_partner_decision"] = int(citizen.get("last_partner_decision", world.tick))

func set_household_preferences(household_id: int, data: Dictionary) -> bool:
    # Future religious/cultural institutions may influence this only through
    # actual expressed household preferences. No faith-specific defaults.
    if household_id <= 0:
        return false
    var desired_children: int = int(data.get("desired_children", 2))
    var minimum_spacing_years: int = int(data.get("minimum_spacing_years", 2))
    var partnership_interest: int = int(data.get("partnership_interest", 55))
    var social_adulthood: int = int(data.get("social_adulthood_age", 18))
    if desired_children < 0 or desired_children > 4 or minimum_spacing_years < 1 or minimum_spacing_years > 8 or partnership_interest < 0 or partnership_interest > 100 or social_adulthood < 18 or social_adulthood > 30:
        return false
    household_preferences[str(household_id)] = {
        "desired_children": desired_children,
        "minimum_spacing_years": minimum_spacing_years,
        "partnership_interest": partnership_interest,
        "social_adulthood_age": social_adulthood}
    return true

func on_household_merge(primary_id: int, absorbed_id: int) -> void:
    var primary_key := str(primary_id)
    var absorbed_key := str(absorbed_id)
    if household_preferences.has(absorbed_key):
        var incoming: Dictionary = household_preferences[absorbed_key]
        if household_preferences.has(primary_key):
            var existing: Dictionary = household_preferences[primary_key]
            # Forming a household never overrides an adult's explicit wish
            # not to have children. A longer requested spacing also wins.
            existing["desired_children"] = mini(int(existing["desired_children"]),
                int(incoming["desired_children"]))
            existing["minimum_spacing_years"] = maxi(int(existing["minimum_spacing_years"]),
                int(incoming["minimum_spacing_years"]))
            existing["partnership_interest"] = mini(int(existing["partnership_interest"]),
                int(incoming["partnership_interest"]))
            existing["social_adulthood_age"] = maxi(int(existing.get("social_adulthood_age", 18)),
                int(incoming.get("social_adulthood_age", 18)))
        else:
            household_preferences[primary_key] = incoming.duplicate(true)
    household_preferences.erase(absorbed_key)
    family_birth_counts[primary_key] = int(family_birth_counts.get(primary_key, 0)) + int(
        family_birth_counts.get(absorbed_key, 0))
    family_birth_counts.erase(absorbed_key)
    if not family_security.has(primary_key) and family_security.has(absorbed_key):
        family_security[primary_key] = family_security[absorbed_key]
    family_security.erase(absorbed_key)
    for pregnancy in pregnancies.values():
        if int(pregnancy["household_id"]) == absorbed_id:
            pregnancy["household_id"] = primary_id

func eligible_adult(world: RefCounted, citizen: Dictionary) -> bool:
    if citizen.is_empty() or int(citizen["hp"]) < 50 or int(citizen.get("hunger", 0)) > 50:
        return false
    var age: int = world.calendar.age_years(int(citizen["birth_tick"]), int(world.tick))
    return age >= 18 and age <= 64

func related(a: Dictionary, b: Dictionary) -> bool:
    var a_id: int = int(a["id"])
    var b_id: int = int(b["id"])
    var a_parents: Array = a.get("parent_ids", [])
    var b_parents: Array = b.get("parent_ids", [])
    if a_parents.has(b_id) or b_parents.has(a_id):
        return true
    for parent in a_parents:
        if int(parent) > 0 and b_parents.has(int(parent)):
            return true
    return false

func affinity(world: RefCounted, a: Dictionary, b: Dictionary) -> int:
    var a_mind: Dictionary = world.citizen_ai_by_id.get(str(a["id"]), {})
    var b_mind: Dictionary = world.citizen_ai_by_id.get(str(b["id"]), {})
    if a_mind.is_empty() or b_mind.is_empty():
        return -10000
    var a_tie := Relations.find(a_mind, int(b["id"]))
    var b_tie := Relations.find(b_mind, int(a["id"]))
    if a_tie.is_empty() or b_tie.is_empty():
        return -10000
    if int(a_tie["trust"]) < 3 or int(b_tie["trust"]) < 3:
        return -10000
    if int(a_tie["rivalry"]) > 15 or int(b_tie["rivalry"]) > 15:
        return -10000
    return (Relations.preference(a_tie) + Relations.preference(b_tie)) / 2

func partnership_interest(world: RefCounted, a: Dictionary) -> int:
    var custom: Dictionary = household_preferences.get(str(a["household_id"]), {})
    if not custom.is_empty():
        return int(custom.get("partnership_interest", 55))
    var mind: Dictionary = world.citizen_ai_by_id.get(str(a["id"]), {})
    if mind.is_empty():
        return 0
    # Agent personality can influence an expressed choice; it is not a
    # destiny or a rule derived from faith, location or citizenship.
    return clampi(50 + (int(mind["personality"]["sociability"]) - 50) / 2
        - (int(mind["personality"]["caution"]) - 50) / 3, 0, 100)

func meets_social_adulthood(world: RefCounted, citizen: Dictionary) -> bool:
    var policy: Dictionary = household_preferences.get(str(citizen["household_id"]), {})
    var minimum: int = int(policy.get("social_adulthood_age", 18))
    return world.calendar.age_years(int(citizen["birth_tick"]), world.tick) >= minimum

func find_partner(world: RefCounted) -> void:
    # Bounded local candidate lists from the existing spatial index.
    for a in world.citizens:
        if not eligible_adult(world, a) or not meets_social_adulthood(world, a) or partners.has(str(a["id"])):
            continue
        if partnership_interest(world, a) < 35:
            continue
        var nearby: Array = world.ai_context.nearby(world, a)
        var candidate: Dictionary = {}
        var best_score := 12
        for b in nearby:
            if int(b["id"]) <= int(a["id"]) or not eligible_adult(world, b) or not meets_social_adulthood(world, b):
                continue
            if partners.has(str(b["id"])) or int(a["nation"]) != int(b["nation"]) or related(a, b):
                continue
            if partnership_interest(world, b) < 35:
                continue
            if Nav.manhattan(Vector2i(int(a["x"]), int(a["y"])),
                    Vector2i(int(b["x"]), int(b["y"]))) > 2:
                continue
            var score: int = affinity(world, a, b)
            if score > best_score or (score == best_score and
                    (candidate.is_empty() or int(b["id"]) < int(candidate["id"]))):
                best_score = score
                candidate = b
        if candidate.is_empty():
            continue
        var b_id: int = int(candidate["id"])
        if not world.households.form_household(world, int(a["id"]), b_id):
            continue
        partners[str(a["id"])] = b_id
        partners[str(b_id)] = int(a["id"])
        world.lifecycle.append_event(world, a, "partnered",
            {"partner_id": b_id, "household_id": int(a["household_id"]),
            "observed_affinity": best_score})

func household_dependents(world: RefCounted, family: Dictionary) -> int:
    var result := 0
    for id in family["members"]:
        var member: Dictionary = world.ai_context.people.get(int(id), {})
        if not member.is_empty() and int(member["hp"]) > 0 and world.lifecycle.is_dependent(member):
            result += 1
    return result

func family_young_children(world: RefCounted, family: Dictionary) -> int:
    var count := 0
    for id in family["members"]:
        var member: Dictionary = world.ai_context.people.get(int(id), {})
        if member.is_empty() or int(member["hp"]) <= 0:
            continue
        if world.calendar.age_years(int(member["birth_tick"]), world.tick) < 13:
            count += 1
    return count

func update_security(world: RefCounted) -> void:
    for family in world.households.families:
        var key := str(family["id"])
        var current: int = 0
        var living := world.households.member_count(world, family)
        if living <= 0:
            continue
        var stored: int = world.food.total(world.food.pantry_for(int(family["id"])))
        var food_per_member: int = stored * 100 / maxi(1, living * 4)
        var worst_hunger := 0
        for member_id in family["members"]:
            var person: Dictionary = world.ai_context.people.get(int(member_id), {})
            if not person.is_empty() and int(person["hp"]) > 0:
                worst_hunger = maxi(worst_hunger, int(person.get("hunger", 0)))
        var climate: int = int(world.calendar.date_at(world.tick)["season_index"])
        var winter_penalty := 5 if climate == 3 else 0
        current = clampi(food_per_member - worst_hunger / 2 - winter_penalty, 0, 100)
        var previous: int = int(family_security.get(key, current))
        family_security[key] = (previous * 2 + current) / 3
    for key in family_security.keys():
        if world.households.family_for(int(key)).is_empty():
            family_security.erase(key)
    for key in household_preferences.keys():
        if world.households.family_for(int(key)).is_empty():
            household_preferences.erase(key)
    for key in family_birth_counts.keys():
        if world.households.family_for(int(key)).is_empty():
            family_birth_counts.erase(key)

func try_conception(world: RefCounted) -> void:
    if world.citizens.size() >= world.MAX_PEOPLE:
        return
    var seen := {}
    for a_id in partners.keys():
        var a_num := int(a_id)
        var b_num: int = int(partners[a_id])
        var key := str(mini(a_num, b_num))
        if seen.has(key):
            continue
        seen[key] = true
        var a: Dictionary = world.ai_context.people.get(mini(a_num, b_num), {})
        var b: Dictionary = world.ai_context.people.get(maxi(a_num, b_num), {})
        if a.is_empty() or b.is_empty() or not eligible_adult(world, a) or not eligible_adult(world, b):
            continue
        if int(a["household_id"]) != int(b["household_id"]):
            continue
        var gestator := a if bool(a["can_gestate"]) else b
        var partner := b if gestator == a else a
        if not bool(gestator.get("can_gestate", false)):
            continue
        var age: int = world.calendar.age_years(int(gestator["birth_tick"]), world.tick)
        if age > 44 or int(gestator["hp"]) < 75 or int(gestator["hunger"]) >= 35:
            continue
        if pregnancies.has(str(gestator["id"])):
            continue
        var family: Dictionary = world.households.family_for(int(gestator["household_id"]))
        if family.is_empty() or int(family["home_id"]) <= 0:
            continue
        var resident_children: int = household_dependents(world, family)
        var preference: Dictionary = household_preferences.get(str(family["id"]), {})
        var desired: int = int(preference.get("desired_children", 2))
        var spacing: int = maxi(MIN_SPACING_TICKS,
            int(preference.get("minimum_spacing_years", 2)) * Calendar.TICKS_PER_YEAR)
        if desired <= 0 or resident_children >= MAX_DEPENDENTS or int(
                family_birth_counts.get(str(family["id"]), 0)) >= desired:
            continue
        var home: Dictionary = world.households.house_by_id(world, int(family["home_id"]))
        if home.is_empty() or not world.households.has_room(world, int(family["home_id"]), 1):
            continue
        if int(world.tick) - int(last_birth.get(str(gestator["id"]),
                gestator.get("last_birth_tick", -Calendar.TICKS_PER_YEAR * 100))) < spacing:
            continue
        var stored: int = world.food.total(world.food.pantry_for(int(family["id"])))
        var minimum: int = maxi(MIN_STABLE_PANTRY, world.households.member_count(world, family) * 3)
        if stored < minimum or int(family_security.get(str(family["id"]), 0)) < 60:
            continue
        var horizon: int = int(world.calendar.date_at(world.tick)["season_index"])
        if horizon == 3 and stored < minimum + 4:
            continue
        pregnancies[str(gestator["id"])] = {
            "gestator_id": int(gestator["id"]), "partner_id": int(partner["id"]),
            "household_id": int(family["id"]), "conception_tick": int(world.tick),
            "due_tick": int(world.tick) + GESTATION_TICKS,
            "deprivation_checks": 0}
        world.lifecycle.append_event(world, gestator, "expecting",
            {"other_parent_id": int(partner["id"]), "due_tick": int(world.tick) + GESTATION_TICKS})

func fail_pregnancy(world: RefCounted, gestator: Dictionary, reason: String) -> void:
    if gestator.is_empty():
        return
    if not pregnancies.has(str(gestator["id"])):
        return
    pregnancies.erase(str(gestator["id"]))
    world.lifecycle.append_event(world, gestator, "pregnancy_ended", {"cause": reason})

func monitor_pregnancies(world: RefCounted) -> void:
    if int(world.tick) % 120 != 0:
        return
    for key in pregnancies.keys():
        var pregnancy: Dictionary = pregnancies[key]
        var gestator: Dictionary = world.ai_context.people.get(int(pregnancy["gestator_id"]), {})
        if gestator.is_empty():
            pregnancies.erase(key)
            continue
        if int(gestator["hp"]) <= 0:
            fail_pregnancy(world, gestator, "parent_died")
            continue
        if int(gestator["hp"]) < 50 or int(gestator.get("hunger", 0)) >= 70:
            pregnancy["deprivation_checks"] = int(pregnancy["deprivation_checks"]) + 1
        else:
            pregnancy["deprivation_checks"] = maxi(0, int(pregnancy["deprivation_checks"]) - 1)
        if int(pregnancy["deprivation_checks"]) >= 8:
            fail_pregnancy(world, gestator, "severe_deprivation")
        elif int(world.tick) > int(pregnancy["due_tick"]) + MAX_DELAY_TICKS:
            fail_pregnancy(world, gestator, "unresolved_shelter_or_care")

func care_at_birth(world: RefCounted, gestator: Dictionary, pregnancy: Dictionary) -> bool:
    var family: Dictionary = world.households.family_for(int(gestator["household_id"]))
    if family.is_empty() or int(family["id"]) != int(pregnancy["household_id"]):
        return false
    var house: Dictionary = world.households.house_by_id(world, int(family["home_id"]))
    if house.is_empty() or not world.households.has_room(world, int(family["home_id"]), 1):
        return false
    if int(gestator["hp"]) < 50 or int(gestator.get("hunger", 0)) >= 70:
        return false
    if world.food.total(world.food.pantry_for(int(family["id"]))) < 2:
        return false
    var site := Vector2i(int(house["x"]), int(house["y"]))
    var position := Vector2i(int(gestator["x"]), int(gestator["y"]))
    return Nav.manhattan(position, site) <= 1 and world.is_walkable(position.x, position.y)

func delivery_step(world: RefCounted, person: Dictionary, mind: Dictionary) -> bool:
    var key := str(person["id"])
    if not pregnancies.has(key):
        return false
    var pregnancy: Dictionary = pregnancies[key]
    if int(world.tick) < int(pregnancy["due_tick"]):
        return false
    var family: Dictionary = world.households.family_for(int(person["household_id"]))
    var house: Dictionary = world.households.house_by_id(world, int(family.get("home_id", 0)))
    if house.is_empty() or not world.households.has_room(world, int(family.get("home_id", 0)), 1):
        return false # keep working / seeking shelter rather than deadlocking
    if int(person["hp"]) < 50 or int(person.get("hunger", 0)) >= 70 or (
            world.food.total(world.food.pantry_for(int(family["id"]))) < 2):
        return false # mother can continue gathering food until safe to deliver
    var home := Vector2i(int(house["x"]), int(house["y"]))
    var pos := Vector2i(int(person["x"]), int(person["y"]))
    if Nav.manhattan(pos, home) > 1:
        var next: Vector2i = Nav.next_step(world, person, mind, home)
        if next != pos:
            person["x"] = next.x
            person["y"] = next.y
            world.ai_context.moved(person, pos)
        return true
    if not care_at_birth(world, person, pregnancy) or world.citizens.size() >= world.MAX_PEOPLE:
        return true
    var other_parent_id: int = int(pregnancy["partner_id"])
    if not world.add_citizen(int(person["x"]), int(person["y"]), int(person["nation"])):
        return true
    var baby: Dictionary = world.citizens[-1]
    world.lifecycle.register_newborn(world, baby, int(person["id"]), other_parent_id)
    # Joining depends on a living in-household guardian. The other biological
    # parent may have died during pregnancy; parentage is never rewritten.
    if not world.households.join_newborn(world, baby, person, person):
        # This is prevalidated by care_at_birth. No silent removal of babies.
        return true
    record_family_birth(world, baby, int(person["id"]))
    pregnancies.erase(key)
    mind["route"] = []
    return true

func on_death(world: RefCounted, person: Dictionary) -> void:
    var key := str(person["id"])
    if partners.has(key):
        var survivor_id: int = int(partners[key])
        partners.erase(key)
        partners.erase(str(survivor_id))
        var survivor: Dictionary = world.ai_context.people.get(survivor_id, {})
        if not survivor.is_empty() and int(survivor["hp"]) > 0:
            world.lifecycle.append_event(world, survivor, "bereaved",
                {"former_partner_id": int(person["id"])})
    if pregnancies.has(key):
        fail_pregnancy(world, person, "gestational_parent_died")
    # Pregnancy may remain viable if the non-gestational parent dies. The
    # child's original biological parent IDs are preserved in the record.

func record_family_birth(world: RefCounted, baby: Dictionary, gestator_id: int) -> void:
    var house_key := str(baby["household_id"])
    family_birth_counts[house_key] = int(family_birth_counts.get(house_key, 0)) + 1
    last_birth[str(gestator_id)] = int(world.tick)
    var gestator: Dictionary = world.ai_context.people.get(gestator_id, {})
    if not gestator.is_empty():
        gestator["last_birth_tick"] = int(world.tick)
    births_total += 1

func archive_dead(world: RefCounted) -> void:
    # Dead citizens occupy renderer slots until two years after death,
    # preserving legacy death expectations and allowing immediate inspection.
    # The archive is limited; full history belongs in a later data store.
    if int(world.tick) % Calendar.TICKS_PER_YEAR != 0:
        return
    var changed := false
    for i in range(world.citizens.size() - 1, -1, -1):
        var person: Dictionary = world.citizens[i]
        var deceased: int = int(person.get("death_tick", -1))
        if int(person["hp"]) > 0 or deceased < 0 or int(world.tick) - deceased < 2 * Calendar.TICKS_PER_YEAR:
            continue
        var key := str(person["id"])
        var record := {"id": int(person["id"]), "birth_tick": int(person["birth_tick"]),
            "death_tick": deceased, "nation": int(person["nation"]),
            "cause": str(person.get("death_cause", "unknown")),
            "parent_ids": person.get("parent_ids", []).duplicate(true)}
        record["career"] = world.occupations.remove_archived(int(person["id"]))
        tombstones.append(record)
        if tombstones.size() > MAX_TOMBSTONES:
            tombstones.pop_front()
        deaths_archived += 1
        partners.erase(key)
        for partner_key in partners.keys():
            if int(partners[partner_key]) == int(person["id"]):
                partners.erase(partner_key)
        pregnancies.erase(key)
        last_birth.erase(key)
        world.citizen_ai_by_id.erase(key)
        world.citizens.remove_at(i)
        changed = true
    if changed:
        world.households.dirty = true
        # Keep the save valid immediately after removal, not a tick later.
        world.households.reconcile(world)
        # Restore must not prune references that the uninterrupted world has
        # kept; remove dangling social IDs deterministically on both paths.
        for mind in world.citizen_ai_by_id.values():
            var ties: Array = mind["relationships"]
            for i in range(ties.size() - 1, -1, -1):
                if not world.citizen_ai_by_id.has(str(ties[i]["id"])):
                    ties.remove_at(i)
            if int(mind["target_id"]) > 0 and not world.citizen_ai_by_id.has(str(mind["target_id"])):
                mind["target_id"] = 0

func on_tick(world: RefCounted) -> void:
    monitor_pregnancies(world)
    if int(world.tick) % PLAN_INTERVAL == 0:
        update_security(world)
        find_partner(world)
        try_conception(world)
    archive_dead(world)

func snapshot() -> Dictionary:
    return {"version": 1, "partners": partners.duplicate(true),
        "pregnancies": pregnancies.duplicate(true),
        "last_birth": last_birth.duplicate(true),
        "family_birth_counts": family_birth_counts.duplicate(true),
        "household_preferences": household_preferences.duplicate(true),
        "family_security": family_security.duplicate(true),
        "tombstones": tombstones.duplicate(true),
        "births_total": births_total, "deaths_archived": deaths_archived}

func load_state(world: RefCounted, raw: Variant) -> bool:
    if raw == null:
        return true
    if not raw is Dictionary or int(raw.get("version", -1)) != 1:
        return false
    for field in ["partners", "pregnancies", "last_birth",
            "household_preferences", "family_security"]:
        if not raw.get(field) is Dictionary:
            return false
    if not raw.get("tombstones") is Array or raw["tombstones"].size() > MAX_TOMBSTONES:
        return false
    for person in world.citizens:
        migrate_citizen(world, person)
    partners = raw["partners"].duplicate(true)
    pregnancies = raw["pregnancies"].duplicate(true)
    last_birth = raw["last_birth"].duplicate(true)
    if raw.has("family_birth_counts"):
        if not raw["family_birth_counts"] is Dictionary:
            return false
        family_birth_counts = raw["family_birth_counts"].duplicate(true)
    household_preferences = raw["household_preferences"].duplicate(true)
    family_security = raw["family_security"].duplicate(true)
    tombstones = raw["tombstones"].duplicate(true)
    births_total = maxi(0, int(raw.get("births_total", 0)))
    deaths_archived = maxi(0, int(raw.get("deaths_archived", 0)))
    for key in pregnancies:
        var entry: Variant = pregnancies[key]
        if not entry is Dictionary or int(entry.get("gestator_id", -1)) != int(key) or not bool(
                world.ai_context.people.get(int(key), {}).get("can_gestate", false)):
            return false
    return true
