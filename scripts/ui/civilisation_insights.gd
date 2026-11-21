extends RefCounted
## Read-only projection of Phase F authorities. Never creates resources, jobs or
## relationships; performance bars explicitly distinguish exact vs derived values.
class_name CivilisationInsights

const FOOD_BUFFER_PER_RESIDENT := 3
const MAX_DISPLAY_LINKS := 48

static func _sid(value: Dictionary) -> int:
    return int(value.get("settlement_id", value.get("nation", 0)))


static func _pct(numerator: int, denominator: int) -> int:
    return clampi(roundi(100.0 * float(numerator) / float(maxi(1, denominator))), 0, 100)


static func _add_job(jobs: Dictionary, people: Dictionary, work: Dictionary, title: String) -> void:
    for key in jobs:
        var citizen: Dictionary = people.get(str(key), {})
        if citizen.is_empty():
            continue
        var id := _sid(citizen)
        if not work.has(str(id)):
            continue
        var group: Dictionary = work[str(id)]
        if not group["workers"].has(str(key)):
            group["workers"][str(key)] = true
        group["jobs"][title] = int(group["jobs"].get(title, 0)) + 1


static func _social_snapshot(world: RefCounted, people: Dictionary) -> Dictionary:
    # Directed observations are deduplicated; they are NOT political alliances.
    var unique: Dictionary = {}
    var by_settlement: Dictionary = {}
    var between: Dictionary = {}
    for owner_key in world.citizen_ai_by_id:
        var owner_id := int(owner_key)
        if not people.has(str(owner_id)):
            continue
        var mind: Dictionary = world.citizen_ai_by_id[owner_key]
        for raw in mind.get("relationships", []):
            if not raw is Dictionary:
                continue
            var other_id := int(raw.get("id", -1))
            if other_id == owner_id or not people.has(str(other_id)):
                continue
            var pair := "%d:%d" % [mini(owner_id, other_id), maxi(owner_id, other_id)]
            if unique.has(pair):
                continue
            unique[pair] = true
            var first := _sid(people[str(owner_id)])
            var second := _sid(people[str(other_id)])
            for id in [first, second]:
                var k := str(id)
                if not by_settlement.has(k):
                    by_settlement[k] = {"ties": 0, "trust": 0, "rivalry": 0, "external": 0}
                by_settlement[k]["ties"] += 1
                by_settlement[k]["trust"] += clampi(int(raw.get("trust", 0)), 0, 100)
                by_settlement[k]["rivalry"] += clampi(int(raw.get("rivalry", 0)), 0, 100)
                if first != second:
                    by_settlement[k]["external"] += 1
            if first != second:
                var link := "%d:%d" % [mini(first, second), maxi(first, second)]
                if not between.has(link):
                    between[link] = {"a": mini(first, second), "b": maxi(first, second),
                        "ties": 0, "trust_total": 0, "rivalry_total": 0}
                between[link]["ties"] += 1
                between[link]["trust_total"] += clampi(int(raw.get("trust", 0)), 0, 100)
                between[link]["rivalry_total"] += clampi(int(raw.get("rivalry", 0)), 0, 100)
    var pairs: Array[Dictionary] = []
    for value in between.values():
        var row: Dictionary = value
        pairs.append({"a": row["a"], "b": row["b"], "ties": row["ties"],
            "trust": roundi(float(row["trust_total"]) / maxi(1, int(row["ties"]))),
            "rivalry": roundi(float(row["rivalry_total"]) / maxi(1, int(row["ties"])))})
    pairs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return int(a["ties"]) > int(b["ties"]))
    return {"local": by_settlement, "between": pairs, "observed_ties": unique.size()}


static func _routes(world: RefCounted) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for key in world.regional_economy.links:
        if result.size() >= MAX_DISPLAY_LINKS:
            break
        var link: Dictionary = world.regional_economy.links[key]
        var path: Array = link.get("path", [])
        var built := 0
        for i in range(1, path.size() - 1):
            if path[i] is Array and path[i].size() >= 2:
                if world.regional_economy.is_road(world,
                        Vector2i(int(path[i][0]), int(path[i][1]))):
                    built += 1
        result.append({"key": str(key), "a": int(link.get("a", -1)),
            "b": int(link.get("b", -1)), "status": str(link.get("status", "unplanned")),
            "built": built, "required": maxi(0, path.size() - 2),
            "path": path, "attempt": int(link.get("attempt", 0))})
    result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        var aa := int(a["a"])
        var ba := int(b["a"])
        return aa < ba or (aa == ba and int(a["b"]) < int(b["b"])))
    return result


