extends RefCounted
# Civilisation Phase C1: evidence-led work and apprenticeship. Every occupation
# has a historical *first appearance*, not a calendar unlock or a universal
# national career. Later jobs need actual adopted techniques AND facilities.
const Nav = preload("res://scripts/ai/navigation.gd")
const Calendar = preload("res://scripts/ai/sim_calendar.gd")
const Relations = preload("res://scripts/ai/relationships.gd")
const TIER_XP := [0, 50, 160, 360, 700]
const TIER_NAMES := ["novice", "practised", "skilled", "expert", "master"]
const MAX_SKILLS := 24
const MAX_EVENTS := 128
const PLANNING_INTERVAL := 180
const TRAIN_INTERVAL := 90
const MENTOR_MIN_XP := 50
const MAX_TRAIN_RANGE := 8

# Each row: id, first-era (1..11), domain, prerequisite tech, required
# facility, local context, playable. A role stays available in later eras
# when its actual material prerequisites still exist.
const ERAS := [
    "I - Early Stone Age", "II - Agricultural Age", "III - Bronze Age",
    "IV - Iron and Classical Age", "V - Medieval Engineering Age",
    "VI - Early Scientific Age", "VII - Industrial Age",
    "VIII - Electrical and Modern Age", "IX - Information Age",
    "X - Advanced Technological Age", "XI - Far Future"]
const ROLE_ROWS := [
    ["forager",1,"agriculture","","","forest_meadow",true],
    ["fisher",1,"agriculture","","","coast",true],
    ["woodcutter",1,"materials","","","forest",true],
    ["quarry_worker",1,"materials","","","mountain",true],
    ["shelter_builder",1,"construction","","","house_project",true],
    ["carer",1,"medicine","","","dependent",true],
    ["food_courier",1,"transport","","house","",true],
    ["oral_mentor",1,"communication","","","",true],
    ["hunter",1,"agriculture","hunting_tools","","wildlife",false],
    ["stone_toolmaker",1,"materials","stone_working","tool_area","",false],
    ["ceremony_facilitator",1,"communication","","gathering_site","",false],
    ["crop_farmer",2,"agriculture","cultivation","farm","meadow",true],
    ["herder",2,"agriculture","domestication","pasture","grassland",false],
    ["potter",2,"materials","pottery","kiln","clay",false],
    ["basket_weaver",2,"manufacturing","weaving","workshop","",false],
    ["irrigation_keeper",2,"agriculture","irrigation","canal","water",false],
    ["granary_keeper",2,"agriculture","storage","granary","",false],
    ["bronze_smith",3,"materials","bronze_working","smelter","ore",false],
    ["copper_miner",3,"materials","copper_mining","mine","ore",false],
    ["scribe",3,"communication","writing","archive","",false],
    ["caravan_trader",3,"transport","caravan_trade","market","",false],
    ["urban_mason",3,"construction","masonry","mason_yard","",false],
    ["temple_caretaker",3,"communication","ritual_institution","temple","",false],
    ["iron_smith",4,"materials","iron_working","forge","ore",false],
    ["road_engineer",4,"construction","road_engineering","roadworks","",false],
    ["physician",4,"medicine","clinical_practice","clinic","",false],
    ["aqueduct_builder",4,"construction","water_engineering","aqueduct","water",false],
    ["market_clerk",4,"communication","accounting","market","",false],
    ["millwright",5,"manufacturing","water_power","mill","water",false],
    ["guild_craftsperson",5,"manufacturing","guild_craft","guild_hall","",false],
    ["fortification_mason",5,"construction","fortification","fort","",false],
    ["shipwright",5,"transport","shipbuilding","shipyard","coast",false],
    ["merchant",5,"transport","market_networks","market","",false],
    ["monastic_scholar",5,"communication","formal_texts","monastic_library","",false],
    ["printer",6,"communication","printing","printshop","",false],
    ["instrument_maker",6,"manufacturing","precision_tools","instrument_workshop","",false],
    ["navigator",6,"transport","navigation","harbour","coast",false],
    ["scientific_researcher",6,"science","experimental_method","laboratory","",false],
    ["cartographer",6,"communication","surveying","cartography_office","",false],
    ["factory_worker",7,"manufacturing","mechanisation","factory","",false],
    ["steam_engineer",7,"energy","steam_engine","engine_works","fuel",false],
    ["rail_conductor",7,"transport","railways","rail_station","",false],
    ["coal_miner",7,"materials","coal_mining","coal_mine","coal",false],
    ["machine_fitter",7,"manufacturing","machine_tools","machine_shop","",false],
    ["electrician",8,"energy","electricity","electrical_workshop","",false],
    ["power_technician",8,"energy","electrical_grid","power_station","",false],
    ["automotive_mechanic",8,"transport","automobiles","garage","",false],
    ["aircraft_pilot",8,"transport","aviation","airfield","",false],
    ["hospital_clinician",8,"medicine","modern_medicine","hospital","",false],
    ["community_mediator",8,"communication","civic_mediation","civic_center","",false],
    ["software_engineer",9,"computing","electronic_computing","computer_lab","",false],
    ["network_engineer",9,"communication","digital_networks","network_hub","",false],
    ["robotics_technician",9,"manufacturing","robotics","robotics_lab","",false],
    ["data_scientist",9,"computing","digital_analysis","computing_center","",false],
    ["renewables_engineer",9,"energy","renewable_power","renewables_plant","",false],
    ["digital_ethicist",9,"science","digital_ethics","research_institute","",false],
    ["fusion_engineer",10,"energy","fusion_power","fusion_plant","",false],
    ["biotechnology_researcher",10,"medicine","advanced_biotechnology","biotech_lab","",false],
    ["autonomous_systems_operator",10,"computing","advanced_automation","automated_plant","",false],
    ["materials_scientist",10,"materials","engineered_composites","materials_lab","",false],
    ["vertical_farmer",10,"agriculture","controlled_farming","vertical_farm","",false],
    ["orbital_engineer",11,"transport","orbital_industry","orbital_yard","",false],
    ["habitat_architect",11,"construction","orbital_habitats","habitat_fabricator","",false],
    ["astrogeologist",11,"science","offworld_geology","space_research_base","",false],
    ["planetary_ecologist",11,"science","planetary_ecology","planetary_lab","",false],
    ["offworld_logistician",11,"transport","interplanetary_transport","spaceport","",false]
]
const MAX_CAPABILITIES := 64

