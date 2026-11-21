extends Node2D
# World-space construction artwork: reveal the ORIGINAL authored atlas pixels in
# discrete masonry/plank-sized sections. No substitute buildings, no save changes.
# One CanvasItem for all visible projects; never one node per brick or citizen.
const MAX_SITES := 40
const MAX_OPERATING := 48
const REDRAW_INTERVAL := 1.0 / 12.0
var world: RefCounted
var atlas: RefCounted
var parent_renderer
var seconds := 0.0
var pending := 0.0
var profiles: Dictionary = {}
var frame_sheets: Dictionary = {}
var playback_frames: Dictionary = {}
const FRAME_COLUMNS := 8
const FRAME_COUNT := 32

func setup(renderer: Node2D, simulation: RefCounted, pixel_atlas: RefCounted) -> void:
    parent_renderer = renderer
    world = simulation
    atlas = pixel_atlas
    var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(
        "res://data/architecture/construction_motion_manifest.json"))
    if manifest is Dictionary:
        profiles = manifest.get("buildings", {})
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    z_index = 470

func advance(delta: float) -> void:
    pending += maxf(0.0, delta)
    if pending >= REDRAW_INTERVAL:
        seconds += pending
        pending = 0.0
        if world != null:
            queue_redraw()

static func progress_by_phase(site: Dictionary, definition: Dictionary) -> Dictionary:
    var result := {"ground": 0.0, "base": 0.0, "walls": 0.0, "roof": 0.0}
    var stages: Array = definition.get("stages", [])
    var index: int = clampi(int(site.get("stage", 0)), 0, stages.size())
    for i in range(stages.size()):
        var stage: Dictionary = stages[i]
        var fraction: float = 1.0 if i < index else 0.0
        if i == index:
            fraction = clampf(float(site.get("stage_work", 0)) /
                maxf(1.0, float(stage.get("labour", 1))), 0.0, 1.0)
        var name: String = str(stage.get("id", ""))
        match name:
            "survey", "site_preparation":
                result["ground"] = maxf(float(result["ground"]), fraction)
            "foundations", "stacking":
                result["base"] = maxf(float(result["base"]), fraction)
            "framework", "structural_assembly":
                result["walls"] = maxf(float(result["walls"]), fraction)
                # Three-stage older definitions combine foundation and framing.
                if name == "structural_assembly":
                    result["base"] = maxf(float(result["base"]), minf(1.0, fraction * 2.0))
            "roofing", "finishing":
                result["roof"] = maxf(float(result["roof"]), fraction)
            "inspection":
                result["roof"] = maxf(float(result["roof"]), fraction)
    if index >= stages.size():
        result = {"ground": 1.0, "base": 1.0, "walls": 1.0, "roof": 1.0}
    return result

func _draw() -> void:
    if world == null or atlas == null or parent_renderer == null:
        return
    var view: Rect2 = parent_renderer.visible_rect.grow(96.0)
    var displayed := 0
    for site in world.construction.projects:
        if displayed >= MAX_SITES:
            break
        var row: Dictionary = world.construction.catalogue.definition(str(site.get("definition_id", "")))
        if row.is_empty():
            continue
        var sprite: String = str(site.get("architecture", {}).get("sprite",
            row.get("visual", {}).get("sprite", "")))
        if not atlas.regions.has(sprite):
            continue
        var x: int = int(site["x"])
        var y: int = int(site["y"])
        var foot: Array = row.get("footprint", [1, 1])
        var end := parent_renderer.top_left(x, y) + Vector2(float(foot[0]) * 16.0, 27.0)
        var size: Vector2 = atlas.size_of(sprite)
        var dest := Rect2((end - Vector2(size.x * 0.5, size.y)).round(), size)
        if not view.intersects(dest.grow(12.0)):
            continue
        displayed += 1
        var phase: Dictionary = progress_by_phase(site, row)
        _draw_survey(dest, phase, site)
        var building_id: String = str(site.get("definition_id", ""))
        var sheet: Texture2D = _frame_sheet(building_id)
        if sheet != null:
            var project_id: int = int(site.get("id", 0))
            var target_frame: int = frame_for_phase(phase)
            var current_frame: int = int(playback_frames.get(project_id, target_frame))
            # Construction can lag behind paid labour but never lead it.
            current_frame = mini(target_frame, current_frame + 1)
            playback_frames[project_id] = current_frame
            var rect := Rect2(Vector2(float(current_frame % FRAME_COLUMNS),
                float(current_frame / FRAME_COLUMNS)) * size, size)
            draw_texture_rect_region(sheet, dest, rect, Color.WHITE, false, true)
        elif parent_renderer.detail > 0:
            # Unsupported modded buildings continue using the safe original.
            var profile: Dictionary = profiles.get(building_id, {})
            _draw_pieces(sprite, dest.position, phase, int(site.get("id", 0)), profile)
        else:
            _draw_low_detail(sprite, dest, phase)
    _draw_finishing_buildings(view)
    if parent_renderer.detail == 0:
        return
    _draw_operations(view)


