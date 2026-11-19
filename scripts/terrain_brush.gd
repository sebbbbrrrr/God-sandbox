extends RefCounted
class_name TerrainBrush

# Tile-space geometry only. Brush dabs are generated incrementally along the
# interpolated path, so fast fingers do not leave holes between touch events.
static func is_terrain_power(power: int) -> bool:
    return power == 0 or power == 2 or power == 5

static func stroke_cells(a: Vector2i, b: Vector2i, radius: int) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    var seen: Dictionary = {}
    var steps: int = maxi(absi(b.x - a.x), absi(b.y - a.y))
    for i in range(steps + 1):
        var progress := float(i) / float(maxi(steps, 1))
        var point := Vector2i(roundi(lerpf(float(a.x), float(b.x), progress)),
            roundi(lerpf(float(a.y), float(b.y), progress)))
        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                if dx * dx + dy * dy > radius * radius:
                    continue
                var cell := point + Vector2i(dx, dy)
                if not seen.has(cell):
                    seen[cell] = true
                    result.append(cell)
    return result

static func paint_segment(world: SandboxSimulation, power: int, start: Vector2i,
        finish: Vector2i, radius: int) -> int:
    if not is_terrain_power(power):
        return 0
    var target := SandboxSimulation.MEADOW
    if power == 2:
        target = SandboxSimulation.FOREST
    elif power == 5:
        target = SandboxSimulation.OCEAN
    var changed := 0
    for cell in stroke_cells(start, finish, radius):
        var idx := world.index_of(cell.x, cell.y)
        if idx < 0:
            continue
        if world.terrain[idx] == target:
            continue
        # Grow forest cannot be applied to ocean; mirror world power semantics.
        if power == 2 and world.terrain[idx] == SandboxSimulation.OCEAN:
            continue
        world.terrain[idx] = target
        changed += 1
    return changed