var definitions: Dictionary = {}
var skills_by_id: Dictionary = {}
var apprenticeships: Dictionary = {} # learner ID -> {teacher_id, role, next_tick}
var adopted_by_settlement: Dictionary = {} # "nation:capital_cell" -> {tech_id: true}
var career_events: Array[Dictionary] = []
var next_event_id := 1
var next_plan_tick := 1

func _init() -> void:
    for row in ROLE_ROWS:
        definitions[str(row[0])] = {"id": str(row[0]), "first_era": int(row[1]),
            "domain": str(row[2]), "tech": str(row[3]), "facility": str(row[4]),
            "context": str(row[5]), "implemented": bool(row[6])}

func role(id: String) -> Dictionary:
    return definitions.get(id, {})

func settlement_key(world: RefCounted, nation: int) -> String:
    if nation not in [0, 1]:
        return ""
    var capital: Vector2i = world.capitals[nation]
    if capital.x < 0:
        return ""
    return str(nation) + ":" + str(world.index_of(capital.x, capital.y))

func has_capability(world: RefCounted, nation: int, tech: String) -> bool:
    if tech == "":
        return true
    if nation not in [0, 1]:
        return false
    if tech in ["cultivation", "irrigation"]:
        return bool(world.food.techniques[nation].get(tech, false))
    var key := settlement_key(world, nation)
    return key != "" and bool(adopted_by_settlement.get(key, {}).get(tech, false))