func is_finishing(building_id: int) -> bool:
    return playback_frames.has(building_id) and int(playback_frames[building_id]) < 31

func _draw_finishing_buildings(view: Rect2) -> void:
    # Functional completion is immediate, but a project already seen being
    # constructed finishes its 32-frame visual sequence before the static
    # completed building takes over. Never delay gameplay, inventories or AI.
    for building in world.construction.houses:
        var id: int = int(building.get("id", -1))
        if not is_finishing(id):
            continue
        var definition: Dictionary = world.construction.catalogue.definition(
            str(building.get("definition_id", "")))
        if definition.is_empty():
            continue
        var kind: String = str(building.get("definition_id", ""))
        var sprite: String = str(building.get("architecture", {}).get("sprite",
            definition.get("visual", {}).get("sprite", "")))
        if not atlas.regions.has(sprite):
            continue
        var x: int = int(building["x"])
        var y: int = int(building["y"])
        var footprint: Array = definition.get("footprint", [1, 1])
        var foot := parent_renderer.top_left(x, y) + Vector2(float(footprint[0]) * 16.0, 27.0)
        var size: Vector2 = atlas.size_of(sprite)
        var dest := Rect2((foot - Vector2(size.x * 0.5, size.y)).round(), size)
        if not view.intersects(dest.grow(12.0)):
            continue
        var sheet: Texture2D = _frame_sheet(kind)
        if sheet == null:
            playback_frames.erase(id)
            continue
        var index: int = mini(31, int(playback_frames[id]) + 1)
        playback_frames[id] = index
        var rect := Rect2(Vector2(float(index % FRAME_COLUMNS),
            float(index / FRAME_COLUMNS)) * size, size)
        draw_texture_rect_region(sheet, dest, rect, Color.WHITE, false, true)
        if index >= 31:
            playback_frames.erase(id)
            parent_renderer.invalidate_cell(Vector2i(x, y))

static func frame_for_phase(phase: Dictionary) -> int:
    var base: float = clampf(float(phase.get("base", 0.0)), 0.0, 1.0)
    var walls: float = clampf(float(phase.get("walls", 0.0)), 0.0, 1.0)
    var roof: float = clampf(float(phase.get("roof", 0.0)), 0.0, 1.0)
    if base <= 0.0:
        return 0
    if base < 1.0:
        return clampi(ceili(base * 6.0), 1, 5)
    if walls <= 0.0:
        return 6
    if walls < 1.0:
        return clampi(7 + floori(walls * 15.0), 7, 20)
    if roof <= 0.0:
        return 21
    if roof < 1.0:
        return clampi(22 + floori(roof * 9.0), 22, 30)
    return 31

