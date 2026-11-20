extends RefCounted
## Reuses the existing D4 pixel artwork, cached per physical item definition.
const Art = preload("res://scripts/ui/item_pixel_art.gd")
static var cache := {}
static func texture(item_id: String) -> Texture2D:
    if cache.has(item_id):
        return cache[item_id]
    var rows: Array = Art.sprite(item_id)
    var img := Image.create(14,14,false,Image.FORMAT_RGBA8)
    img.fill(Color.TRANSPARENT)
    for y in range(rows.size()):
        for x in range(str(rows[y]).length()):
            var letter := str(rows[y]).substr(x,1)
            if letter != ".":
                img.set_pixel(x+2,y+2,Art.P.get(letter,Art.P["k"]))
    var result := ImageTexture.create_from_image(img)
    cache[item_id] = result
    return result