func grant_capability(world: RefCounted, nation: int, tech: String, evidence: String) -> bool:
    # For the upcoming research system: no capability is awarded from age,
    # class or calendar. Callers must supply an attributable experiment,
    # teaching/trade or institutional event. Future releases will validate
    # event IDs and the physical production preconditions.
    if nation not in [0, 1] or evidence not in ["experiment", "trade", "teaching", "institution"]:
        return false
    var recognised := false
    for definition in definitions.values():
        if str(definition["tech"]) == tech and tech != "":
            recognised = true
            break
    if not recognised:
        return false
    if tech in ["cultivation", "irrigation"]:
        return world.food.set_technique(nation, tech, true)
    var key := settlement_key(world, nation)
    if key == "":
        return false
    var known: Dictionary = adopted_by_settlement.get(key, {})
    if known.size() >= MAX_CAPABILITIES and not known.has(tech):
        return false
    known[tech] = true
    adopted_by_settlement[key] = known
    return true

func lose_capability(world: RefCounted, nation: int, tech: String, reason: String) -> bool:
    # Future collapse / specialist-death events can withdraw actually lost
    # manufacturing knowledge without deleting citizens' past skills.
    if nation not in [0, 1] or reason not in [
            "knowledge_lost", "catastrophe", "infrastructure_lost"]:
        return false
    if tech in ["cultivation", "irrigation"]:
        return world.food.set_technique(nation, tech, false)
    var key := settlement_key(world, nation)
    if key == "" or not adopted_by_settlement.has(key):
        return false
    var skills: Dictionary = adopted_by_settlement[key]
    if not skills.has(tech):
        return false
    skills.erase(tech)
    return true

func facility_present(world: RefCounted, nation: int, facility: String) -> bool:
    if facility == "":
        return true
    if facility == "farm":
        for farm in world.food.farms:
            if int(farm["nation"]) == nation:
                return true
        return false
    if facility == "house":
        for house in world.construction.houses:
            if int(house["nation"]) == nation and int(house.get("capacity", 0)) > 0:
                return true
        return false
    # Only actual specialised building entities unlock advanced roles.
    # The existing town tile is not a forge, factory or research laboratory.
    for house in world.construction.houses:
        if int(house["nation"]) == nation and str(house.get("type", "home")) == facility:
            return true
    return false

func enabled(world: RefCounted, nation: int, id: String) -> bool:
    var r := role(id)
    return not r.is_empty() and bool(r["implemented"]) and \
        has_capability(world, nation, str(r["tech"])) and \
        facility_present(world, nation, str(r["facility"]))

func context_exists(world: RefCounted, nation: int, context: String) -> bool:
    if context == "":
        return true
    if nation not in [0, 1]:
        return false
    var center: Vector2i = world.capitals[nation]
    if center.x < 0:
        return false
    match context:
        "house_project":
            return not world.construction.project_for(nation).is_empty()
        "dependent":
            for person in world.citizens:
                if int(person["nation"]) == nation and int(person["hp"]) > 0 and \
                        int(person.get("guardian_id", 0)) > 0:
                    return true
            return false
        "meadow":
            for farm in world.food.farms:
                if int(farm["nation"]) == nation:
                    return true
            return false
    for dy in range(-12, 13):
        for dx in range(-12, 13):
            if absi(dx) + absi(dy) > 12:
                continue
            var cell := center + Vector2i(dx, dy)
            if world.index_of(cell.x, cell.y) < 0:
                continue
            var terrain: int = world.at(cell.x, cell.y)
            match context:
                "forest":
                    if terrain == world.FOREST:
                        return true
                "forest_meadow":
                    if terrain in [world.FOREST, world.MEADOW]:
                        return true
                "mountain":
                    if terrain == world.MOUNTAIN:
                        return true
                "coast":
                    if world.food.source_kind(world, cell) == "fish":
                        return true
                "water":
                    if terrain in [world.BEACH, world.OCEAN]:
                        return true
    return false

func available_roles(world: RefCounted, nation: int) -> Array[String]:
    var result: Array[String] = []
    for id in definitions:
        var entry: Dictionary = definitions[id]
        if enabled(world, nation, str(id)) and context_exists(world, nation, str(entry["context"])):
            result.append(str(id))
    result.sort()
    return result

