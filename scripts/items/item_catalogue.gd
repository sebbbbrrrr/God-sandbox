extends RefCounted
# D1: data-driven catalogue. Never grants technology from elapsed time or era.
# The world's authoritative work actions must call these gates before committing
# any inventory/material transaction. No passive production happens here.

const ITEM_PATH := "res://data/catalogue/foundation_items.json"
const ABILITY_PATH := "res://data/catalogue/foundation_abilities.json"

var items: Dictionary = {}
var abilities: Dictionary = {}

func _init() -> void:
    var item_rows: Variant = _load_rows(ITEM_PATH, "items")
    var ability_rows: Variant = _load_rows(ABILITY_PATH, "abilities")
    if item_rows is Array:
        for row in item_rows:
            if row is Dictionary and row.has("id"):
                items[str(row["id"])] = row
    if ability_rows is Array:
        for row in ability_rows:
            if row is Dictionary and row.has("id"):
                abilities[str(row["id"])] = row

func _load_rows(path: String, key: String) -> Variant:
    if not FileAccess.file_exists(path):
        push_error("Catalogue file missing: " + path)
        return null
    var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not document is Dictionary or int(document.get("schema_version", -1)) != 1:
        push_error("Invalid catalogue format: " + path)
        return null
    return document.get(key, null)

func item(id: String) -> Dictionary:
    var record: Dictionary = items.get(id, {})
    return record.duplicate(true)

func ability(id: String) -> Dictionary:
    var record: Dictionary = abilities.get(id, {})
    return record.duplicate(true)

func validate() -> Array[String]:
    var errors: Array[String] = []
    if items.size() != 100:
        errors.append("Expected 100 unique items")
    if abilities.size() != 35:
        errors.append("Expected 35 unique abilities")
    for id in items:
        var record: Dictionary = items[id]
        if id != str(record.get("id", "")) or int(record.get("first_era", 0)) not in range(1, 12):
            errors.append("Invalid item id/era: " + id)
        if not record.get("physical", null) is Dictionary:
            errors.append("Missing physics: " + id)
        var recipe: Variant = record.get("recipe", null)
        if str(record.get("acquisition", "")) == "craft":
            if not recipe is Dictionary or not recipe.get("inputs", null) is Dictionary:
                errors.append("Missing recipe: " + id)
                continue
            if int(recipe.get("output", 0)) <= 0:
                errors.append("Invalid recipe output: " + id)
            for ingredient in recipe["inputs"]:
                if not items.has(str(ingredient)) or int(recipe["inputs"][ingredient]) <= 0:
                    errors.append("Unknown/nonpositive ingredient in " + id + ": " + str(ingredient))
        elif recipe != null:
            errors.append("Gatherable with a recipe: " + id)
    for id in abilities:
        var row: Dictionary = abilities[id]
        if str(row.get("id", "")) != id or int(row.get("first_era", 0)) not in range(1, 12):
            errors.append("Invalid ability: " + id)
        var required_item := str(row.get("required_item", ""))
        if required_item != "" and not items.has(required_item):
            errors.append("Missing ability equipment: " + id)
    return errors

static func _flag_present(flags: Variant, id: String) -> bool:
    if id == "":
        return true
    if flags is Dictionary:
        return bool(flags.get(id, false))
    if flags is Array:
        return id in flags
    return false

static func _has_materials(inventory: Dictionary, inputs: Dictionary) -> bool:
    for ingredient in inputs:
        if int(inventory.get(ingredient, 0)) < int(inputs[ingredient]) or int(inputs[ingredient]) <= 0:
            return false
    return true

# 'context' is provided by an authoritative real work event:
# age_years:int, skills:{occupation:xp}, capabilities:{tech:true},
# facilities:{workstation:true}. Its values are NOT fabricated by era labels.
func can_craft(id: String, inventory: Dictionary, context: Dictionary) -> bool:
    var record: Dictionary = items.get(id, {})
    if record.is_empty():
        return false
    var recipe: Variant = record.get("recipe", null)
    if not recipe is Dictionary:
        return false
    var station := str(recipe.get("station", ""))
    var tech := str(recipe.get("capability", ""))
    var occupation := str(recipe.get("skill", ""))
    var skill_xp: Dictionary = context.get("skills", {})
    if not _flag_present(context.get("capabilities", {}), tech) or \
            not _flag_present(context.get("facilities", {}), station):
        return false
    if not _flag_present(context.get("roles", {}), occupation):
        return false
    if int(context.get("age_years", -1)) < int(recipe.get("min_age_years", 9999)):
        return false
    if int(skill_xp.get(occupation, 0)) < int(recipe.get("min_skill_xp", 0)):
        return false
    return _has_materials(inventory, recipe["inputs"])

