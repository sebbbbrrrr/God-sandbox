extends RefCounted
# Phase A2: stable household identities, physical home occupancy, caregiving and
# guardianship. Biological parent IDs remain separate from social guardians.
const Nav = preload("res://scripts/ai/navigation.gd")
const CARE_INTERVAL := 36
const HOME_ASSIGN_RADIUS := 16
const MAX_HOUSEHOLDS := 1500

var families: Array[Dictionary] = []
var next_id := 1
var dirty := true

func family_for(id: int) -> Dictionary:
    for family in families:
        if int(family["id"]) == id:
            return family
    return {}

func living_person(world: RefCounted, id: int) -> Dictionary:
    var person: Dictionary = world.ai_context.people.get(id, {})
    if not person.is_empty() and int(person["hp"]) > 0:
        return person
    return {}

func on_citizen_added(world: RefCounted, person: Dictionary) -> void:
    person["household_id"] = 0
    person["home_id"] = 0
    person["guardian_id"] = 0
    person["carried_by"] = 0
    person["last_care_tick"] = int(world.tick)
    person["care_visits"] = 0
    if families.size() >= MAX_HOUSEHOLDS:
        return
    var id := next_id
    next_id += 1
    person["household_id"] = id
    families.append({"id": id, "nation": int(person["nation"]),
        "members": [int(person["id"])], "home_id": 0,
        "steward_id": int(person["id"]), "founded_tick": int(world.tick)})
    dirty = true

func member_count(world: RefCounted, family: Dictionary) -> int:
    var number := 0
    for id in family["members"]:
        if not living_person(world, int(id)).is_empty():
            number += 1
    return number

func house_by_id(world: RefCounted, id: int) -> Dictionary:
    if id <= 0:
        return {}
    for house in world.construction.houses:
        if int(house["id"]) == id:
            return house
    return {}

func occupancy(world: RefCounted, house_id: int) -> int:
    var number := 0
    for family in families:
        if int(family["home_id"]) == house_id:
            number += member_count(world, family)
    return number

func has_room(world: RefCounted, house_id: int, new_residents: int = 1) -> bool:
    var house := house_by_id(world, house_id)
    return not house.is_empty() and occupancy(world, house_id) + new_residents <= int(house.get("capacity", 0))

func form_household(world: RefCounted, first_id: int, second_id: int) -> bool:
    if first_id == second_id:
        return false
    var first := living_person(world, first_id)
    var second := living_person(world, second_id)
    if first.is_empty() or second.is_empty():
        return false
    if int(first["nation"]) != int(second["nation"]):
        return false
    if str(first["life_stage"]) not in ["adult", "elder"] or str(second["life_stage"]) not in ["adult", "elder"]:
        return false
    if Nav.manhattan(Vector2i(int(first["x"]), int(first["y"])),
            Vector2i(int(second["x"]), int(second["y"]))) > 2:
        return false
    var a := family_for(int(first["household_id"]))
    var b := family_for(int(second["household_id"]))
    if a.is_empty() or b.is_empty():
        return false
    if int(a["id"]) == int(b["id"]):
        return true
    var original_home := int(a["home_id"])
    var second_home := int(b["home_id"])
    var combined: int = member_count(world, a) + member_count(world, b)
    # A household can be formed before housing exists; it cannot silently keep
    # a home whose real bed capacity is smaller than the merged family.
    var retained_home := 0
    if original_home > 0 and has_room(world, original_home, member_count(world, b)):
        retained_home = original_home
    elif second_home > 0 and has_room(world, second_home, member_count(world, a)):
        retained_home = second_home
    var members: Array = a["members"]
    for id in b["members"]:
        members.append(int(id))
        var person := living_person(world, int(id))
        if not person.is_empty():
            person["household_id"] = int(a["id"])
    for i in range(families.size()):
        if int(families[i]["id"]) == int(b["id"]):
            families.remove_at(i)
            break
    a["home_id"] = retained_home
    a["steward_id"] = first_id
    for id in members:
        var member := living_person(world, int(id))
        if not member.is_empty():
            member["home_id"] = retained_home
    dirty = true
    world.lifecycle.append_event(world, first, "household_formed",
        {"household_id": int(a["id"]), "second_adult_id": second_id, "members": combined})
    return true