func era_summary(world: RefCounted, nation: int) -> Dictionary:
    # Descriptive evidence only: never drives skill/occupation unlocking.
    var top := 1
    var titles: Array[String] = []
    for id in available_roles(world, nation):
        var entry := role(id)
        top = maxi(top, int(entry["first_era"]))
        titles.append(id)
    return {"highest_demonstrated_era": top, "label": ERAS[top - 1],
        "playable_roles": titles, "note": "capability summary, not calendar unlock"}

func new_record() -> Dictionary:
    return {"xp": {}, "last_practice": {}, "current": "", "preference": "",
        "work_actions": 0, "last_choice_tick": 0}

func register_citizen(person: Dictionary, tick: int) -> void:
    var id := str(person["id"])
    if not skills_by_id.has(id):
        skills_by_id[id] = new_record()
    person["occupation_id"] = str(skills_by_id[id]["current"])

func record_for(person: Dictionary) -> Dictionary:
    return skills_by_id.get(str(person["id"]), {})

func xp_for(person: Dictionary, id: String) -> int:
    return int(record_for(person).get("xp", {}).get(id, 0))

func skill_tier(person: Dictionary, id: String) -> int:
    var xp: int = xp_for(person, id)
    var result := 0
    for i in range(1, TIER_XP.size()):
        if xp >= TIER_XP[i]:
            result = i
    return result

func append_event(world: RefCounted, person: Dictionary, type: String, extra: Dictionary) -> void:
    var row := {"id": next_event_id, "tick": int(world.tick), "citizen_id": int(person["id"]),
        "kind": type}
    for key in extra:
        row[key] = extra[key]
    career_events.append(row)
    next_event_id += 1
    if career_events.size() > MAX_EVENTS:
        career_events.pop_front()

func credit(world: RefCounted, person: Dictionary, id: String, quantity: int, practice: bool) -> bool:
    if int(person["hp"]) <= 0 or not enabled(world, int(person["nation"]), id) or quantity <= 0:
        return false
    var rec: Dictionary = record_for(person)
    if rec.is_empty():
        register_citizen(person, world.tick)
        rec = record_for(person)
    var xp: Dictionary = rec["xp"]
    var last: Dictionary = rec["last_practice"]
    if not xp.has(id) and xp.size() >= MAX_SKILLS:
        return false # fail closed rather than silently erase professional history
    var old: int = int(xp.get(id, 0))
    var before: int = tier_for_xp(old)
    xp[id] = mini(1000, old + mini(quantity, 6))
    last[id] = int(world.tick)
    if practice:
        rec["work_actions"] = mini(2147483647, int(rec["work_actions"]) + 1)
        if str(rec["current"]) != id:
            rec["current"] = id
            person["occupation_id"] = id
            append_event(world, person, "occupation_changed", {"role": id})
    if tier_for_xp(int(xp[id])) > before:
        append_event(world, person, "skill_improved",
            {"role": id, "tier": tier_for_xp(int(xp[id]))})
    return true

func tier_for_xp(xp: int) -> int:
    var result := 0
    for i in range(1, TIER_XP.size()):
        if xp >= TIER_XP[i]:
            result = i
    return result

func on_real_work(world: RefCounted, person: Dictionary, id: String, units: int = 1) -> bool:
    # Called ONLY from validated physical extraction, hauling, building or
    # care completion. Mere passage of time gives no expertise.
    return credit(world, person, id, maxi(1, mini(6, units * 2)), true)

