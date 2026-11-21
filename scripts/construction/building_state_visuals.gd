extends RefCounted
const Operational = preload("res://scripts/construction/building_operational_visuals.gd")
# Bounded presentation of actual condition, abandonment and archived collapse.
# Shared pixel effects are reported separately from authored per-building states.
static func draw(canvas: Node2D, game: Node2D) -> void:
    if game.world_renderer == null: return
    var ts: float = game.tile_size()
    if ts < 9.0: return
    var origin: Vector2 = game.world_origin()
    var visible := Rect2(Vector2.ZERO,game.ui_size()).grow(ts*3.0)
    var atlas = game.world_renderer.atlas
    var s := ts/32.0
    for house in game.world.construction.houses:
        if int(house.get("condition",100))>=70 and not bool(house.get("abandoned",false)): continue
        var row: Dictionary = game.world.construction.catalogue.definition(str(house.get("definition_id","")))
        var p := origin+Vector2(float(house["x"]),float(house["y"]))*ts
        p.y -= float(game.world.height_at(int(house["x"]),int(house["y"])))*12.0*s
        if not visible.has_point(p): continue
        if int(house.get("condition",100))<70:
            var width := float(row.get("footprint",[1,1])[0])*ts
            for i in range(1+(70-int(house.get("condition",100)))/20):
                var start := p+Vector2(width*(0.28+float(i)*0.12),ts*0.3)
                var points := PackedVector2Array([start,start+Vector2(3,5)*s,start+Vector2(1,9)*s,start+Vector2(5,13)*s])
                canvas.draw_polyline(points,Color("#463e31"),maxf(1.0,s),false)
        if bool(house.get("abandoned",false)):
            _prop(canvas,atlas,"fern_cluster",p+Vector2(ts*0.5,ts*1.4),s*0.55)
    Operational.draw(canvas, game)
    # Persistent collapse provenance supplies actual ruins. Demolitions are clean.
    for entity in game.world.construction.archived:
        var history: Array = entity.get("history",[])
        if history.is_empty() or str(history[-1].get("kind",""))!="collapse": continue
        var p := origin+Vector2(float(entity["x"]),float(entity["y"]))*ts
        p.y -= float(game.world.height_at(int(entity["x"]),int(entity["y"])))*12.0*s
        if not visible.has_point(p) or game.world.construction.occupied(int(entity["x"]),int(entity["y"])): continue
        for i in range(4):
            _prop(canvas,atlas,"log" if i%2==0 else "rock_small",p+Vector2(8+i*8,25+posmod(i*7,9))*s,s*0.7)

static func _prop(canvas: Node2D, atlas: RefCounted, key: String, foot: Vector2, scale: float) -> void:
    var size: Vector2 = atlas.size_of(key)*scale
    canvas.draw_texture_rect_region(atlas.texture(key),Rect2(foot-size*Vector2(0.5,1.0),size),atlas.region(key))
