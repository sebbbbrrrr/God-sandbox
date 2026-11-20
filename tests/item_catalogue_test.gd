extends SceneTree
const Catalogue = preload("res://scripts/items/item_catalogue.gd")

func _initialize() -> void:
    var ok := true
    var catalogue = Catalogue.new()
    var errors: Array[String] = catalogue.validate()
    ok = check(errors.is_empty(), "100 items and 35 abilities validate: " + str(errors)) and ok
    ok = check(catalogue.items.size() == 100 and catalogue.abilities.size() == 35,
        "bounded foundation catalogue loaded") and ok
    var era_counts: Dictionary = {}
    for row in catalogue.items.values():
        var era := int(row["first_era"])
        era_counts[era] = int(era_counts.get(era, 0)) + 1
    ok = check(era_counts.has(1) and era_counts.has(2) and era_counts.has(3),
        "early eras represented; later eras remain reserved") and ok
    var inventory := {"wood": 2, "stone": 1}
    var context := {"age_years": 18, "skills": {"stone_toolmaker": 0},
        "capabilities": {}, "facilities": {}, "roles": {"stone_toolmaker": true}}
    ok = check(catalogue.can_craft("wood_plank", inventory, context),
        "recipe accepts real available materials") and ok
    ok = check(catalogue.craft("wood_plank", inventory, context) and
        int(inventory.get("wood_plank", 0)) == 1 and not inventory.has("wood") and
        int(inventory.get("stone", 0)) == 1, "successful craft conserves unrelated inventory") and ok
    var child_context: Dictionary = context.duplicate(true)
    child_context["age_years"] = 6
    ok = check(not catalogue.can_craft("wood_plank", {"wood": 2}, child_context),
        "child cannot perform age-restricted crafting") and ok
    var denied_role: Dictionary = context.duplicate(true)
    denied_role["roles"] = {"stone_toolmaker": false}
    ok = check(not catalogue.can_craft("wood_plank", {"wood": 2}, denied_role),
        "catalogued-but-disabled occupation does not authorize crafting") and ok
    var before: Dictionary = inventory.duplicate(true)
    ok = check(not catalogue.craft("wood_plank", inventory, context) and inventory == before,
        "failed craft never consumes partial input or produces items") and ok
    ok = check(not catalogue.craft("fresh_water", inventory, context),
        "natural resources cannot be created by crafting") and ok
    var forged := {"copper_ore": 3, "tin_ore": 1, "charcoal": 1}
    var metal_ctx := {"age_years": 30, "skills": {"bronze_smith": 160},
        "capabilities": {}, "facilities": {"smelter": true},
        "roles": {"bronze_smith": true}}
    ok = check(not catalogue.can_craft("bronze_ingot", forged, metal_ctx),
        "bronze not unlocked by era label or raw ore alone") and ok
    metal_ctx["capabilities"] = {"bronze_working": true}
    var untrained: Dictionary = metal_ctx.duplicate(true)
    untrained["skills"] = {"bronze_smith": 0}
    ok = check(not catalogue.can_craft("bronze_ingot", forged, untrained),
        "knowledge and workshop alone do not substitute for practiced skill") and ok
    ok = check(catalogue.craft("bronze_ingot", forged, metal_ctx) and
        int(forged.get("bronze_ingot", 0)) == 1 and forged.size() == 1,
        "actual adopted metallurgy and smelter allow conserved production") and ok
    var batch := {"wood": 2, "knapped_flint": 2, "plant_fibre": 1}
    var trained_crafter: Dictionary = context.duplicate(true)
    trained_crafter["skills"] = {"stone_toolmaker": 30}
    ok = check(catalogue.craft("arrows", batch, trained_crafter) and
        int(batch.get("arrows", 0)) == 6, "batch outputs respect quantity") and ok
    var ability_ctx := {"age_years": 18, "skills": {"forager": 0},
        "capabilities": {}, "facilities": {}, "roles": {"forager": true}}
    ok = check(catalogue.can_use_ability("foraging", {}, ability_ctx),
        "adult forager may use implemented ungated ability") and ok
    ability_ctx["age_years"] = 4
    ok = check(not catalogue.can_use_ability("foraging", {}, ability_ctx),
        "age-gated action denied to an ineligible child") and ok
    ability_ctx["age_years"] = 18
    ok = check(not catalogue.can_use_ability("archery", {"shortbow": 1}, ability_ctx),
        "catalogued but unimplemented action cannot execute") and ok
    var candidate: Dictionary = catalogue.new_instance("flint_knife", 31, 9, 120)
    ok = check(int(candidate.get("quality", -1)) == 100 and
        str(candidate.get("item_id", "")) == "flint_knife" and
        candidate.get("history", null) is Array,
        "unique item state and quality constraints") and ok
    ok = check(catalogue.new_instance("missing_item", 3, 0).is_empty(),
        "unknown item cannot be instanced") and ok
    if ok:
        print("ITEM_CATALOGUE_TESTS_PASSED")
    quit(0 if ok else 1)

func check(condition: bool, message: String) -> bool:
    if not condition:
        push_error("FAILED: " + message)
        return false
    print("PASS: " + message)
    return true