func apprenticeship_available(world: RefCounted, teacher: Dictionary,
        student: Dictionary, id: String) -> bool:
    if teacher.is_empty() or student.is_empty() or int(teacher["id"]) == int(student["id"]):
        return false
    if int(teacher["hp"]) <= 0 or int(student["hp"]) <= 0 or \
            int(teacher["nation"]) != int(student["nation"]):
        return false
    if world.calendar.age_years(int(teacher["birth_tick"]), world.tick) < 18 or \
            world.calendar.age_years(int(student["birth_tick"]), world.tick) < 13:
        return false
    if not enabled(world, int(student["nation"]), id) or xp_for(teacher, id) < MENTOR_MIN_XP:
        return false
    if xp_for(student, id) >= xp_for(teacher, id):
        return false
    return Nav.manhattan(Vector2i(int(teacher["x"]), int(teacher["y"])),
        Vector2i(int(student["x"]), int(student["y"]))) <= MAX_TRAIN_RANGE

func begin_apprenticeship(world: RefCounted, teacher_id: int, student_id: int,
        occupation: String) -> bool:
    var teacher: Dictionary = world.ai_context.people.get(teacher_id, {})
    var student: Dictionary = world.ai_context.people.get(student_id, {})
    if not apprenticeship_available(world, teacher, student, occupation):
        return false
    for link in apprenticeships.values():
        if int(link["teacher_id"]) == teacher_id:
            return false # one learner per mentor in C1
    apprenticeships[str(student_id)] = {
        "teacher_id": teacher_id, "student_id": student_id, "occupation": occupation,
        "next_tick": int(world.tick) + TRAIN_INTERVAL, "lessons": 0}
    append_event(world, teacher, "apprenticeship_started",
        {"learner_id": student_id, "role": occupation})
    return true

func training_step(world: RefCounted, mentor: Dictionary, mind: Dictionary) -> bool:
    if int(mentor["hp"]) <= 0 or int(mentor.get("hunger", 0)) >= 35:
        return false
    for student_key in apprenticeships.keys():
        var link: Dictionary = apprenticeships[student_key]
        if int(link["teacher_id"]) != int(mentor["id"]) or \
                int(world.tick) < int(link["next_tick"]):
            continue
        var pupil: Dictionary = world.ai_context.people.get(int(student_key), {})
        var profession := str(link["occupation"])
        if not apprenticeship_available(world, mentor, pupil, profession):
            apprenticeships.erase(student_key)
            return false
        if world.food.jobs.has(str(mentor["id"])) or world.construction.jobs.has(str(mentor["id"])):
            return false # finish actual carried cargo before teaching
        var start := Vector2i(int(mentor["x"]), int(mentor["y"]))
        var goal := Vector2i(int(pupil["x"]), int(pupil["y"]))
        if Nav.manhattan(start, goal) > 1:
            var next: Vector2i = Nav.next_step(world, mentor, mind, goal)
            if next != start:
                mentor["x"] = next.x
                mentor["y"] = next.y
                world.ai_context.moved(mentor, start)
            return true
        if xp_for(pupil, profession) + 3 > xp_for(mentor, profession):
            apprenticeships.erase(student_key)
            return false
        credit(world, pupil, profession, 3, false)
        credit(world, mentor, "oral_mentor", 1, true)
        link["lessons"] = int(link["lessons"]) + 1
        link["next_tick"] = int(world.tick) + TRAIN_INTERVAL
        append_event(world, mentor, "lesson_taught",
            {"learner_id": int(pupil["id"]), "role": profession})
        return true
    return false

func retire_invalid_apprenticeships(world: RefCounted) -> void:
    for key in apprenticeships.keys():
        var link: Dictionary = apprenticeships[key]
        var mentor: Dictionary = world.ai_context.people.get(int(link["teacher_id"]), {})
        var pupil: Dictionary = world.ai_context.people.get(int(link["student_id"]), {})
        if mentor.is_empty() or pupil.is_empty() or \
                int(mentor["hp"]) <= 0 or int(pupil["hp"]) <= 0 or \
                not enabled(world, int(pupil["nation"]), str(link["occupation"])):
            apprenticeships.erase(key)

