extends RefCounted
# Deterministic packed physical-item atlas: one texture for 420 visual regions.
# This layer only draws; it never creates inventory or advances citizen jobs.
const PAGE = preload("res://assets/pixel/physical_atlas.png")
const MANIFEST_PATH := "res://data/visuals/physical_sprite_manifest.json"
static var _entries: Dictionary = {}
static var _item_keys: Dictionary = {}

static func _load_manifest() -> void:
    if not _entries.is_empty():
        return
    var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
    if parsed is Dictionary:
        _entries = parsed.get("sprites", {})
        _item_keys = parsed.get("items", {})

static func has_sprite(key: String) -> bool:
    _load_manifest()
    return _entries.has(key)

static func has_item(item_id: String) -> bool:
    _load_manifest()
    return _item_keys.has(item_id)

static func draw(canvas: CanvasItem, key: String, center: Vector2, pixels: float) -> bool:
    if pixels < 2.0:
        return false
    _load_manifest()
    if not _entries.has(key):
        return false
    var r: Array = _entries[key]["rect"]
    var source := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
    var dim := Vector2.ONE * pixels
    canvas.draw_texture_rect_region(PAGE, Rect2((center - dim * 0.5).round(), dim),
        source, Color.WHITE, false, true)
    return true

static func draw_item(canvas: CanvasItem, item_id: String, center: Vector2, pixels: float) -> bool:
    _load_manifest()
    return draw(canvas, str(_item_keys.get(item_id, "")), center, pixels)
