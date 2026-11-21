extends RefCounted
# Phase A2: reusable work choreography. ALL jobs, movement, materials and stages
# come from the authoritative world. This module modifies no simulation data.
# Drawing is culled to visible citizens, without nodes or animated textures.
const Art = preload("res://scripts/ui/item_pixel_art.gd")
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
        if task.is_empty() and world.regional_economy.road_jobs.has(str(id)):
            task = {"kind": "road", "phase": "site"}
        elif task.is_empty() and world.regional_economy.trade_jobs.has(str(id)):
            task = world.regional_economy.trade_jobs[str(id)].duplicate()
            task["kind"] = "merchant"
        elif task.is_empty() and world.founding.assignments.has(str(id)):
            task = {"kind": "founder", "phase": "travel", "cargo": world.inventory.citizen_inventory(id)}
        if task.is_empty() and world.local_logistics.jobs.has(str(id)):
            task = world.local_logistics.jobs[str(id)].duplicate()
            task["kind"] = "merchant"
            task["cargo"] = world.inventory.citizen_inventory(id)
        if task.is_empty() and world.food.jobs.has(str(id)):
            task = world.food.jobs[str(id)].duplicate()
            task["food_action"] = str(task["kind"])
            task["kind"] = "food"
            task["cargo"] = {str(task.get("type","grain")):int(task.get("amount",0))} if int(task.get("amount",0))>0 else {}
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
        # Cap zoom scaling so tools cannot turn into enormous wooden poles.
        var size := clampf(ts / 42.0, 0.72, 1.75)
        var cargo: Dictionary = task.get("cargo", {})
        if kind == "gather" and phase == "depot" and int(task.get("amount", 0)) > 0:
            cargo = {str(task.get("material", "wood")): int(task.get("amount", 0))}
        if kind == "merchant" and phase in ["exchange", "return"]:
            cargo = world.inventory.citizen_inventory(id)
            for good in world.food.travel_cargo.get(str(id),{}):
                if int(world.food.travel_cargo[str(id)][good])>0: cargo[good] = int(world.food.travel_cargo[str(id)][good])
        var carrying := not cargo.is_empty()
        var t := clock + float(posmod(id * 37, 97)) * 0.23
        var equipment: String = _equipped_tool(world, person)
        if carrying:
            _bundle(canvas, p + Vector2(-8, -14 + (sin(t * 4.0) if moving else 0.0)) * size, size, cargo)
        if moving:
            # Stride dust and a swinging carrying posture. No new animation actors.
            if ts >= 19.0 and sin(t * 8.0) > 0.84:
                _specks(canvas, p + Vector2(0, 9) * size, size, t, DUST, 2)
            continue
        if kind == "food":
            _action(canvas,p,size,t,"dig" if str(task.get("food_action",""))=="sow" else "sweep")
            continue
        if kind == "road":
            var road_key: String = str(world.regional_economy.road_jobs.get(str(id), ""))
            for site in world.regional_economy.road_queue:
                if str(site.get("key", "")) != road_key:
                    continue
                var target: Array = site.get("cell", [])
                if target.size() == 2 and int(person["x"]) == int(target[0]) and int(person["y"]) == int(target[1]):
                    var stage: int = int(site.get("work", 0))
                    _action(canvas, p, size, t, ["clear", "dig", "level"][posmod(stage + int(t / 2.5), 3)])
                break
            continue
        if kind == "merchant":
            var market: Vector2i = world.settlements.center(world, int(task.get("other", 1 - int(person["nation"]))))
            var homeland: Vector2i = world.settlements.center(world, world.settlements.sid(person))
            var here := Vector2i(int(person["x"]), int(person["y"]))
            if phase == "pickup" and here == homeland:
                _action(canvas, p, size, t, "pickup", equipment)
            elif phase == "exchange" and here == market:
                _action(canvas, p, size, t, "unload", equipment)
            elif phase == "return" and here == homeland:
                _action(canvas, p, size, t, "unload")
            continue
        if kind == "gather":
            if phase == "source":
                var gather_target: Array = task.get("target", [])
                if gather_target.size() == 2 and int(person["x"]) == int(gather_target[0]) and int(person["y"]) == int(gather_target[1]):
                    var material := str(task.get("material", "wood"))
                    _action(canvas, p, size, t, "chop" if material in ["wood", "plant_fibre"] else "mine", equipment)
            elif phase == "depot":
                var gather_depot: Vector2i = world.settlements.center(world, world.settlements.sid(person))
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
            var pickup_depot: Vector2i = world.settlements.center(world, world.settlements.sid(person))
            if int(person["x"]) == pickup_depot.x and int(person["y"]) == pickup_depot.y:
                _action(canvas, p, size, t, "pickup")
        elif phase == "return" and carrying:
            var return_depot: Vector2i = world.settlements.center(world, world.settlements.sid(person))
            if int(person["x"]) == return_depot.x and int(person["y"]) == return_depot.y:
                _action(canvas, p, size, t, "unload")
        elif phase == "site" and nearby:
            if carrying and kind != "repair":
                _action(canvas, p, size, t, "unload")
            elif kind == "repair":
                _action(canvas, p, size, t, "repair", equipment)
            elif kind == "demolish":
                _action(canvas, p, size, t, "demolish", equipment)
            elif not site.is_empty() and not bool(site.get("paused", false)):
                _action(canvas, p, size, t, _build_action(world, site, t), equipment)

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

