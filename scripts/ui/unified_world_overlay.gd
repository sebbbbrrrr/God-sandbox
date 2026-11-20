extends Node2D
const PhysicalSprites = preload("res://scripts/visuals/physical_sprite_atlas.gd")
# Unified front-end overlay: world-space item sprites at layer 5;
# modal item inspector at layer 20. Both read the D4 physical ledger.
const ConstructionVisuals = preload("res://scripts/construction/construction_visuals.gd")
const CitizenWorkVisuals = preload("res://scripts/construction/citizen_work_visuals.gd")
const Art = preload("res://scripts/ui/item_pixel_art.gd")
const InspectorOverlay = preload("res://scripts/ui/item_overlay.gd")
var game: Node2D
var mode := "world"

func _ready() -> void:
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _draw() -> void:
    if game == null or game.world == null:
        return
    if mode == "items":
        if game.inspector.visible:
            InspectorOverlay.draw_panel(self, game.font, game.world, game.inspector,
                game.ui_size(), game.toolbar_height())
        return
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
    # Physical settlement stores: present representative piles from real
    # conserved inventory quantities. No independent stockpile state exists.
    if ts >= 12.0:
        for nation in range(2):
            var capital: Vector2i = world.capitals[nation]
            if world.index_of(capital.x, capital.y) < 0:
                continue
            var stock: Dictionary = world.inventory.stockpile(nation)
            var kinds: Array = stock.keys()
            kinds.sort()
            var biggest_id := ""
            var biggest_count := 0
            for item_id in kinds:
                var qty := int(stock[item_id])
                if qty > biggest_count:
                    biggest_id = str(item_id)
                    biggest_count = qty
            if biggest_count <= 0:
                continue
            var p := origin + Vector2(float(capital.x), float(capital.y)) * ts
            p.y -= float(world.height_at(capital.x, capital.y)) * (12.0 / 32.0) * ts
            if p.x < -ts or p.x > size.x or p.y < -ts or p.y > size.y:
                continue
            var pile := "resource.%s.stack_large" % biggest_id if biggest_count >= 16 else (
                "resource.%s.stack_small" % biggest_id if biggest_count >= 4 else
                "item.%s" % biggest_id)
            var pos := p + Vector2(ts * 0.8, ts * 0.85)
            # Storage capacity is represented visually, not altered.
            var fullness := "low" if biggest_count < 4 else ("medium" if biggest_count < 16 else "full")
            if biggest_id == "wood":
                pile = "storage.log_pile." + fullness
            elif biggest_id in ["stone", "flint", "copper_ore", "tin_ore"]:
                pile = "storage.ore_pile." + fullness
            if not PhysicalSprites.draw(self, pile, pos, ts * 0.54):
                PhysicalSprites.draw_item(self, biggest_id, pos, ts * 0.54)
    # Toolmakers use the actual founded facility; an active bench is shown
    # only when its nation's physical toolmaking job is underway.
    if ts >= 18.0:
        for house in world.construction.houses:
            if str(house.get("type", "")) != "tool_area":
                continue
            var nation := int(house.get("nation", -1))
            if nation < 0:
                continue
            var x := int(house["x"])
            var y := int(house["y"])
            var anchor := origin + Vector2(float(x), float(y)) * ts
            anchor.y -= float(world.height_at(x, y)) * (12.0 / 32.0) * ts
            if anchor.x < -ts or anchor.x > size.x or anchor.y < -ts or anchor.y > size.y:
                continue
            var active := false
            for work in world.toolmaking.jobs.values():
                if int(work.get("nation", -1)) == nation and str(work.get("kind", "")) in [
                        "craft", "repair", "experiment"] and str(work.get("phase", "")) == "depot":
                    active = true
                    break
            var key := "workstation.flintbench.active" if active else "workstation.flintbench.idle"
            PhysicalSprites.draw(self, key, anchor + Vector2(ts * 0.55, ts * 0.32), ts * 0.39)
    # Other citizens may carry physical inventory outside construction jobs.
    # Skip construction workers whose authoritative cargo is already drawn
    # by CitizenWorkVisuals; do not create a second cargo visual.
    if ts >= 17.0:
        for citizen in world.citizens:
            if int(citizen.get("hp", 0)) <= 0:
                continue
            var id := int(citizen["id"])
            if world.construction.jobs.has(str(id)):
                continue
            var visual := Vector2(float(citizen["x"]), float(citizen["y"]))
            if game.world_renderer != null and game.world_renderer.walks != null and \
                    game.world_renderer.walks.tracks.has(id):
                visual = game.world_renderer.walks.visual_tile(id)
            var pos := origin + (visual + Vector2(0.5, 0.5)) * ts
            pos.y -= float(world.height_at(int(citizen["x"]), int(citizen["y"]))) * (12.0 / 32.0) * ts
            if pos.x < -ts or pos.x > size.x + ts or pos.y < -ts or pos.y > size.y + ts:
                continue
            var held: Dictionary = world.inventory.balances.get("citizen:" + str(id), {})
            var held_keys: Array = held.keys()
            held_keys.sort()
            for item_id in held_keys:
                if int(held[item_id]) <= 0 or world.toolmaking._managed(str(item_id)):
                    continue
                var load := "resource.%s.stack_small" % str(item_id)
                var at := pos + Vector2(-ts * 0.25, -ts * 0.30)
                if not PhysicalSprites.draw(self, load, at, ts * 0.38):
                    PhysicalSprites.draw_item(self, str(item_id), at, ts * 0.38)
                break
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