func auto_apprenticeship(world: RefCounted) -> void:
    # Teaching emerges only where a capable, interested adult has an actually
    # observed social relationship with a reachable eligible pupil.
    var occupied_teachers := {}
    for link in apprenticeships.values():
        occupied_teachers[str(link["teacher_id"])] = true
    for teacher in world.citizens:
        if int(teacher["hp"]) <= 0 or occupied_teachers.has(str(teacher["id"])) or                 world.calendar.age_years(int(teacher["birth_tick"]), world.tick) < 18:
            continue
        var rec := record_for(teacher)
        if rec.is_empty():
            continue
        var taught := ""
        var most_xp := MENTOR_MIN_XP - 1
        for skill_id in rec["xp"]:
            var xp: int = int(rec["xp"][skill_id])
            if xp > most_xp and enabled(world, int(teacher["nation"]), str(skill_id)):
                most_xp = xp
                taught = str(skill_id)
        if taught == "":
            continue
        var teacher_mind: Dictionary = world.citizen_ai_by_id.get(str(teacher["id"]), {})
        if teacher_mind.is_empty():
            continue
        for pupil in world.ai_context.nearby(world, teacher):
            if apprenticeships.has(str(pupil["id"])) or                     not apprenticeship_available(world, teacher, pupil, taught):
                continue
            var tie := Relations.find(teacher_mind, int(pupil["id"]))
            var student_mind: Dictionary = world.citizen_ai_by_id.get(str(pupil["id"]), {})
            var reverse := Relations.find(student_mind, int(teacher["id"])) if not student_mind.is_empty() else {}
            if tie.is_empty() or reverse.is_empty() or int(tie["trust"]) < 3 or                     int(reverse["trust"]) < 3:
                continue
            if begin_apprenticeship(world, int(teacher["id"]), int(pupil["id"]), taught):
                occupied_teachers[str(teacher["id"])] = true
                break

func on_tick(world: RefCounted) -> void:
    if int(world.tick) % 90 == 0:
        retire_invalid_apprenticeships(world)
    if int(world.tick) % Calendar.TICKS_PER_YEAR == 0:
        for record in skills_by_id.values():
            for skill_id in record["xp"]:
                if int(world.tick) - int(record["last_practice"].get(skill_id, world.tick)) > 5 * Calendar.TICKS_PER_YEAR:
                    record["xp"][skill_id] = maxi(0, int(record["xp"][skill_id]) - 2)
    if int(world.tick) < next_plan_tick:
        return
    next_plan_tick = int(world.tick) + PLANNING_INTERVAL
    var local: Array = [available_roles(world, 0), available_roles(world, 1)]
    auto_apprenticeship(world)
    for person in world.citizens:
        if int(person["hp"]) <= 0:
            continue
        var record := record_for(person)
        if record.is_empty():
            register_citizen(person, world.tick)
            record = record_for(person)
        if world.calendar.age_years(int(person["birth_tick"]), world.tick) < 18:
            record["preference"] = ""
            continue
        var nation: int = int(person["nation"])
        var old_role := str(record["preference"])
        var choice := old_role if old_role in local[nation] else ""
        var best_score := -2147483647
        for role_id in local[nation]:
            var proposed := role(str(role_id))
            if str(proposed["id"]) in ["oral_mentor", "carer"] and \
                    int(record["xp"].get(str(role_id), 0)) == 0:
                continue
            if str(proposed["id"]) == "shelter_builder" and \
                    world.construction.project_for(nation).is_empty():
                continue
            var score: int = int(record["xp"].get(str(role_id), 0)) / 4
            var mind: Dictionary = world.citizen_ai_by_id.get(str(person["id"]), {})
            if not mind.is_empty():
                score += (int(mind["personality"]["diligence"]) +
                    int(mind["personality"]["curiosity"])) / 10
            if str(role_id) == "forager":
                score += 25 if world.food.total(world.food.depots[nation]) < 8 else 10
            if str(role_id) == "shelter_builder":
                score += 15
            if str(role_id) == "crop_farmer":
                score += 20
            if str(role_id) == old_role:
                score += 8 # stable job preference, not permanent occupation lock
            score += posmod(int(person["id"]) * 17 + str(role_id).hash(), 7)
            if score > best_score or (score == best_score and str(role_id) < choice):
                best_score = score
                choice = str(role_id)
        record["preference"] = choice
        record["last_choice_tick"] = int(world.tick)

