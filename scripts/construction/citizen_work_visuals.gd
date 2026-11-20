extends RefCounted
# Phase A2: reusable work choreography. ALL jobs, movement, materials and stages
# come from the authoritative world. This module modifies no simulation data.
# Drawing is culled to visible citizens, without nodes or animated textures.
const DUST := Color("#c4ad87")
const WOOD := Color("#93613c")
const WOOD_LIGHT := Color("#d2aa6a")
const STONE := Color("#a2a89f")
const IRON := Color("#c4c9c3")
const EARTH := Color("#71533b")
const FIBRE := Color("#bea56d")

static func draw(canvas: Node2D, game: Node2D, clock: float) -> void:
    var world = game.world
    var ts: float = game.tile_size()
    if ts < 9.0:
        return
    var viewport := Rect2(Vector2.ZERO, game.ui_size()).grow(ts * 2.0)
    var origin: Vector2 = game.world_origin()
    var jobs: Dictionary = world.construction.jobs
    for person in world.citizens:
        if int(person.get("hp", 0)) <= 0:
            continue
        var id: int = int(person["id"])
        var task: Dictionary = jobs.get(str(id), {})
        if task.is_empty():
            continue
        var kind := str(task.get("kind", ""))
        var phase := str(task.get("phase", ""))
        var tile := Vector2(float(person["x"]), float(person["y"]))
        var moving := false
        if game.world_renderer != null and game.world_renderer.walks != null:
            var walks = game.world_renderer.walks
            if walks.tracks.has(id):
                tile = walks.visual_tile(id)
                moving = walks.walk_phase(id) >= 0.0
        var p: Vector2 = origin + (tile + Vector2(0.5, 0.5)) * ts
        p.y -= float(world.height_at(int(person["x"]), int(person["y"]))) * (12.0 / 32.0) * ts
        if not viewport.has_point(p):
            continue
        var size := ts / 32.0
        var cargo: Dictionary = task.get("cargo", {})
        if kind == "gather" and phase == "depot" and int(task.get("amount", 0)) > 0:
            cargo = {str(task.get("material", "wood")): int(task.get("amount", 0))}
        var carrying := not cargo.is_empty()
        var t := clock + float(posmod(id * 37, 97)) * 0.23
        if carrying:
            _bundle(canvas, p + Vector2(-8, -14 + (sin(t * 4.0) if moving else 0.0)) * size, size, cargo)
        if moving:
            # Stride dust and a swinging carrying posture. No new animation actors.
            if ts >= 19.0 and sin(t * 8.0) > 0.84:
                _specks(canvas, p + Vector2(0, 9) * size, size, t, DUST, 2)
            continue
        if kind == "gather":
            if phase == "source":
                var gather_target: Array = task.get("target", [])
                if gather_target.size() == 2 and int(person["x"]) == int(gather_target[0]) and int(person["y"]) == int(gather_target[1]):
                    var material := str(task.get("material", "wood"))
                    _action(canvas, p, size, t, "chop" if material in ["wood", "plant_fibre"] else "mine")
            elif phase == "depot":
                var gather_depot: Vector2i = world.capitals[int(person["nation"])]
                if int(person["x"]) == gather_depot.x and int(person["y"]) == gather_depot.y:
                    _action(canvas, p, size, t, "unload")
            continue
        var destination := Vector2i(-999, -999)
        var site: Dictionary = {}
        if kind in ["repair", "demolish"]:
            var house: Dictionary = world.construction.building_by_id(int(task.get("building_id", 0)))
            if not house.is_empty():
                destination = Vector2i(int(house["x"]), int(house["y"]))
        else:
            site = world.construction.site_by_id(int(task.get("project_id", 0)))
            if not site.is_empty():
                destination = Vector2i(int(site["x"]), int(site["y"]))
        var nearby := absi(int(person["x"]) - destination.x) <= 1 and absi(int(person["y"]) - destination.y) <= 1
        if phase == "depot":
            var pickup_depot: Vector2i = world.capitals[int(person["nation"])]
            if int(person["x"]) == pickup_depot.x and int(person["y"]) == pickup_depot.y:
                _action(canvas, p, size, t, "pickup")
        elif phase == "return" and carrying:
            var return_depot: Vector2i = world.capitals[int(person["nation"])]
            if int(person["x"]) == return_depot.x and int(person["y"]) == return_depot.y:
                _action(canvas, p, size, t, "unload")
        elif phase == "site" and nearby:
            if carrying and kind != "repair":
                _action(canvas, p, size, t, "unload")
            elif kind == "repair":
                _action(canvas, p, size, t, "repair")
            elif kind == "demolish":
                _action(canvas, p, size, t, "demolish")
            elif not site.is_empty() and not bool(site.get("paused", false)):
                _action(canvas, p, size, t, _build_action(world, site, t))

# A visible sub-action is selected from the real construction stage and work
# counter. Nothing here adds labour, speeds progress or consumes resources.
static func _build_action(world: RefCounted, site: Dictionary, clock: float) -> String:
    var row: Dictionary = world.construction.catalogue.definition(str(site["definition_id"]))
    var stage_index: int = int(site.get("stage", 0))
    var stages: Array = row.get("stages", [])
    if stage_index >= stages.size():
        return "finish"
    var name := str(stages[stage_index].get("id", ""))
    var progress := int(site.get("stage_work", 0))
    var alternate := int(floor(clock / 2.5)) % 2
    if name == "site_preparation":
        return ["clear", "dig", "stake", "level"][posmod(progress + alternate, 4)]
    if name == "structural_assembly":
        return ["saw", "mason", "lift", "hammer", "join", "brace"][posmod(progress + alternate, 6)]
    if name == "finishing":
        return ["roof", "thatch", "plaster", "door", "paint", "sweep"][posmod(progress + alternate, 6)]
    return "hammer"

