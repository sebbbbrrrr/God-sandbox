extends RefCounted
# Pure visual selection. The simulation's locally adopted technology determines
# visual age; sprites never unlock jobs, construction or item production.
const ORDINARY := [
    ["lean_to", "hide_tent", "branch_hut", "stone_shelter", "communal_canopy", "drying_rack"],
    ["wattle_house", "longhouse", "granary", "mud_store", "farmstead"],
    ["mudbrick_house", "courtyard_house", "granary", "market_court", "watch_post"],
    ["stone_villa", "courtyard_house", "tiled_workshop", "barracks"],
    ["half_timber_house", "stone_cottage", "granary", "guildhall"]
]
const CENTRES := ["hearth_circle", "meeting_lodge", "civic_hall", "colonnade", "guildhall"]

static func visual_age(world: RefCounted, nation: int) -> int:
    if nation not in [0, 1]:
        return 1
    return clampi(int(world.construction.catalogue.local_age(world, nation)), 1, 5)

static func nation_at(world: RefCounted, cell: Vector2i) -> int:
    var best := -1
    var distance := 9223372036854775807
    for nation in range(2):
        var capital: Vector2i = world.capitals[nation]
        if world.index_of(capital.x, capital.y) < 0:
            continue
        var score := cell.distance_squared_to(capital)
        if score < distance:
            distance = score
            best = nation
    return best

static func sprite(age: int, role: String, x: int, y: int, seed: int) -> String:
    var visual := clampi(age, 1, 5)
    var kind := ""
    if role == "capital":
        kind = CENTRES[visual - 1]
    elif role == "tool_area":
        kind = "tool_area"
    elif role == "primitive_shelter":
        visual = 1
        kind = "hide_tent"
    elif role == "timber_hut":
        visual = 1
        kind = "branch_hut"
    else:
        var pool: Array = ORDINARY[visual - 1]
        var h: int = (x * 374761393 + y * 668265263 + seed * 31) & 0x7fffffff
        kind = str(pool[h % pool.size()])
    var variant := "a" if ((x * 41 + y * 23 + seed * 7) & 1) == 0 else "b"
    return "era%d_%s_%s" % [visual, kind, variant]