func remove_archived(person_id: int) -> Dictionary:
    var key := str(person_id)
    var data: Dictionary = skills_by_id.get(key, {})
    var summary := {"occupation": str(data.get("current", "")),
        "mastered": []}
    for id in data.get("xp", {}):
        if int(data["xp"][id]) >= TIER_XP[4]:
            summary["mastered"].append(str(id))
    skills_by_id.erase(key)
    apprenticeships.erase(key)
    for pupil_key in apprenticeships.keys():
        if int(apprenticeships[pupil_key]["teacher_id"]) == person_id:
            apprenticeships.erase(pupil_key)
    return summary

func snapshot() -> Dictionary:
    return {"version": 1, "skills_by_id": skills_by_id.duplicate(true),
        "apprenticeships": apprenticeships.duplicate(true),
        "adopted_by_settlement": adopted_by_settlement.duplicate(true),
        "career_events": career_events.duplicate(true),
        "next_event_id": next_event_id, "next_plan_tick": next_plan_tick}

func load_state(world: RefCounted, raw: Variant) -> bool:
    if raw == null:
        for person in world.citizens:
            register_citizen(person, world.tick)
        return true
    if not raw is Dictionary or int(raw.get("version", -1)) != 1:
        return false
    for field in ["skills_by_id", "apprenticeships", "adopted_by_settlement"]:
        if not raw.get(field) is Dictionary:
            return false
    if not raw.get("career_events") is Array or raw["career_events"].size() > MAX_EVENTS:
        return false
    var people := {}
    for person in world.citizens:
        people[str(person["id"])] = person
    skills_by_id.clear()
    for key in raw["skills_by_id"]:
        var record: Variant = raw["skills_by_id"][key]
        if not people.has(str(key)) or not record is Dictionary or \
                not record.get("xp", {}) is Dictionary or not record.get("last_practice", {}) is Dictionary:
            return false
        var data := new_record()
        for skill_id in record["xp"]:
            if not definitions.has(str(skill_id)) or data["xp"].size() >= MAX_SKILLS:
                return false
            data["xp"][str(skill_id)] = clampi(int(record["xp"][skill_id]), 0, 1000)
            data["last_practice"][str(skill_id)] = maxi(0, int(
                record["last_practice"].get(skill_id, 0)))
        var current: String = str(record.get("current", ""))
        var preference: String = str(record.get("preference", ""))
        if current != "" and not definitions.has(current):
            return false
        data["current"] = current
        data["preference"] = preference if preference == "" or definitions.has(preference) else ""
        data["work_actions"] = maxi(0, int(record.get("work_actions", 0)))
        data["last_choice_tick"] = int(record.get("last_choice_tick", world.tick))
        skills_by_id[str(key)] = data
        people[str(key)]["occupation_id"] = current
    for key in people:
        if not skills_by_id.has(key):
            register_citizen(people[key], world.tick)
    apprenticeships.clear()
    for key in raw["apprenticeships"]:
        var entry: Variant = raw["apprenticeships"][key]
        if not entry is Dictionary or not people.has(str(key)) or \
                not people.has(str(entry.get("teacher_id", ""))) or \
                not definitions.has(str(entry.get("occupation", ""))):
            return false
        apprenticeships[str(key)] = entry.duplicate(true)
    adopted_by_settlement.clear()
    for key in raw["adopted_by_settlement"]:
        var caps: Variant = raw["adopted_by_settlement"][key]
        if not caps is Dictionary or caps.size() > MAX_CAPABILITIES:
            return false
        adopted_by_settlement[str(key)] = caps.duplicate(true)
    career_events.clear()
    for event in raw["career_events"]:
        if not event is Dictionary:
            return false
        career_events.append(event.duplicate(true))
    next_event_id = maxi(1, int(raw.get("next_event_id", 1)))
    next_plan_tick = maxi(0, int(raw.get("next_plan_tick", 1)))
    return true
