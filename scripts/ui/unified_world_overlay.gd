extends Node2D
# Unified front-end overlay: world-space item sprites at layer 5;
# modal item inspector at layer 20. Both read the D4 physical ledger.
const Art = preload("res://scripts/ui/item_pixel_art.gd")
const InspectorOverlay = preload("res://scripts/ui/item_overlay.gd")
var game: Node2D
var mode := "world"

func _draw() -> void:
    if game == null or game.world == null:
        return
    if mode == "items":
        if game.inspector.visible:
            InspectorOverlay.draw_panel(self, game.font, game.world, game.inspector,
                game.ui_size(), game.toolbar_height())
        return
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
            Art.draw_item(self, str(item["item_id"]), p + Vector2(ts * 0.42, -ts * 0.05),
                ts / 17.5)
            if int(item["condition"]) * 4 < maxi(1, int(item["max_condition"])):
                draw_rect(Rect2(p + Vector2(ts * 0.31, ts * 0.23),
                    Vector2(maxf(2.0, ts * 0.16), 2)), Color("#d98a65"))