func join_newborn(world: RefCounted, baby: Dictionary, parent_a: Dictionary, parent_b: Dictionary) -> bool:
    var family_id: int = int(parent_a["household_id"])
    if family_id <= 0 or family_id != int(parent_b["household_id"]):
        return false
    var family := family_for(family_id)
    if family.is_empty():
        return false
    var home_id: int = int(family["home_id"])
    if not has_room(world, home_id, 1):
        return false
    var solo_id: int = int(baby["household_id"])
    for i in range(families.size() - 1, -1, -1):
        if int(families[i]["id"]) == solo_id:
            families.remove_at(i)
            break
    var members: Array = family["members"]
    members.append(int(baby["id"]))
    baby["household_id"] = family_id
    baby["home_id"] = home_id
    baby["guardian_id"] = int(parent_a["id"])
    baby["carried_by"] = 0
    baby["last_care_tick"] = int(world.tick)
    dirty = true
    return true

func pick_steward(world: RefCounted, family: Dictionary) -> int:
    for id in family["members"]:
        var person := living_person(world, int(id))
        if not person.is_empty() and str(person["life_stage"]) in ["adult", "elder"]:
            return int(id)
    return 0

func pick_guardian(world: RefCounted, family: Dictionary) -> int:
    return pick_steward(world, family)

func adopt_unprotected(world: RefCounted, child: Dictionary) -> void:
    var selected: Dictionary = {}
    var best_distance := 2147483647
    for family in families:
        if int(family["id"]) == int(child["household_id"]) or int(family["nation"]) != int(child["nation"]):
            continue
        var adult_id: int = pick_guardian(world, family)
        if adult_id <= 0:
            continue
        if int(family["home_id"]) <= 0 or not has_room(world, int(family["home_id"]), 1):
            continue
        var guardian := living_person(world, adult_id)
        var distance: int = Nav.manhattan(Vector2i(int(child["x"]), int(child["y"])),
            Vector2i(int(guardian["x"]), int(guardian["y"])))
        if distance < best_distance and distance <= HOME_ASSIGN_RADIUS:
            best_distance = distance
            selected = family
    if selected.is_empty():
        child["guardian_id"] = 0
        return
    var original: Dictionary = family_for(int(child["household_id"]))
    if not original.is_empty():
        var members: Array = original["members"]
        members.erase(int(child["id"]))
    var selected_members: Array = selected["members"]
    selected_members.append(int(child["id"]))
    child["household_id"] = int(selected["id"])
    child["home_id"] = int(selected["home_id"])
    child["guardian_id"] = pick_guardian(world, selected)
    child["carried_by"] = 0
    world.lifecycle.append_event(world, child, "guardian_assigned",
        {"household_id": int(selected["id"]), "guardian_id": int(child["guardian_id"])})
    dirty = true

func assign_homes(world: RefCounted) -> void:
    for house in world.construction.houses:
        var home_id: int = int(house["id"])
        var remaining: int = int(house.get("capacity", 0)) - occupancy(world, home_id)
        if remaining <= 0:
            continue
        # Nearest eligible family first, stable ID ties. Families are never
        # split across dwellings; multiple families may share a larger house.
        while remaining > 0:
            var selected: Dictionary = {}
            var best := 2147483647
            for family in families:
                if int(family["nation"]) != int(house["nation"]) or int(family["home_id"]) > 0:
                    continue
                var size: int = member_count(world, family)
                if size <= 0 or size > remaining:
                    continue
                var representative := living_person(world, int(family["members"][0]))
                if representative.is_empty():
                    continue
                var distance: int = Nav.manhattan(Vector2i(int(representative["x"]), int(representative["y"])),
                    Vector2i(int(house["x"]), int(house["y"])))
                # A resident cannot be assigned an unreachable distant house.
                if distance > HOME_ASSIGN_RADIUS:
                    continue
                var score: int = distance * 10000 + int(family["id"])
                if score < best:
                    best = score
                    selected = family
            if selected.is_empty():
                break
            selected["home_id"] = home_id
            for id in selected["members"]:
                var person := living_person(world, int(id))
                if not person.is_empty():
                    person["home_id"] = home_id
            remaining -= member_count(world, selected)