# Never fabricate an equipped tool. A worker with no physical, intact tool
# animates bare hands and material contact; stones/axes/picks come from D3 custody.
static func _equipped_tool(world: RefCounted, person: Dictionary) -> String:
    var id := str(person["id"])
    var serial := str(world.toolmaking.equipped.get(id, ""))
    if serial == "" or not world.toolmaking.instances.has(serial):
        return ""
    var item: Dictionary = world.toolmaking.instances[serial]
    if str(item.get("holder", "")) != "citizen:" + id or int(item.get("condition", 0)) <= 0:
        return ""
    return str(item.get("item_id", ""))

# Compact articulated hand pose, three beats (reach/contact/recover), with
# material-specific 1-2px touches. Icons use the same shaded pixel art as D4.
static func _action(canvas: Node2D, p: Vector2, s: float, t: float,
        action: String, tool_id: String = "") -> void:
    var beat := fposmod(t * 3.6, TAU)
    var motion := sin(beat)
    var contact: bool = beat > 1.8 and beat < 2.8
    var hand := p + Vector2(5.0 + motion * 1.4, -3.0 + motion * 3.0) * s
    var forearm := p + Vector2(2, -1) * s
    var active_tool := (action == "chop" and tool_id == "stone_axe") or \
        (action in ["mine", "mason"] and tool_id == "stone_pick") or \
        (action in ["hammer", "repair", "join"] and tool_id == "hammerstone")
    if action in ["lift", "brace", "join"]:
        hand += Vector2(-1, -3) * s
    elif action in ["roof", "thatch"]:
        hand += Vector2(0, -4) * s
    elif action in ["dig", "level", "clear", "sweep"]:
        hand += Vector2(1, 2) * s
    canvas.draw_line(forearm.round(), hand.round(), Color("#b78361"), maxf(1.0, s))
    canvas.draw_rect(Rect2(hand.round(), Vector2.ONE * maxf(1.0, s * 1.5)), Color("#e6b993"))
    if active_tool:
        Art.draw_item(canvas, tool_id, hand + Vector2(2.2, -2.2) * s,
            maxf(0.7, s * 0.84))
    elif action in ["lift", "brace", "join", "saw"]:
        # A genuinely carried timber section, not a giant off-body beam.
        canvas.draw_line(hand, hand + Vector2(6, -1) * s, Color("#422f29"), maxf(1.0, 2.8 * s))
        canvas.draw_line(hand + Vector2(1, -1) * s, hand + Vector2(5, -2) * s,
            WOOD_LIGHT, maxf(1.0, s))
    elif action in ["roof", "thatch", "sweep", "clear"]:
        canvas.draw_rect(Rect2(hand + Vector2(0, -2) * s, Vector2(4, 2) * s), FIBRE)
    elif action in ["dig", "level", "mason", "mine", "demolish", "stake"]:
        canvas.draw_rect(Rect2(hand + Vector2(1, -1) * s, Vector2(3, 3) * s),
            STONE if action in ["mason", "mine", "demolish"] else EARTH)
    elif action in ["plaster", "paint"]:
        canvas.draw_rect(Rect2(hand + Vector2(1, -2) * s, Vector2(3, 2) * s),
            Color("#ddd0ad"))
    elif action in ["pickup", "unload"]:
        canvas.draw_rect(Rect2(hand + Vector2(1, 1) * s, Vector2(3, 2) * s), WOOD_LIGHT)
    elif action in ["hammer", "repair", "door"]:
        canvas.draw_rect(Rect2(hand + Vector2(1, -2) * s, Vector2(3, 2) * s), WOOD)
    if contact and action not in ["pickup", "unload", "paint", "lift"]:
        var debris := STONE if action in ["mine", "mason", "demolish"] else \
            FIBRE if action in ["thatch", "roof", "sweep"] else WOOD_LIGHT
        _specks(canvas, p + Vector2(8, 5) * s, s * 0.65, t, debris, 2)

static func _specks(canvas: Node2D, p: Vector2, s: float, t: float, colour: Color, count: int) -> void:
    for i in range(count):
        var drift := Vector2(float(i * 4 - 3), -float(i * 3 + 1) * (0.5 + absf(sin(t * 3.0)))) * s
        canvas.draw_rect(Rect2((p + drift).round(), Vector2.ONE * maxf(1.0, s * 1.5)), colour)
