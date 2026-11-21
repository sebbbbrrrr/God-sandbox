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
        var path: String = "res://assets/pixel/construction_frames/" + str(id) + ".png.b64"
        assert(FileAccess.file_exists(path), "No authored frame sheet for " + str(id))
        var bytes: PackedByteArray = Marshalls.base64_to_raw(
            FileAccess.get_file_as_string(path).strip_edges())
        var frames := Image.new()
        assert(frames.load_png_from_buffer(bytes) == OK, "Invalid PNG " + str(id))
        var sprite: String = str(profile["sprite"])
        var source_rect: Rect2i = Rect2i(atlas.region(sprite))
        assert(frames.get_width() == source_rect.size.x * Overlay.FRAME_COLUMNS)
        assert(frames.get_height() == source_rect.size.y * 4)
        var source: Image = atlas.images[int(atlas.entries[sprite].get("page", 0))]
        # Every pixel of frame 31 must match the approved sprite, including
        # transparent edges. No palette drift or coarse upscaling is allowed.
        var final_at := Vector2i(source_rect.size.x * 7, source_rect.size.y * 3)
        for py in range(source_rect.size.y):
            for px in range(source_rect.size.x):
                var old: Color = source.get_pixel(source_rect.position.x + px,
                    source_rect.position.y + py)
                var final_pixel: Color = frames.get_pixel(final_at.x + px,
                    final_at.y + py)
                assert(old == final_pixel, "Original sprite pixel mismatch: " + str(id))
        assert(Overlay.frame_for_phase(untouched) == 0)
        assert(Overlay.frame_for_phase(complete) == 31)
        checked += 1
    print("BUILDING MOTION CONTRACT PASS: %d exact-match 32-frame sprite sheets verified" % checked)
    quit()
