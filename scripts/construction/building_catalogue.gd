extends RefCounted
# Building rules reuse C1's local capability vocabulary and D1 item identifiers.
const Eras = preload("res://scripts/ai/era_occupations.gd")
var definitions: Dictionary = {}
var errors: Array[String] = []
var eras: Array = []
var regions: Dictionary = {}

func _init() -> void:
    var raw: Variant = normalize(JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/catalogue.json")))
    if not raw is Dictionary or not raw.get("buildings") is Array:
        errors.append("Invalid building catalogue")
        return
    eras = raw.get("eras", [])
    regions = raw.get("regions", {})
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
    if eras.size() != 11 or regions.size() != 8:
        result.append("Missing canonical age or regional grammar")
    for row in definitions.values():
        var id := str(row["id"])
        if str(row.get("function","")) not in ["shelter","tool_area","storage","forestry","quarry","farm","market","civic","production","granary","mine","irrigation"]:
            result.append("Unimplemented building function: " + id)
        if int(row.get("primary_age", 0)) not in range(1, 12):
            result.append("Invalid primary age: " + id)
        if str(row.get("purpose", "")) == "" or int(row.get("max_workers", 0)) < 1:
            result.append("Missing function/work capacity: " + id)
        for tool in row.get("tools", []):
            if not items.has(str(tool)): result.append("Unknown tool: " + str(tool))
        for transition in row.get("upgrades", []) + row.get("conversions", []):
            if not definitions.has(str(transition)): result.append("Unknown conversion: " + str(transition))
        for kind in ["repair", "maintenance"]:
            for material in row.get(kind, {}).get("materials", {}):
                if not items.has(material) or typeof(row[kind]["materials"][material]) != TYPE_INT or int(row[kind]["materials"][material]) <= 0:
                    result.append("Invalid " + kind + " material: " + id)
        for process in row.get("production", []):
            var item: Dictionary = items.get(str(process.get("item", "")), {})
            if not item.get("recipe") is Dictionary or int(process.get("work", 0)) <= 0:
                result.append("Invalid production recipe: " + id)
        for service in row.get("services",[]):
            if str(service.get("kind",""))!="irrigation" or int(service.get("work",0))<=0 or int(service.get("capacity",0))<=0: result.append("Invalid service: "+id)
            for material in service.get("inputs",{}):
                if not items.has(material) or typeof(service["inputs"][material])!=TYPE_INT or int(service["inputs"][material])<=0: result.append("Invalid service input: "+id)
        var size: Array = row.get("footprint", [])
        if size.size() != 2 or int(size[0]) <= 0 or int(size[1]) <= 0:
            result.append("Invalid footprint: " + id)
        for entrance in row.get("entrances", []):
            if entrance.size() != 2 or int(entrance[0]) < 0 or int(entrance[1]) < 0 or int(entrance[0]) >= int(size[0]) or int(entrance[1]) >= int(size[1]):
                result.append("Invalid entrance: " + id)
        var total = {}
        var labour = 0
        for stage in row["stages"]:
            labour += int(stage["labour"])
            if typeof(stage["labour"]) != TYPE_INT or int(stage["labour"]) <= 0:
                result.append("Nonpositive labour: " + str(row["id"]))
            for material in stage["materials"]:
                total[material] = int(total.get(material, 0)) + int(stage["materials"][material])
        if total != row["materials"] or labour != int(row["labour"]):
            result.append("Stage totals: " + str(row["id"]))
        for item in row["materials"]:
            if not items.has(item) or typeof(row["materials"][item]) != TYPE_INT or int(row["materials"][item]) <= 0:
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

# Shared by autonomous candidate selection and inspection. Era labels never
# substitute for demonstrated local knowledge. Stable IDs break equal scores.
func candidate_ids(function_name: String) -> Array:
    var ids: Array = []
    for row in definitions.values():
        if str(row.get("function", "")) == function_name: ids.append(str(row["id"]))
    ids.sort_custom(func(a: Variant, b: Variant) -> bool:
        var left := int(definitions[a].get("autonomous_priority", 0))
        var right := int(definitions[b].get("autonomous_priority", 0))
        return left > right or (left == right and str(a) < str(b)))
    return ids

func knowledge_blockers(world: RefCounted, sid: int, row: Dictionary) -> Array:
    var missing: Array = []
    for key in ["technology_prerequisites", "knowledge_prerequisites"]:
        for tech in row.get(key, []):
            if not world.occupations.has_capability(world, sid, str(tech)):
                missing.append(str(tech))
    return missing

func architecture_for(row: Dictionary) -> Dictionary:
    return {"sprite":str(row.get("visual", {}).get("sprite", "hut_a")),
        "primary_age":int(row.get("primary_age", 1)),
        "region":str(row.get("regional_family", "legacy")), "revision":1}

static func state_of(entity: Dictionary, now: int) -> String:
    if entity.has("remaining_labour"):
        if int(entity.get("progress", 0)) > 0: return "under_construction"
        return "awaiting_resources" if not entity.get("required", {}).is_empty() else "planned"
    if int(entity.get("condition", 100)) <= 0: return "ruined"
    if bool(entity.get("abandoned", false)): return "abandoned"
    if str(entity.get("pending_action", "")) == "repair": return "under_repair"
    if int(entity.get("condition", 100)) < 60: return "partially_damaged"
    if now - int(entity.get("last_condition_tick", now)) > 7200: return "neglected"
    return "functional"
