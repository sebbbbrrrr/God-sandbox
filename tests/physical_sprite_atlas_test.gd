extends SceneTree
# Visual asset contract: sprite count, physical catalogue and atlas bounds.
const Art = preload("res://scripts/visuals/physical_sprite_atlas.gd")
const Catalogue = preload("res://scripts/items/item_catalogue.gd")

func _initialize() -> void:
    var parsed = JSON.parse_string(FileAccess.get_file_as_string(
        "res://data/visuals/physical_sprite_manifest.json"))
    assert(parsed is Dictionary)
    assert(int(parsed["total_regions"]) == 420)
    var sprites: Dictionary = parsed["sprites"]
    assert(sprites.size() == 420)
    var catalogue = Catalogue.new()
    for item_id in catalogue.items:
        assert(Art.has_item(str(item_id)), "Missing art for item: " + str(item_id))
    var tex: Texture2D = load("res://assets/pixel/physical_atlas.png")
    assert(tex.get_width() == 512 and tex.get_height() == 864)
    for key in sprites:
        var r: Array = sprites[key]["rect"]
        assert(int(r[0]) >= 0 and int(r[1]) >= 0)
        assert(int(r[0]) + int(r[2]) <= tex.get_width())
        assert(int(r[1]) + int(r[3]) <= tex.get_height())
    print("PASS physical atlas: 420 regions; complete 100-item catalogue coverage")
    quit()
