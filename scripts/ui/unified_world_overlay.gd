extends Node2D
# Unified front-end overlay: world-space item sprites at layer 5;
# modal item inspector at layer 20. Both read the D4 physical ledger.
const ConstructionVisuals = preload("res://scripts/construction/construction_visuals.gd")
const BuildingStateVisuals = preload("res://scripts/construction/building_state_visuals.gd")
const CitizenWorkVisuals = preload("res://scripts/construction/citizen_work_visuals.gd")
const Art = preload("res://scripts/ui/item_pixel_art.gd")
const InspectorOverlay = preload("res://scripts/ui/item_overlay.gd")
var game: Node2D
var mode := "world"
var feedback_point := Vector2.ZERO
var feedback_alpha := 0.0
var feedback_radius := 0.0
var feedback_tween: Tween

func flash_feedback(point: Vector2) -> void:
    if mode != "items":
        return
    if feedback_tween != null and feedback_tween.is_running():
        feedback_tween.kill()
    feedback_point = point
    feedback_alpha = 0.28
    feedback_radius = 4.0
    feedback_tween = create_tween().set_parallel(true)
    feedback_tween.tween_property(self, "feedback_alpha", 0.0, 0.23).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    feedback_tween.tween_property(self, "feedback_radius", 26.0, 0.23).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
    queue_redraw()


func _draw() -> void:
    if game == null or game.world == null:
        return
    if mode == "items":
        if game.inspector.visible:
            InspectorOverlay.draw_panel(self, game.font, game.world, game.inspector,
                game.ui_size(), game.toolbar_height())
            if feedback_alpha > 0.001:
                draw_circle(feedback_point, feedback_radius,
                    Color("#f6d8a0", feedback_alpha * 0.42))
                draw_arc(feedback_point, feedback_radius, 0.0, TAU, 32,
                    Color("#f9e5bd", feedback_alpha), 1.7, true)
        return
    BuildingStateVisuals.draw(self, game)
    # The original atlas-frame assembly is now drawn at native resolution by
    # PixelWorldRenderer; do not paint the old generic house above it.
    if game.world_renderer == null or game.world_renderer.build_overlay == null:
        ConstructionVisuals.draw(self, game)
    CitizenWorkVisuals.draw(self, game, game.work_visual_clock)
    var world: SandboxSimulation = game.world
    var size: Vector2 = game.ui_size()
    var ts: float = game.tile_size()
    var origin: Vector2 = game.world_origin()
    # Ground caches are keyed by the actual terrain tile rather than fabricated
    # visual objects. Offscreen inventories are culled before drawing.
    if ts >= 7.0:
        for holder in world.inventory.balances:
            var label := str(holder)
            if not label.begins_with("ground:"):
                continue
            var store: Dictionary = world.inventory.balances[holder]
            if store.is_empty():
                continue
            var idx := int(label.get_slice(":", 1))
            var x := idx % world.WIDTH
            var y := int(idx / world.WIDTH)
            var p := origin + Vector2(float(x), float(y)) * ts
            p.y -= float(world.height_at(x, y)) * (12.0 / 32.0) * ts
            if p.x < -ts or p.x > size.x or p.y < -ts or p.y > size.y:
                continue
            var keys: Array = store.keys()
            keys.sort()
            var first := ""
            var total := 0
            for item_id in keys:
                var quantity := int(store[item_id])
                if quantity <= 0:
                    continue
                total += quantity
                if first == "":
                    first = str(item_id)
            if first != "":
                Art.draw_ground(self, Rect2(p, Vector2(ts, ts)), first, total,
                    game.inspector.visible and game.inspector.holder_id == label)
    # Render only tools that are actually equipped and linked to a unique
    # durable instance. Follow the interpolated walking trajectory.
    if ts >= 13.0:
        for citizen in world.citizens:
            if int(citizen["hp"]) <= 0:
                continue
            var serial := str(world.toolmaking.equipped.get(str(citizen["id"]), ""))
            if serial == "" or not world.toolmaking.instances.has(serial):
                continue
            var item: Dictionary = world.toolmaking.instances[serial]
            if str(item["holder"]) != "citizen:" + str(citizen["id"]):
                continue
            var visual: Vector2 = Vector2(int(citizen["x"]), int(citizen["y"]))
            if game.world_renderer != null and game.world_renderer.walks != null and \
                    game.world_renderer.walks.tracks.has(int(citizen["id"])):
                visual = game.world_renderer.walks.visual_tile(int(citizen["id"]))
            var p := origin + (visual + Vector2(0.5, 0.5)) * ts
            p.y -= float(world.height_at(int(citizen["x"]), int(citizen["y"]))) * (12.0 / 32.0) * ts
            if p.x < -ts or p.x > size.x + ts or p.y < -ts or p.y > size.y + ts:
                continue
            # Work choreography draws an actively used physical tool in the hand.
            # An idle/walking worker displays only a small, shaded carried item.
            if world.construction.jobs.has(str(citizen["id"])) and \
                    str(world.construction.jobs[str(citizen["id"])].get("phase", "")) == "site":
                continue
            Art.draw_item(self, str(item["item_id"]),
                p + Vector2(minf(ts * 0.20, 10.0), -minf(ts * 0.08, 4.0)),
                clampf(ts / 43.0, 0.75, 2.0))
            if int(item["condition"]) * 4 < maxi(1, int(item["max_condition"])):
                draw_rect(Rect2(p + Vector2(ts * 0.31, ts * 0.23),
                    Vector2(maxf(2.0, ts * 0.16), 2)), Color("#d98a65"))