func _frame_sheet(building_id: String) -> Texture2D:
    if frame_sheets.has(building_id):
        return frame_sheets[building_id]
    var path := "res://assets/pixel/construction_frames/" + building_id + ".png.b64"
    if not FileAccess.file_exists(path):
        frame_sheets[building_id] = null
        return null
    var encoded: String = FileAccess.get_file_as_string(path)
    var buffer: PackedByteArray = Marshalls.base64_to_raw(encoded.strip_edges())
    var decoded := Image.new()
    if decoded.load_png_from_buffer(buffer) != OK:
        push_warning("Invalid authored construction sprite sheet: " + building_id)
        frame_sheets[building_id] = null
        return null
    frame_sheets[building_id] = ImageTexture.create_from_image(decoded)
    return frame_sheets[building_id]

func _draw_survey(rect: Rect2, phase: Dictionary, site: Dictionary) -> void:
    var left := rect.position.x + 2.0
    var bottom := rect.end.y - 3.0
    var width := maxf(4.0, rect.size.x - 4.0)
    draw_rect(Rect2(Vector2(left, bottom), Vector2(width, 3.0)), Color("#67543d", 0.65))
    for x in [left, left + width]:
        draw_rect(Rect2(Vector2(x, bottom - 4.0), Vector2(1.0, 5.0)), Color("#c8a47a"))
    if bool(site.get("paused", false)):
        draw_rect(rect, Color("#985847", 0.13))

func _draw_pieces(sprite: String, at: Vector2, phase: Dictionary, seed: int,
        profile: Dictionary) -> void:
    var source: Rect2 = atlas.region(sprite)
    var width: int = int(source.size.x)
    var height: int = int(source.size.y)
    if width <= 0 or height <= 0:
        return
    # Non-overlapping structural bands; every visible pixel comes directly
    # from its final authored atlas rectangle.
    var base_top: int = floori(float(height) * 0.79)
    var roof_bottom: int = floori(float(height) * 0.34)
    var foundation: Array = profile.get("foundation", [5, 3])
    var walls: Array = profile.get("walls", [7, 4])
    var roofing: Array = profile.get("roof", [6, 3])
    _draw_band(sprite, at, source, base_top, height,
        int(foundation[0]), int(foundation[1]), float(phase["base"]), seed)
    _draw_band(sprite, at, source, roof_bottom, base_top,
        int(walls[0]), int(walls[1]), float(phase["walls"]), seed + 11)
    _draw_band(sprite, at, source, 0, roof_bottom,
        int(roofing[0]), int(roofing[1]), float(phase["roof"]), seed + 29)

func _draw_band(sprite: String, at: Vector2, src: Rect2, top: int, bottom: int,
        cell_width: int, cell_height: int, fraction: float, seed: int) -> void:
    if fraction <= 0.0 or bottom <= top:
        return
    var cols: int = ceili(src.size.x / float(cell_width))
    var rows: int = ceili(float(bottom - top) / float(cell_height))
    var count: int = cols * rows
    var visible_count: int = clampi(floori(fraction * float(count) + 0.00001), 0, count)
    if visible_count == 0:
        return
    for i in range(visible_count):
        var row_index: int = i / cols
        var col_index: int = i % cols
        # Brickwork staggering. All pieces remain aligned with their original
        # exact pixel positions; stagger only the ORDER of appearance.
        if (row_index + seed) % 2 == 1:
            col_index = cols - 1 - col_index
        var px: int = col_index * cell_width
        var piece_bottom: int = bottom - row_index * cell_height
        var py: int = maxi(top, piece_bottom - cell_height)
        var w: int = mini(cell_width, int(src.size.x) - px)
        var h: int = piece_bottom - py
        if w <= 0 or h <= 0:
            continue
        draw_texture_rect_region(atlas.texture(sprite),
            Rect2(at + Vector2(px, py), Vector2(w, h)),
            Rect2(src.position + Vector2(px, py), Vector2(w, h)),
            Color.WHITE, false, true)

