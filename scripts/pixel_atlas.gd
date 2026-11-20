extends RefCounted
class_name PixelAtlas

const ATLAS = preload("res://assets/pixel/sprite_atlas.png")
var pages: Array[Texture2D] = [ATLAS]
var entries: Dictionary
var textures := {"terrain": ATLAS, "objects": ATLAS, "transitions": ATLAS}
var regions: Dictionary = {}
var images: Dictionary = {}
var miniature_cache: Dictionary = {}

func _init() -> void:
    entries = JSON.parse_string(FileAccess.get_file_as_string("res://assets/pixel/atlas.json"))
    var page_names: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/pixel/pages.json"))
    for i in range(1,page_names.size()):
        pages.append(load("res://assets/pixel/" + str(page_names[i])))
    for i in range(pages.size()):
        images[i] = pages[i].get_image()
    for key in entries:
        var entry: Dictionary = entries[key]
        var r: Array = entry["packed_rect"]
        regions[key] = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))

func region(key: String) -> Rect2:
    return regions[key]

func size_of(key: String) -> Vector2:
    return (regions[key] as Rect2).size

func texture(key: String) -> Texture2D:
    return pages[int(entries[key].get("page",0))]

func miniature(key: String, draw_size: Vector2, tint: Color) -> Image:
    var target := Vector2i(maxi(1,roundi(draw_size.x/4.0)),maxi(1,roundi(draw_size.y/4.0)))
    var cache_key := "%s/%d/%d/%s" % [key,target.x,target.y,tint.to_html()]
    if miniature_cache.has(cache_key):
        return miniature_cache[cache_key]
    var source: Image = images[int(entries[key].get("page",0))]
    var result := source.get_region(Rect2i(region(key)))
    result.resize(target.x,target.y,Image.INTERPOLATE_NEAREST)
    if tint!=Color.WHITE:
        for y in range(result.get_height()):
            for x in range(result.get_width()):
                result.set_pixel(x,y,result.get_pixel(x,y)*tint)
    miniature_cache[cache_key]=result
    return result