func reconcile(world: RefCounted) -> void:
    if not dirty and int(world.tick) % 60 != 0:
        return
    dirty = false
    for i in range(families.size() - 1, -1, -1):
        var family: Dictionary = families[i]
        var survivors: Array = []
        for id in family["members"]:
            if not living_person(world, int(id)).is_empty():
                survivors.append(int(id))
        family["members"] = survivors
        if survivors.is_empty():
            families.remove_at(i)
            continue
        var home := house_by_id(world, int(family["home_id"]))
        if home.is_empty() or int(home["nation"]) != int(family["nation"]):
            family["home_id"] = 0
        var old_steward: int = int(family["steward_id"])
        if living_person(world, old_steward).is_empty():
            family["steward_id"] = pick_steward(world, family)
            var witness := living_person(world, int(survivors[0]))
            if not witness.is_empty():
                world.lifecycle.append_event(world, witness, "steward_succeeded",
                    {"household_id": int(family["id"]), "steward_id": int(family["steward_id"])})
        for id in survivors:
            var person := living_person(world, int(id))
            person["home_id"] = int(family["home_id"])
    assign_homes(world)
    # Real guardian availability is separate from recorded biological ancestry.
    var unprotected: Array = []
    for family in families:
        for id in family["members"]:
            var child := living_person(world, int(id))
            if child.is_empty() or not world.lifecycle.is_dependent(child):
                continue
            var guardian := living_person(world, int(child["guardian_id"]))
            if guardian.is_empty() or int(guardian["household_id"]) != int(family["id"]):
                child["guardian_id"] = pick_guardian(world, family)
                child["carried_by"] = 0
                if int(child["guardian_id"]) <= 0:
                    unprotected.append(child)
    for child in unprotected:
        adopt_unprotected(world, child)

func care_step(world: RefCounted, person: Dictionary, mind: Dictionary) -> bool:
    if str(person["life_stage"]) not in ["adult", "elder"]:
        return false
    var family := family_for(int(person["household_id"]))
    if family.is_empty():
        return false
    var guardian_id: int = int(person["id"])
    for id in family["members"]:
        var child := living_person(world, int(id))
        if child.is_empty() or str(child["life_stage"]) != "infant" or int(child["guardian_id"]) != guardian_id:
            continue
        var here := Vector2i(int(person["x"]), int(person["y"]))
        var child_pos := Vector2i(int(child["x"]), int(child["y"]))
        var house := house_by_id(world, int(family["home_id"]))
        var home := child_pos if house.is_empty() else Vector2i(int(house["x"]), int(house["y"]))
        var needs_visit: bool = int(world.tick) - int(child["last_care_tick"]) >= CARE_INTERVAL
        var needs_pickup: bool = not house.is_empty() and Nav.manhattan(child_pos, home) > 1
        var in_danger: bool = Nav.danger_near(world, child_pos)
        if not needs_visit and not needs_pickup and not in_danger and int(child["carried_by"]) != guardian_id:
            continue
        if int(child["carried_by"]) != guardian_id:
            if Nav.manhattan(here, child_pos) > 1:
                move_guardian(world, person, mind, child_pos)
                return true
            if needs_pickup or in_danger:
                child["carried_by"] = guardian_id
                # Pickup is only possible in the same/adjacent cell.
                child["x"] = here.x
                child["y"] = here.y
                world.ai_context.moved(child, child_pos)
                child_pos = here
                mind["route"] = []
        if int(child["carried_by"]) == guardian_id:
            var safe_home := home
            if house.is_empty() or not world.is_walkable(home.x, home.y) or Nav.danger_near(world, home):
                safe_home = here  # remain with guardian if shelter is unsafe
            if here != safe_home:
                move_guardian(world, person, mind, safe_home)
                var after := Vector2i(int(person["x"]), int(person["y"]))
                child["x"] = after.x
                child["y"] = after.y
                world.ai_context.moved(child, child_pos)
                return true
            child["carried_by"] = 0
        child["last_care_tick"] = int(world.tick)
        child["care_visits"] = int(child["care_visits"]) + 1
        return true
    return false