static func _bundle(canvas: Node2D, at: Vector2, scale: float, cargo: Dictionary) -> void:
    var wood: int = int(cargo.get("wood", 0))
    var stone: int = int(cargo.get("stone", 0))
    var fibre: int = int(cargo.get("plant_fibre", 0))
    if wood > 0 or fibre > 0:
        for i in range(mini(3, maxi(wood, fibre))):
            var a := at + Vector2(0, 3 * i) * scale
            canvas.draw_line(a, a + Vector2(12, -2) * scale, WOOD if wood > 0 else FIBRE, maxf(1.0, 2.5 * scale))
        canvas.draw_line(at + Vector2(6, -1) * scale, at + Vector2(7, 9) * scale, WOOD_LIGHT, maxf(1.0, scale))
    if stone > 0 or (wood == 0 and fibre == 0):
        var q := at + Vector2(5, 1) * scale
        canvas.draw_colored_polygon(PackedVector2Array([q, q + Vector2(5, -4) * scale, q + Vector2(11, 0) * scale, q + Vector2(8, 7) * scale, q + Vector2(1, 6) * scale]), STONE)

static func _action(canvas: Node2D, p: Vector2, s: float, t: float, action: String) -> void:
    # Three key motions in one cycle: wind-up, strike/contact, recovery.
    var pulse := sin(t * 4.5)
    var beat := fposmod(t * 4.5, TAU)
    var strike := beat > 2.1 and beat < 3.1
    var tip := p + Vector2(8, -7 + pulse * 5.0) * s
    var contact := p + Vector2(11, 4) * s
    var colour := WOOD
    var head := IRON
    match action:
        "clear", "sweep":
            tip = p + Vector2(8 + pulse * 5.0, 7) * s
            head = FIBRE
        "dig", "level":
            tip = p + Vector2(9, 1 + pulse * 7.0) * s
            head = EARTH
        "stake":
            tip = p + Vector2(9, -6 + pulse * 8.0) * s
        "saw":
            tip = p + Vector2(6 + pulse * 6.0, 2) * s
        "mason", "mine":
            tip = p + Vector2(8, -9 + pulse * 9.0) * s
        "lift", "brace", "join":
            tip = p + Vector2(5, -15 + pulse * 3.0) * s
            colour = WOOD_LIGHT
        "roof", "thatch":
            tip = p + Vector2(6, -16 + pulse * 5.0) * s
            head = FIBRE
        "plaster", "paint":
            tip = p + Vector2(10, -13 + pulse * 4.0) * s
            head = Color("#ddd0ad")
        "door", "repair", "hammer":
            tip = p + Vector2(9, -11 + pulse * 10.0) * s
        "demolish":
            tip = p + Vector2(11, -15 + pulse * 14.0) * s
        "chop":
            tip = p + Vector2(9, -13 + pulse * 12.0) * s
        "pickup", "unload":
            tip = p + Vector2(7, 1 + pulse * 6.0) * s
            head = WOOD_LIGHT
        _:
            tip = p + Vector2(8, -7 + pulse * 5.0) * s
    # Arm and hand always attach to the same actor location.
    canvas.draw_line(p + Vector2(2, -1) * s, tip, Color("#d3aa86"), maxf(1.0, 2.0 * s))
    if action in ["lift", "brace", "join"]:
        canvas.draw_line(tip + Vector2(-7, -1) * s, tip + Vector2(11, -1) * s, colour, maxf(2.0, 3.0 * s))
        canvas.draw_line(p + Vector2(-2, -2) * s, tip + Vector2(-5, -1) * s, Color("#d3aa86"), maxf(1.0, 2.0 * s))
    elif action in ["pickup", "unload", "paint", "plaster", "thatch", "clear", "sweep"]:
        canvas.draw_rect(Rect2(tip.round(), Vector2(6, 3) * s), head)
    elif action == "saw":
        canvas.draw_line(tip, tip + Vector2(12, 1) * s, IRON, maxf(1.0, 2.0 * s))
        for i in range(3):
            canvas.draw_line(tip + Vector2(i * 4, 1) * s, tip + Vector2(i * 4 + 2, 3) * s, IRON, maxf(1.0, s))
    else:
        canvas.draw_line(tip, tip + Vector2(7, -7) * s, colour, maxf(1.0, 2.0 * s))
        canvas.draw_rect(Rect2((tip + Vector2(4, -9) * s).round(), Vector2(7, 3) * s), head)
    if strike:
        var debris := DUST
        if action in ["saw", "chop", "join", "brace"]:
            debris = WOOD_LIGHT
        elif action in ["mine", "mason", "demolish"]:
            debris = STONE
        elif action in ["roof", "thatch"]:
            debris = FIBRE
        if action not in ["pickup", "unload", "lift", "paint"]:
            _specks(canvas, contact, s, t, debris, 3)

static func _specks(canvas: Node2D, p: Vector2, s: float, t: float, colour: Color, count: int) -> void:
    for i in range(count):
        var drift := Vector2(float(i * 4 - 3), -float(i * 3 + 1) * (0.5 + absf(sin(t * 3.0)))) * s
        canvas.draw_rect(Rect2((p + drift).round(), Vector2.ONE * maxf(1.0, s * 1.5)), colour)
