extends SceneTree
const World = preload("res://scripts/simulation.gd")
const Styles = preload("res://scripts/visuals/era_architecture.gd")
const Atlas = preload("res://scripts/pixel_atlas.gd")
const Renderer = preload("res://scripts/pixel_world_renderer.gd")

func _initialize() -> void:
    var world = World.new(1107, false)
    world.capitals[0] = Vector2i(12, 12)
    world.set_terrain_cell(12, 12, World.TOWN)
    var original_tick: int = world.tick
    assert(Styles.nation_at(world, Vector2i(12, 12)) == 0)
    assert(Styles.visual_age(world, 0) == 1)
    var pixel_atlas = Atlas.new()
    var appearances := []
    for age in range(1, 6):
        var key := Styles.sprite(age, "ordinary", 10, 10, 99)
        appearances.append(key)
        assert(pixel_atlas.regions.has(key), "Missing art " + key)
        for role in ["capital", "tool_area", "primitive_shelter", "timber_hut"]:
            assert(pixel_atlas.regions.has(Styles.sprite(age, role, 10, 10, 99)))
    assert(appearances.size() == 5)
    assert(appearances[0] != appearances[1] and appearances[1] != appearances[2])
    assert(appearances[2] != appearances[3] and appearances[3] != appearances[4])
    assert(world.food.set_technique(0, "cultivation"))
    assert(Styles.visual_age(world, 0) == 2)
    assert(world.occupations.grant_capability(world, 0, "bronze_working", "experiment"))
    assert(Styles.visual_age(world, 0) == 3)
    assert(world.occupations.grant_capability(world, 0, "iron_working", "experiment"))
    assert(Styles.visual_age(world, 0) == 4)
    assert(world.occupations.grant_capability(world, 0, "water_power", "experiment"))
    assert(Styles.visual_age(world, 0) == 5)
    var renderer = Renderer.new()
    root.add_child(renderer)
    renderer.setup(world)
    renderer.update_view(Vector2.ZERO, 32.0, Rect2(0, 0, 480, 480))
    assert(renderer.architecture_ages[0] == 5)
    assert(world.occupations.lose_capability(world, 0, "water_power", "knowledge_lost"))
    renderer.update_view(Vector2.ZERO, 32.0, Rect2(0, 0, 480, 480))
    assert(renderer.architecture_ages[0] == 4)
    assert(world.tick == original_tick, "Visual change cannot advance simulation")
    var count := 0
    for key in pixel_atlas.entries:
        if str(key).begins_with("era"):
            count += 1
            var record: Dictionary = pixel_atlas.entries[key]
            assert(int(record["page"]) == 1)
            var area: Array = record["packed_rect"]
            assert(int(area[0]) + int(area[2]) <= 640)
            assert(int(area[1]) + int(area[3]) <= 512)
    assert(count == 80, "Expected 80 region age art")
    assert(Styles.sprite(5, "primitive_shelter", 12, 12, 99).begins_with("era1_"))
    assert(Styles.sprite(5, "timber_hut", 12, 12, 99).begins_with("era1_"))
    print("PASS: 80 architecture sprites, 5 distinct visual ages, adoption, downgrade, redraw and backwards-compatible primitive buildings")
    quit()