static func capture(world: RefCounted) -> Dictionary:
    if world == null:
        return {}
    var lookup: Dictionary = {}
    for person in world.citizens:
        if int(person.get("hp", 0)) > 0:
            lookup[str(person.get("id", -1))] = person
    var work: Dictionary = {}
    var ids: Array[int] = []
    for key in world.settlements.records:
        var sid := int(key)
        ids.append(sid)
        work[str(sid)] = {"workers": {}, "jobs": {}}
    ids.sort()
    _add_job(world.construction.jobs, lookup, work, "Building")
    _add_job(world.food.jobs, lookup, work, "Food")
    _add_job(world.toolmaking.jobs, lookup, work, "Crafting")
    _add_job(world.local_logistics.jobs, lookup, work, "Hauling")
    _add_job(world.regional_economy.road_jobs, lookup, work, "Roadwork")
    _add_job(world.regional_economy.trade_jobs, lookup, work, "Trade")
    var social := _social_snapshot(world, lookup)
    var routes := _routes(world)
    var summaries: Array[Dictionary] = []
    var total_projects := 0
    var total_population := 0
    var active_towns := 0
    var connected_links := 0
    var blocked_links := 0
    for link in routes:
        if str(link["status"]) == "connected":
            connected_links += 1
        elif str(link["status"]) == "blocked":
            blocked_links += 1
    for id in ids:
        var record: Dictionary = world.settlements.get_record(id)
        var population: int = world.settlements.population(id)
        var capacity: int = world.settlements.housing(world, id)
        var materials: Dictionary = world.inventory.settlement_inventory(id)
        var food: int = world.food.total(world.food.store(id))
        var status: String = str(record.get("status", "unknown"))
        var plans: Dictionary = record.get("plan", {})
        var projects: Array[Dictionary] = []
        var buildings := 0
        var families := 0
        var farms := 0
        var hp := 0
        var hunger := 0
        var counted := 0
        var active_links := 0
        var building_links := 0
        var blocked := 0
        var road_queue := 0
        var traders := 0
        for person_id in world.settlements.residents.get(str(id), []):
            var person: Dictionary = lookup.get(str(person_id), {})
            if person.is_empty():
                continue
            counted += 1
            hp += int(person.get("hp", 0))
            hunger += clampi(int(person.get("hunger", 0)), 0, 100)
        for house in world.construction.houses:
            if _sid(house) == id:
                buildings += 1
        for family in world.households.families:
            if _sid(family) == id:
                families += 1
        for farm in world.food.farms:
            if _sid(farm) == id and not bool(farm.get("harvested", false)):
                farms += 1
        for project in world.construction.projects:
            if _sid(project) == id:
                var required: Dictionary = project.get("required", {})
                var delivered: Dictionary = project.get("delivered", {})
                var pending: Dictionary = {}
                for good in required:
                    var remaining := maxi(0, int(required[good]) - int(delivered.get(good, 0)))
                    if remaining > 0:
                        pending[str(good)] = remaining
                projects.append({"id": int(project.get("id", 0)),
                    "definition": str(project.get("definition_id", project.get("type", "Building"))),
                    "paused": bool(project.get("paused", false)),
                    "reason": str(project.get("pause_reason", "")),
                    "remaining_labour": int(project.get("remaining_labour", 0)),
                    "progress": int(project.get("progress", 0)),
                    "pending": pending, "last_tick": int(project.get("last_progress_tick", world.tick))})
        for link in routes:
            if id in [int(link["a"]), int(link["b"])]:
                match str(link["status"]):
                    "connected": active_links += 1
                    "blocked": blocked += 1
                    "building": building_links += 1
        for road in world.regional_economy.road_queue:
            if _sid(road) == id:
                road_queue += 1
        for trade in world.regional_economy.trade_jobs.values():
            if _sid(trade) == id:
                traders += 1
        var alerts: Array[String] = []
        var strengths: Array[String] = []
        if population > capacity:
            alerts.append("Housing shortfall: %d places" % (population - capacity))
        elif population > 0 and capacity >= population:
            strengths.append("Enough housing for current residents")
        if bool(record.get("food_insecure", false)):
            alerts.append("Food insecurity flagged by settlement lifecycle")
        elif population > 0 and food < population:
            alerts.append("Depot food below 1 unit per resident")
        elif population > 0 and food >= population * FOOD_BUFFER_PER_RESIDENT:
            strengths.append("Depot food buffer exceeds planning target")
        if int(record.get("security", -1)) == 0:
            alerts.append("Local hazards reported by lifecycle")
        if status == "struggling":
            alerts.append("Settlement in struggling state")
        if blocked > 0:
            alerts.append("%d blocked road connection(s)" % blocked)
        if active_links > 0:
            strengths.append("%d completed road connection(s)" % active_links)
        for project in projects:
            if project["paused"]:
                alerts.append("Project %d paused: %s" % [int(project["id"]),
                    str(project["reason"]) if str(project["reason"]) != "" else "unclassified"])
            elif int(project["remaining_labour"]) > 0 and world.tick - int(project["last_tick"]) >= 240:
                alerts.append("Project %d has had no progress for 240 ticks" % int(project["id"]))
        if int(record.get("prosperity", 0)) >= 75 and not plans.is_empty():
            strengths.append("High planner prosperity score")
        if alerts.is_empty():
            alerts.append("No monitored bottleneck identified")
        var relations: Dictionary = social["local"].get(str(id), {})
        var snapshot := {"id": id, "name": str(record.get("name", "Settlement %d" % id)),
            "nation": int(record.get("nation", 0)),
            "x": world.settlements.center(world, id).x, "y": world.settlements.center(world, id).y,
            "status": status, "specialisation": str(record.get("specialisation", "subsistence")),
            "founded_tick": int(record.get("founded_tick", 0)),
            "population": population, "housing": capacity, "buildings": buildings,
            "families": families, "farms": farms, "projects": projects,
            "jobs": work[str(id)]["jobs"], "active_workers": work[str(id)]["workers"].size(),
            "food": food, "materials": materials, "prosperity": int(record.get("prosperity", -1)),
            "prosperity_assessed": not plans.is_empty(), "stress": int(record.get("stress_ticks", 0)),
            "security": int(record.get("security", -1)),
            "food_insecure": bool(record.get("food_insecure", false)),
            "housing_pct": _pct(capacity, population) if population > 0 else -1,
            "food_pct": _pct(food, population * FOOD_BUFFER_PER_RESIDENT) if population > 0 else -1,
            "health_pct": _pct(hp, counted * 100) if counted > 0 else -1,
            "hunger_pct": _pct(hunger, counted * 100) if counted > 0 else -1,
            "active_links": active_links, "building_links": building_links,
            "blocked_links": blocked, "road_queue": road_queue, "traders": traders,
            "ties": int(relations.get("ties", 0)),
            "cross_ties": int(relations.get("external", 0)),
            "trust": roundi(float(relations.get("trust", 0)) / maxi(1, int(relations.get("ties", 0)))),
            "rivalry": roundi(float(relations.get("rivalry", 0)) / maxi(1, int(relations.get("ties", 0)))),
            "plan": plans, "history": record.get("history", []),
            "alerts": alerts, "strengths": strengths}
        summaries.append(snapshot)
        total_population += population
        total_projects += projects.size()
        if status in ["active", "legacy", "camp"]:
            active_towns += 1
    return {"tick": world.tick, "settlements": summaries, "routes": routes,
        "social": social["between"], "observed_ties": social["observed_ties"],
        "trades": world.regional_economy.recent_trades.slice(maxi(0,
            world.regional_economy.recent_trades.size() - 12)),
        "summary": {"total": summaries.size(), "active": active_towns,
            "population": total_population, "projects": total_projects,
            "connected": connected_links, "blocked": blocked_links,
            "road_queue": world.regional_economy.road_queue.size(),
            "traders": world.regional_economy.trade_jobs.size(),
            "completed_trades": world.regional_economy.completed_trades,
            "relief": world.regional_economy.completed_relief}}
