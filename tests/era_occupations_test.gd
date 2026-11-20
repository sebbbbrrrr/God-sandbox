extends SceneTree
const World = preload("res://scripts/simulation.gd")
const Relations = preload("res://scripts/ai/relationships.gd")
const Calendar = preload("res://scripts/ai/sim_calendar.gd")
const SaveStore = preload("res://scripts/ai/save_store.gd")

func _initialize() -> void:
    var ok := true
    var w = fixture()
    var occupations = w.occupations
    var roles := occupations.definitions
    ok = check(occupations.ERAS.size() == 11 and roles.size() >= 60,
        "complete eleven-era career catalogue has broad cross-domain coverage") and ok
    var era_seen := {}
    for definition in roles.values():
        var era: int = int(definition["first_era"])
        era_seen[era] = true
        ok = check(era >= 1 and era <= 11, "occupation first era in range") and ok
    ok = check(era_seen.size() == 11,
        "every civilisation era contains named occupations") and ok
    ok = check(int(roles["crop_farmer"]["first_era"]) == 2 and
        int(roles["steam_engineer"]["first_era"]) == 7 and
        int(roles["software_engineer"]["first_era"]) == 9 and
        int(roles["orbital_engineer"]["first_era"]) == 11,
        "agricultural, industrial, digital and far-future careers appear in appropriate eras") and ok
    var available: Array[String] = occupations.available_roles(w, 0)
    ok = check("forager" in available and "fisher" in available and
        "woodcutter" in available and "quarry_worker" in available,
        "prehistory supports only physically supported regional livelihoods") and ok
    ok = check("crop_farmer" not in available and "steam_engineer" not in available and
        "software_engineer" not in available,
        "advanced and agricultural roles never appear before their requirements") and ok
    w.tick = Calendar.TICKS_PER_YEAR * 100
    ok = check(occupations.available_roles(w, 0) == available and
        int(occupations.era_summary(w, 0)["highest_demonstrated_era"]) == 1,
        "a century passing does not magically unlock modern professions") and ok
    w.tick = 0
    ok = check(not occupations.grant_capability(w, 0, "steam_engine", "calendar"),
        "bare chronology is not a valid technology-adoption event") and ok
    ok = check(occupations.grant_capability(w, 0, "steam_engine", "experiment") and
        not occupations.enabled(w, 0, "steam_engineer"),
        "even known steam theory cannot create a working engineer without machinery") and ok
    w.food.depots[0]["grain"] = 1
    w.food.produced["grain"] = 1
    ok = check(w.food.set_technique(0, "cultivation") and
        w.food.create_farm(w, 0) and
        occupations.enabled(w, 0, "crop_farmer") and
        int(occupations.era_summary(w, 0)["highest_demonstrated_era"]) == 2,
        "genuine cultivated land and knowledge make an agricultural occupation possible") and ok
    w.food.set_technique(0, "cultivation", false)
    ok = check(not occupations.enabled(w, 0, "crop_farmer") and
        w.food.ready_farm(w, 0).is_empty() and
        int(occupations.era_summary(w, 0)["highest_demonstrated_era"]) == 1,
        "lost cultivation capability removes a farming job without deleting historical skills") and ok
    var worker: Dictionary = w.citizens[0]
    var origin := Vector2i(int(worker["x"]), int(worker["y"]))
    worker["x"] = 15
    worker["y"] = 12
    w.ai_context.moved(worker, origin)
    var job_id: String = str(worker["id"])
    w.food.jobs[job_id] = {"kind": "forage", "nation": 0, "phase": "source",
        "source": [15, 12], "target": [15, 12], "type": "berries", "amount": 0}
    var before := occupations.xp_for(worker, "forager")
    ok = check(w.food.work_step(w, worker, w.citizen_ai_by_id[job_id]) and
        occupations.xp_for(worker, "forager") > before and
        str(worker["occupation_id"]) == "forager" and w.food.ledger_ok(),
        "physically harvesting a finite food source earns matching skill and retains food conservation") and ok
    before = occupations.xp_for(worker, "forager")
    w.tick += 1
    occupations.on_tick(w)
    ok = check(occupations.xp_for(worker, "forager") == before,
        "neither elapsed calendar time nor occupation assignment alone awards skill") and ok
    var teacher: Dictionary = w.citizens[1]
    var pupil: Dictionary = w.citizens[2]
    pupil["birth_tick"] = -15 * Calendar.TICKS_PER_YEAR
    pupil["life_stage"] = "adolescent"
    # Controlled test setup represents an experienced forager with genuine
    # past practice; production grants this XP only through work hooks.
    for i in range(9):
        occupations.credit(w, teacher, "forager", 6, true)
    var teacher_id: int = int(teacher["id"])
    var student_id: int = int(pupil["id"])
    for i in range(3):
        Relations.encounter(w.citizen_ai_by_id[str(teacher_id)], student_id,
            Vector2i(12, 12), w.tick, "friendly")
        Relations.encounter(w.citizen_ai_by_id[str(student_id)], teacher_id,
            Vector2i(12, 12), w.tick, "friendly")
    w.tick = 180
    w.ai_context.begin_tick(w)
    occupations.on_tick(w)
    ok = check(occupations.apprenticeships.has(str(student_id)),
        "observed trust and relevant mentor expertise create a local apprenticeship") and ok
    var student_before := occupations.xp_for(pupil, "forager")
    var tutor_before := occupations.xp_for(teacher, "oral_mentor")
    w.tick = 270
    w.ai_context.begin_tick(w)
    ok = check(occupations.training_step(w, teacher,
        w.citizen_ai_by_id[str(teacher_id)]) and
        occupations.xp_for(pupil, "forager") > student_before and
        occupations.xp_for(teacher, "oral_mentor") > tutor_before,
        "teaching requires a real scheduled mentor action and transfers practical skill") and ok
    var learning_snapshot: Dictionary = w.snapshot()
    var restored = World.from_snapshot(learning_snapshot)
    ok = check(restored != null and restored.snapshot() == learning_snapshot,
        "old AI plus professional expertise, apprenticeship and capability state restore exactly") and ok
    var decoded: Variant = SaveStore.decode(w.prepare_save_bytes())
    var binary = World.from_snapshot(decoded) if decoded is Dictionary else null
    ok = check(binary != null and binary.occupations.snapshot() == occupations.snapshot(),
        "binary save preserves exact skill and apprenticeship progress") and ok
    if binary != null:
        for i in range(60):
            w.step()
            binary.step()
        ok = check(w.snapshot() == binary.snapshot(),
            "mid-training deterministic continuation after save and load") and ok
    var slow_age = fixture()
    var legacy: Dictionary = slow_age.snapshot()
    legacy.erase("occupations")
    for old_person in legacy["citizens"]:
        old_person.erase("occupation_id")
    var migrated = World.from_snapshot(legacy)
    ok = check(migrated != null and migrated.occupations.skills_by_id.size() ==
        migrated.citizens.size() and
        migrated.occupations.xp_for(migrated.citizens[0], "forager") == 0,
        "pre-career saves migrate with blank skills, not invented professions") and ok
    var pre_archive = fixture()
    var elder: Dictionary = pre_archive.citizens[0]
    pre_archive.occupations.credit(pre_archive, elder, "forager", 6, true)
    var first_id: int = int(elder["id"])
    pre_archive.lifecycle.record_death(pre_archive, elder, "injury")
    pre_archive.tick = Calendar.TICKS_PER_YEAR * 3
    pre_archive.demography.archive_dead(pre_archive)
    ok = check(not pre_archive.occupations.skills_by_id.has(str(first_id)) and
        pre_archive.demography.tombstones.size() == 1 and
        pre_archive.demography.tombstones[0]["career"]["occupation"] == "forager",
        "dead people's active skill records expire but historical occupations survive") and ok
    if ok:
        print("ERA_OCCUPATIONS_TESTS_PASSED")
    quit(0 if ok else 1)

func fixture():
    var w = World.new(1510, false)
    for y in range(7, 22):
        for x in range(7, 23):
            w.set_terrain_cell(x, y, World.MEADOW)
    w.set_terrain_cell(15, 12, World.FOREST)
    w.set_terrain_cell(18, 12, World.MOUNTAIN)
    w.set_terrain_cell(16, 12, World.BEACH)
    w.set_terrain_cell(17, 12, World.OCEAN)
    w.capitals[0] = Vector2i(12, 12)
    for i in range(3):
        w.add_citizen(12, 12, 0)
    w.ai_context.begin_tick(w)
    return w

func check(condition: bool, label: String) -> bool:
    if not condition:
        push_error("FAILED: " + label)
        return false
    print("PASS: " + label)
    return true
