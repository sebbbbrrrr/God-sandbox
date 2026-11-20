extends RefCounted
## Original SVG symbols, rasterised once per colour/size and cached.
const ICON_PATHS := {
    "hand": "<path d='M8 13V5a1.5 1.5 0 0 1 3 0v6-7a1.5 1.5 0 0 1 3 0v7-5a1.5 1.5 0 0 1 3 0v6-3a1.5 1.5 0 0 1 3 0v6c0 4-2.5 7-6.5 7H11c-2.3 0-4-1-5.1-2.8L3 15a1.5 1.5 0 0 1 2.5-1.7l2.5 2.7'/>",
    "raise": "<path d='m2 19 6-9 4 5 4-10 6 14H2Z'/><path d='M16 5V2m-3 3h6'/>",
    "fire": "<path d='M12 22c-4.4 0-7-3.2-7-7.2 0-3 2.5-6 3.4-8.8.5 3.1 2.5 3.2 3.4 3.8 1.2-3 1.6-5.4 1-8 4.8 3.8 7.2 7.7 7.2 11.5 0 4.2-2.7 7.7-7 7.7Z'/><path d='M12 22c-2.1 0-3.5-1.5-3.5-3.5 0-1.8 1-3 2-4.4.3 2 2.7 2.6 3 4.3.3-1 .5-2 .4-3.1 2 1.9 2.6 3.3 2.6 4.3 0 2.1-1.4 3.4-3.5 3.4Z'/>",
    "forest": "<path d='m6 3-4 8h3l-4 7h11l-4-7h3L7 3ZM7 18v4'/><path d='m17 2-4 9h3l-3 7h10l-3-7h2l-4-9Zm1 16v4'/>",
    "bless": "<path d='m12 2 2.6 6.5L21 11l-6.4 2.5L12 20l-2.5-6.5L3 11l6.5-2.5L12 2Z'/><path d='M20 18v5m-2.5-2.5h5M4 2v4M2 4h4'/>",
    "spawn": "<circle cx='12' cy='6' r='3'/><path d='M5 22v-5c0-4 2.8-6 7-6s7 2 7 6v5M9 16v6m6-6v6'/>",
    "ocean": "<path d='M2 7c3-4 5 4 10 0s7-4 10 0M2 13c3-4 5 4 10 0s7-4 10 0M2 19c3-4 5 4 10 0s7-4 10 0'/>",
    "tools": "<rect x='3' y='4' width='7' height='7' rx='1'/><rect x='14' y='4' width='7' height='7' rx='1'/><rect x='3' y='15' width='7' height='6' rx='1'/><rect x='14' y='15' width='7' height='6' rx='1'/>",
    "pause": "<rect x='5' y='4' width='5' height='16' rx='1'/><rect x='14' y='4' width='5' height='16' rx='1'/>",
    "play": "<path d='m7 4 13 8-13 8V4Z'/>",
    "settings": "<circle cx='12' cy='12' r='3'/><path d='M10 2h4l.6 2.5 2 1.2 2.5-.7 2 3.5-1.9 1.8v3.4l1.9 1.8-2 3.5-2.5-.7-2 1.2L14 22h-4l-.6-2.5-2-1.2-2.5.7-2-3.5 1.9-1.8v-3.4L2.9 8.5l2-3.5 2.5.7 2-1.2L10 2Z'/>",
    "close": "<path d='M5 5 19 19M19 5 5 19'/>",
    "chevron": "<path d='m5 9 7 7 7-7'/>"
    ,"info": "<circle cx='12' cy='12' r='9'/><path d='M12 11v6m0-11v1'/>",
    "eye": "<path d='M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12Z'/><circle cx='12' cy='12' r='3'/>",
    "save": "<path d='M4 3h13l4 4v14H3V3h1Z'/><path d='M7 3v6h10V3M7 21v-8h10v8'/>",
    "load": "<path d='M3 7h7l2 3h10l-4 11H2V5h7l2 2M3 11h19'/>",
    "pack": "<rect x='5' y='7' width='14' height='15' rx='3'/><path d='M9 7V3h6v4M5 13h14M9 17h6'/>",
    "back": "<path d='m14 5-7 7 7 7M7 12h15'/>",
    "more": "<circle cx='5' cy='12' r='1'/><circle cx='12' cy='12' r='1'/><circle cx='19' cy='12' r='1'/>",
    "brush": "<circle cx='12' cy='12' r='8'/><circle cx='12' cy='12' r='3'/>",
    "check": "<path d='m4 12 5 5L20 6'/>"
}
static var cache := {}
static func texture(key: String, tint: Color = Color("#f5efdf"), size: int = 24) -> Texture2D:
    var id := "%s:%s:%d" % [key, tint.to_html(), size]
    if cache.has(id):
        return cache[id]
    var path: String = ICON_PATHS.get(key, ICON_PATHS["tools"])
    var svg := "<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d' viewBox='0 0 24 24' fill='none' stroke='#%s' stroke-width='1.7' stroke-linecap='round' stroke-linejoin='round'>%s</svg>" % [size, size, tint.to_html(false), path]
    var img := Image.new()
    if img.load_svg_from_buffer(svg.to_utf8_buffer(), 2.0) != OK:
        return null
    var tex := ImageTexture.create_from_image(img)
    cache[id] = tex
    return tex
