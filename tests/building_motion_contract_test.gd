extends SceneTree
# Run: godot --headless --path . --script res://tests/building_motion_contract_test.gd
const Catalogue = preload("res://scripts/construction/building_catalogue.gd")
const Atlas = preload("res://scripts/pixel_atlas.gd")
const Overlay = preload("res://scripts/construction/architectural_build_overlay.gd")

func _initialize() -> void:
    var catalogue = Catalogue.new()
    var atlas = Atlas.new()
    var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(
        "res://data/architecture/construction_motion_manifest.json"))
    assert(manifest is Dictionary)
    var profiles: Dictionary = manifest.get("buildings", {})
    assert(profiles.size() == catalogue.definitions.size(), "Every building requires a profile")
    var checked := 0
    for id in catalogue.definitions:
        var row: Dictionary = catalogue.definitions[id]
        assert(profiles.has(id), "Missing construction profile " + str(id))
        var profile: Dictionary = profiles[id]
        assert(str(profile.get("sprite", "")) == str(row.get("visual", {}).get("sprite", "")))
        assert(atlas.regions.has(str(profile["sprite"])), "Unpacked sprite " + str(id))
        for band in ["foundation", "walls", "roof"]:
            var dimensions: Array = profile.get(band, [])
            assert(dimensions.size() == 2)
            assert(int(dimensions[0]) >= 2 and int(dimensions[1]) >= 2)
        var site := {"stage": 0, "stage_work": 0}
        var untouched: Dictionary = Overlay.progress_by_phase(site, row)
        assert(float(untouched["roof"]) == 0.0 and float(untouched["walls"]) == 0.0)
        site["stage"] = row["stages"].size()
        var complete: Dictionary = Overlay.progress_by_phase(site, row)
        assert(float(complete["roof"]) == 1.0)
        assert(float(complete["walls"]) == 1.0)
        assert(float(complete["base"]) == 1.0)
        checked += 1
    print("BUILDING MOTION CONTRACT PASS: %d catalogue sprites covered" % checked)
    quit()
