extends RefCounted
class_name PixelAtlas

const ATLAS = preload("res://assets/pixel/sprite_atlas.png")
var pages: Array[Texture2D] = [ATLAS]
var entries: Dictionary
var textures := {"terrain": ATLAS, "objects": ATLAS, "transitions": ATLAS}
var regions: Dictionary = {}
var images: Dictionary = {}
var miniature_cache: Dictionary = {}
# Small reusable edge masks generated once; no runtime atlas rebuild or per-frame work.
var scorch_images: Dictionary = {}
var scorch_textures: Dictionary = {}

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
    if scorch_textures.has(key):
        return scorch_textures[key]
    return pages[int(entries[key].get("page",0))]

func miniature(key: String, draw_size: Vector2, tint: Color) -> Image:
    var target := Vector2i(maxi(1,roundi(draw_size.x/4.0)),maxi(1,roundi(draw_size.y/4.0)))
    var cache_key := "%s/%d/%d/%s" % [key,target.x,target.y,tint.to_html()]
    if miniature_cache.has(cache_key):
        return miniature_cache[cache_key]
    var result: Image
    if scorch_images.has(key):
        result = (scorch_images[key] as Image).duplicate()
    else:
        var source: Image = images[int(entries[key].get("page",0))]
        result = source.get_region(Rect2i(region(key)))
    result.resize(target.x,target.y,Image.INTERPOLATE_NEAREST)
    if tint!=Color.WHITE:
        for y in range(result.get_height()):
            for x in range(result.get_width()):
                result.set_pixel(x,y,result.get_pixel(x,y)*tint)
    miniature_cache[cache_key]=result
    return result

# 8-neighbour exposure mask: N,E,S,W,NW,NE,SE,SW. The ash alpha retreats
# irregularly inside exposed cells instead of presenting 32px square edges.
# Caching by mask + material variant keeps generation bounded to 4 * 256.
func scorch_tile(exposure: int, variant: int) -> String:
    var key := "scorch_%d_%d" % [exposure, variant]
    if scorch_images.has(key):
        return key
    var base_key := "ash_%d" % variant
    var source: Image = images[int(entries[base_key].get("page", 0))]
    var result := source.get_region(Rect2i(region(base_key)))
    for py in range(32):
        for px in range(32):
            # Coarse, deterministic pixel-scale irregularity without blurry sampling.
            var north_cut := 7 + ((px * 3 + variant * 5) % 9) - 4
            var east_cut := 7 + ((py * 5 + variant * 7) % 9) - 4
            var south_cut := 7 + ((px * 5 + variant * 3) % 9) - 4
            var west_cut := 7 + ((py * 3 + variant * 11) % 9) - 4
            var corner_cut := 15 + ((px * 7 + py * 11 + variant * 3) % 7) - 3
            var exposed_edge := (
                ((exposure & 1) != 0 and py < north_cut)
                or ((exposure & 2) != 0 and 31 - px < east_cut)
                or ((exposure & 4) != 0 and 31 - py < south_cut)
                or ((exposure & 8) != 0 and px < west_cut)
                or ((exposure & 16) != 0 and px + py < corner_cut)
                or ((exposure & 32) != 0 and 31 - px + py < corner_cut)
                or ((exposure & 64) != 0 and 62 - px - py < corner_cut)
                or ((exposure & 128) != 0 and px + 31 - py < corner_cut)
            )
            if exposed_edge:
                result.set_pixel(px, py, Color.TRANSPARENT)
    scorch_images[key] = result
    scorch_textures[key] = ImageTexture.create_from_image(result)
    regions[key] = Rect2(0, 0, 32, 32)
    return key