func _draw_low_detail(sprite: String, dest: Rect2, phase: Dictionary) -> void:
    var src: Rect2 = atlas.region(sprite)
    var top_base: float = floorf(src.size.y * 0.79)
    var bottom_roof: float = floorf(src.size.y * 0.34)
    _draw_strip(sprite, dest.position, src, top_base, src.size.y, float(phase["base"]))
    _draw_strip(sprite, dest.position, src, bottom_roof, top_base, float(phase["walls"]))
    _draw_strip(sprite, dest.position, src, 0.0, bottom_roof, float(phase["roof"]))

func _draw_strip(sprite: String, at: Vector2, source: Rect2, top: float,
        bottom: float, fraction: float) -> void:
    var height: float = floorf((bottom - top) * fraction)
    if height <= 0.0:
        return
    var y: float = bottom - height
    draw_texture_rect_region(atlas.texture(sprite),
        Rect2(at + Vector2(0, y), Vector2(source.size.x, height)),
        Rect2(source.position + Vector2(0, y), Vector2(source.size.x, height)),
        Color.WHITE, false, true)

func _draw_operations(view: Rect2) -> void:
    var active: Dictionary = {}
    for task in world.construction.jobs.values():
        if str(task.get("kind", "")) == "operate" and str(task.get("phase", "")) == "site":
            active[int(task.get("building_id", -1))] = true
    var shown := 0
    for building in world.construction.houses:
        if shown >= MAX_OPERATING:
            break
        if bool(building.get("abandoned", false)) or int(building.get("condition", 100)) < 25:
            continue
        var kind: String = str(building.get("definition_id", ""))
        var live: bool = active.has(int(building.get("id", -1)))
        var irrigating: bool = kind == "water_lift" and int(building.get("irrigation_until", 0)) > int(world.tick)
        if not live and not irrigating:
            continue
        var row: Dictionary = world.construction.catalogue.definition(kind)
        var x: int = int(building["x"])
        var y: int = int(building["y"])
        var size: Array = row.get("footprint", [1, 1])
        var foot: Vector2 = parent_renderer.top_left(x, y) + Vector2(float(size[0]) * 16.0, 27.0)
        if not view.has_point(foot):
            continue
        shown += 1
        # Pixel-art equipment is drawn over the original sprite and moves only
        # when the authoritative facility worker is actually at work.
        var pivot := foot + Vector2(0.0, -13.0)
        match kind:
            "grain_grinding_shelter", "water_lift":
                _wheel(pivot, 8.0 if kind == "grain_grinding_shelter" else 11.0, seconds, 8)
                if irrigating:
                    draw_line(pivot + Vector2(0, 10), pivot + Vector2(0, 15), Color("#76b8c6"), 2.0)
            "timber_workyard", "masonry_workyard", "weaving_house", "cordage_canopy":
                var shift: float = roundf(sin(seconds * 8.0) * 3.0)
                draw_line(pivot + Vector2(-7, shift), pivot + Vector2(7, shift), Color("#d6b992"), 2.0)
            "pottery_kiln", "charcoal_clamp", "bronze_smelter", "bronze_forge":
                for i in range(3):
                    var rise: float = float(posmod(floori(seconds * 7.0) + i * 3, 7))
                    draw_rect(Rect2((pivot + Vector2(float(i - 1) * 3, -rise)).round(),
                        Vector2.ONE * 2.0), Color("#ebb56b") if i % 2 == 0 else Color("#d97e57"))

func _wheel(pivot: Vector2, radius: float, clock: float, spokes: int) -> void:
    draw_arc(pivot, radius, 0.0, TAU, 16, Color("#b4a082"), 2.0)
    for i in range(spokes):
        var a: float = clock * 1.8 + float(i) * TAU / float(spokes)
        var direction := Vector2(cos(a), sin(a))
        draw_line((pivot + direction * 1.5).round(), (pivot + direction * (radius - 1.0)).round(),
            Color("#b4a082"), 1.0)
    draw_rect(Rect2((pivot - Vector2.ONE).round(), Vector2.ONE * 2.0), Color("#554a3a"))