func move_guardian(world: RefCounted, guardian: Dictionary, mind: Dictionary, target: Vector2i) -> void:
    var start := Vector2i(int(guardian["x"]), int(guardian["y"]))
    if start == target:
        return
    var next := Nav.next_step(world, guardian, mind, target)
    if next != start:
        guardian["x"] = next.x
        guardian["y"] = next.y
        world.ai_context.moved(guardian, start)

func snapshot() -> Dictionary:
    return {"version": 1, "families": families.duplicate(true), "next_id": next_id}

func load_state(world: RefCounted, raw: Variant) -> bool:
    if raw == null:
        # Existing saves never defined household IDs. Establish one household
        # per living founder without rewriting age or parentage.
        families.clear()
        next_id = 1
        for person in world.citizens:
            if int(person["hp"]) > 0:
                on_citizen_added(world, person)
            else:
                person["household_id"] = 0
                person["home_id"] = 0
                person["guardian_id"] = 0
                person["carried_by"] = 0
                person["last_care_tick"] = int(world.tick)
                person["care_visits"] = 0
        return true
    if not raw is Dictionary or int(raw.get("version", -1)) != 1 or not raw.get("families") is Array:
        return false
    var source: Array = raw["families"]
    if source.size() > MAX_HOUSEHOLDS:
        return false
    var people: Dictionary = {}
    for citizen in world.citizens:
        people[int(citizen["id"])] = citizen
    var family_ids := {}
    var member_ids := {}
    var incoming: Array[Dictionary] = []
    var max_id := 0
    for entry in source:
        if not entry is Dictionary or not entry.get("members") is Array:
            return false
        var id := int(entry.get("id", 0))
        var nation := int(entry.get("nation", -1))
        if id <= 0 or family_ids.has(id) or nation not in [0, 1]:
            return false
        family_ids[id] = true
        max_id = maxi(max_id, id)
        var members: Array = []
        for person_id in entry["members"]:
            var pid := int(person_id)
            if not people.has(pid) or member_ids.has(pid) or int(people[pid]["nation"]) != nation or int(people[pid]["hp"]) <= 0:
                return false
            member_ids[pid] = true
            members.append(pid)
        if members.is_empty():
            return false
        incoming.append({"id": id, "nation": nation, "members": members,
            "home_id": maxi(0, int(entry.get("home_id", 0))),
            "steward_id": maxi(0, int(entry.get("steward_id", 0))),
            "founded_tick": int(entry.get("founded_tick", 0))})
    for citizen in world.citizens:
        if int(citizen["hp"]) > 0 and not member_ids.has(int(citizen["id"])):
            return false
    families = incoming
    next_id = maxi(max_id + 1, int(raw.get("next_id", 1)))
    for family in families:
        for id in family["members"]:
            var person: Dictionary = people[int(id)]
            person["household_id"] = int(family["id"])
            person["home_id"] = int(family["home_id"])
            person["guardian_id"] = int(person.get("guardian_id", 0))
            person["carried_by"] = int(person.get("carried_by", 0))
            person["last_care_tick"] = int(person.get("last_care_tick", world.tick))
            person["care_visits"] = maxi(0, int(person.get("care_visits", 0)))
    dirty = true
    return true