# Only invoke after a physically executed craft job; changes caller-supplied
# inventory atomically (no mutation on failed checks, no free raw resources).
func craft(id: String, inventory: Dictionary, context: Dictionary) -> bool:
    if not can_craft(id, inventory, context):
        return false
    var recipe: Dictionary = items[id]["recipe"]
    for ingredient in recipe["inputs"]:
        inventory[ingredient] = int(inventory[ingredient]) - int(recipe["inputs"][ingredient])
        if int(inventory[ingredient]) == 0:
            inventory.erase(ingredient)
    inventory[id] = int(inventory.get(id, 0)) + int(recipe["output"])
    return true

# Eligibility is not action execution. The existing simulation is still
# responsible for work, effort, physical effects and XP reward.
func can_use_ability(id: String, inventory: Dictionary, context: Dictionary) -> bool:
    var row: Dictionary = abilities.get(id, {})
    if row.is_empty() or not bool(row.get("implemented", false)):
        return false
    if int(context.get("age_years", -1)) < int(row.get("min_age_years", 9999)):
        return false
    var role := str(row.get("occupation", ""))
    var skills: Dictionary = context.get("skills", {})
    if not _flag_present(context.get("roles", {}), role):
        return false
    if int(skills.get(role, 0)) < int(row.get("min_skill_xp", 0)):
        return false
    if not _flag_present(context.get("capabilities", {}), str(row.get("capability", ""))):
        return false
    if not _flag_present(context.get("facilities", {}), str(row.get("facility", ""))):
        return false
    var needed := str(row.get("required_item", ""))
    return needed == "" or int(inventory.get(needed, 0)) > 0

# Use actual local technology, workstations and citizen progression, not
# country, religion, ethnicity, year or a universal global era number.
func context_for_citizen(world: RefCounted, person: Dictionary, definition_id: String, for_ability: bool = false) -> Dictionary:
    var row: Dictionary = abilities.get(definition_id, {}) if for_ability else items.get(definition_id, {})
    if row.is_empty() or int(person.get("hp", 0)) <= 0:
        return {}
    var requirements_variant: Variant = row if for_ability else row.get("recipe", null)
    if not requirements_variant is Dictionary or requirements_variant.is_empty():
        return {}
    var requirements: Dictionary = requirements_variant
    var tech := str(requirements.get("capability", ""))
    var facility := str(requirements.get("facility", requirements.get("station", "")))
    var nation: int = world.settlements.sid(person)
    var skills: Dictionary = world.occupations.record_for(person).get("xp", {})
    var role := str(requirements.get("occupation", requirements.get("skill", "")))
    var roles: Dictionary = {}
    var capabilities: Dictionary = {}
    var facilities: Dictionary = {}
    if role != "":
        roles[role] = world.occupations.enabled(world, nation, role)
    if tech != "":
        capabilities[tech] = world.occupations.has_capability(world, nation, tech)
    if facility != "":
        facilities[facility] = world.occupations.facility_present(world, nation, facility)
    return {
        "age_years": world.calendar.age_years(int(person.get("birth_tick", world.tick)), world.tick),
        "skills": skills.duplicate(),
        "roles": roles, "capabilities": capabilities, "facilities": facilities
    }

# Instance state is separate from immutable definitions and can be persisted
# by the inventory/equipment slice without duplicating every catalogue entry.
func new_instance(id: String, serial: int, owner_id: int, quality: int = 50) -> Dictionary:
    if not items.has(id) or serial <= 0 or owner_id < 0:
        return {}
    var properties: Dictionary = items[id]["physical"]
    return {"serial": serial, "item_id": id, "owner_id": owner_id,
        "quality": clampi(quality, 0, 100),
        "condition": int(properties.get("durability", 0)),
        "origin_settlement": "", "crafted_tick": -1,
        "modifiers": [], "history": []}
