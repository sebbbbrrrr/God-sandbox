extends RefCounted
# Building rules reuse C1's local capability vocabulary and D1 item identifiers.
const Eras = preload("res://scripts/ai/era_occupations.gd")
var definitions: Dictionary = {}
var errors: Array[String] = []

func _init() -> void:
    var raw: Variant = normalize(JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/phase_a.json")))
    if not raw is Dictionary or not raw.get("buildings") is Array:
        errors.append("Invalid building catalogue")
        return
    for row in raw["buildings"]:
        if not row is Dictionary or str(row.get("id", "")) == "" or definitions.has(row["id"]):
            errors.append("Invalid or duplicate building")
            continue
        definitions[str(row["id"])] = row

func definition(id: String) -> Dictionary:
    return definitions.get(id, {})

static func normalize(value: Variant) -> Variant:
    if value is Dictionary:
        for key in value:
            value[key] = normalize(value[key])
    elif value is Array:
        for i in range(value.size()):
            value[i] = normalize(value[i])
    elif typeof(value) == TYPE_FLOAT and is_finite(value) and value == floor(value):
        return int(value)
    return value

func validate(items: Dictionary) -> Array[String]:
    var result: Array[String] = errors.duplicate()
    for row in definitions.values():
        var total = {}
        var labour = 0
        for stage in row["stages"]:
            labour += int(stage["labour"])
            if int(stage["labour"]) <= 0:
                result.append("Nonpositive labour: " + str(row["id"]))
            for material in stage["materials"]:
                total[material] = int(total.get(material, 0)) + int(stage["materials"][material])
        if total != row["materials"] or labour != int(row["labour"]):
            result.append("Stage totals: " + str(row["id"]))
        for item in row["materials"]:
            if not items.has(item) or int(row["materials"][item]) <= 0:
                result.append("Invalid material: " + str(item))
        for age in row["supported_ages"]:
            if int(age) < 1 or int(age) > Eras.ERAS.size():
                result.append("Invalid C1 era")
    return result

func eligible(world: RefCounted, nation: int, row: Dictionary, context: Dictionary = {}) -> bool:
    if row.is_empty() or (nation not in [0, 1] and world.settlements.get_record(nation).is_empty()):
        return false
    if row.get("supported_ages", []).size() < 11 and local_age(world, nation) not in row.get("supported_ages", []):
        return false
    # No global age unlock: actual local techniques always remain mandatory.
    for key in ["technology_prerequisites", "knowledge_prerequisites"]:
        for tech in row.get(key, []):
            if not (world.occupations.has_capability(world, nation, str(tech)) if nation in [0, 1] else bool(world.settlements.get_record(nation)["knowledge"].get(str(tech), false))):
                return false
    for dimension in ["regions", "climates", "cultures", "religions"]:
        var allowed: Array = row.get("variations", {}).get(dimension, [])
        if not allowed.is_empty() and str(context.get(dimension, "")) not in allowed:
            return false
    return true

func worker_eligible(world: RefCounted, person: Dictionary, row: Dictionary) -> bool:
    if int(person.get("hp", 0)) <= 0 or world.lifecycle.is_dependent(person):
        return false
    if not eligible(world, world.settlements.sid(person), row,
            world.construction.settlement_context.get(str(world.settlements.sid(person)), {})):
        return false
    for skill in row.get("skills", {}):
        if world.occupations.skill_tier(person, str(skill)) < int(row["skills"][skill]):
            return false
    for tool in row.get("tools", []):
        var serial = str(world.toolmaking.equipped.get(str(person["id"]), ""))
        var instance: Dictionary = world.toolmaking.instances.get(serial, {})
        if str(instance.get("item_id", "")) != str(tool) or int(instance.get("condition", 0)) <= 0:
            return false
    return true

func local_age(world: RefCounted, nation: int) -> int:
    # C1 has no global date-driven era. Report the local evidence floor.
    var age := 1
    for role in world.occupations.definitions.values():
        var tech := str(role["tech"])
        if tech != "" and world.occupations.has_capability(world, nation, tech):
            age = maxi(age, int(role["first_era"]))
    return age
