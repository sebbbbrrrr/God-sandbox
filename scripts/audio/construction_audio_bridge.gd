extends RefCounted
## Observes *authoritative* completed construction work, not rendered poses.
## Does not mutate world, construction jobs, resource counters, or simulation RNG.
const WorkVisuals = preload("res://scripts/construction/citizen_work_visuals.gd")
const LivingWorldAudio = preload("res://scripts/audio/living_world_audio.gd")
const MAX_EVENTS_PER_STEP := 4
var _last_tick := -1
var _site_progress := {}
var _jobs := {}
var _building_conditions := {}
var _pending: Dictionary = {}
const MAX_PENDING := 12

func reset() -> void:
    _last_tick = -1
    _site_progress.clear()
    _jobs.clear()
    _building_conditions.clear()
    _pending.clear()

static func classify_build_action(action: String) -> String:
    if action in ["clear", "dig", "level", "stake"]:
        return "dig"
    if action == "saw":
        return "saw"
    if action in ["mason", "hammer", "join", "brace", "lift", "roof",
            "thatch", "plaster", "door", "paint", "sweep"]:
        return "build"
    return ""

func observe(world: Object, living: RefCounted, audio: Node, origin: Vector2,
        cell_pixels: float, viewport_size: Vector2, panel_height: float,
        animation_clock: float) -> int:
    if int(world.tick) == _last_tick:
        return 0
    if int(world.tick) < _last_tick:
        reset()
    var has_baseline := _last_tick >= 0
    _last_tick = int(world.tick)
    var now_progress := {}
    var now_jobs := {}
    var now_condition := {}
    var emitted := 0
    var positions := {}
    for person in world.citizens:
        if int(person.get("hp", 0)) > 0:
            positions[str(person["id"])] = Vector2i(int(person["x"]), int(person["y"]))
    for job_id in world.construction.jobs:
        var job: Dictionary = world.construction.jobs[job_id]
        now_jobs[str(job_id)] = {"kind": str(job.get("kind", "")),
            "phase": str(job.get("phase", "")),
            "amount": int(job.get("amount", 0)),
            "cargo": job.get("cargo", {}).duplicate(true),
            "project_id": int(job.get("project_id", 0)),
            "building_id": int(job.get("building_id", 0)),
            "remaining": int(job.get("remaining", 0)),
            "material": str(job.get("material", ""))}
    for site in world.construction.projects:
        var site_id := int(site["id"])
        now_progress[site_id] = int(site.get("progress", 0))
        if not has_baseline or not _site_progress.has(site_id):
            continue
        if int(now_progress[site_id]) <= int(_site_progress[site_id]):
            continue
        for job_id in now_jobs:
            var job: Dictionary = now_jobs[job_id]
            if str(job.get("kind", "")) != "build" or int(job.get("project_id", 0)) != site_id:
                continue
            if not positions.has(str(job_id)):
                continue
            var cell: Vector2i = positions[str(job_id)]
            var location := Vector2i(int(site["x"]), int(site["y"]))
            if absi(cell.x - location.x) > 1 or absi(cell.y - location.y) > 1:
                continue
            var point := LivingWorldAudio.world_to_screen(cell, origin, cell_pixels)
            if not LivingWorldAudio.screen_visible(point, viewport_size, panel_height):
                continue
            var action: String = WorkVisuals._build_action(world, site, animation_clock)
            var audio_action := classify_build_action(action)
            if audio_action != "":
                if _queue_contact(audio_action, int(job_id), int(world.tick), point):
                    emitted += 1
            break
        if emitted >= MAX_EVENTS_PER_STEP:
            break
    if has_baseline and emitted < MAX_EVENTS_PER_STEP:
        for job_id in now_jobs:
            if emitted >= MAX_EVENTS_PER_STEP:
                break
            if not _jobs.has(job_id) or not positions.has(job_id):
                continue
            var job: Dictionary = now_jobs[job_id]
            var previous: Dictionary = _jobs[job_id]
            var action := ""
            if str(job["kind"]) == "gather":
                if str(previous["phase"]) == "source" and str(job["phase"]) == "depot" and int(job["amount"]) > 0:
                    action = "chop" if str(job["material"]) in ["wood", "plant_fibre"] else "mine"
            elif str(job["kind"]) == "build":
                if str(previous["phase"]) == "depot" and str(job["phase"]) == "site" and not job["cargo"].is_empty():
                    action = "deliver"
                elif str(previous["phase"]) == "site" and not previous["cargo"].is_empty() and job["cargo"].is_empty():
                    action = "deliver"
            elif str(job["kind"]) in ["repair", "demolish"] and int(job["remaining"]) < int(previous["remaining"]):
                action = str(job["kind"])
            if action == "":
                continue
            var point := LivingWorldAudio.world_to_screen(positions[job_id], origin, cell_pixels)
            if LivingWorldAudio.screen_visible(point, viewport_size, panel_height):
                if _queue_contact(action, int(job_id), int(world.tick), point):
                    emitted += 1
    # Detect completed repairs even when a job is removed in the same tick.
    for house in world.construction.houses:
        now_condition[int(house["id"])] = int(house.get("condition", 0))
    _site_progress = now_progress
    _jobs = now_jobs
    _building_conditions = now_condition
    return emitted

# Sound is queued only after the authoritative simulation has committed work.
# The display then fires it at the exact same contact beat as _action() visuals.
func _queue_contact(action: String, worker_id: int, marker: int, point: Vector2) -> bool:
    if worker_id <= 0 or action == "":
        return false
    if _pending.size() >= MAX_PENDING and not _pending.has(worker_id):
        return false
    _pending[worker_id] = {"action": action, "marker": marker, "point": point}
    return true

static func contact_cycle(clock: float, worker_id: int) -> int:
    var phase: float = (clock + float(posmod(worker_id * 37, 97)) * 0.23) * 4.5
    # Each 2*pi visual cycle has contact when wrapped phase enters [2.1,3.1].
    return int(floor(phase / TAU))

static func contact_crossed(previous_clock: float, current_clock: float, worker_id: int) -> bool:
    if current_clock <= previous_clock:
        return false
    var offset := float(posmod(worker_id * 37, 97)) * 0.23
    var before: float = (previous_clock + offset) * 4.5
    var after: float = (current_clock + offset) * 4.5
    return int(floor((after - 2.1) / TAU)) > int(floor((before - 2.1) / TAU))

func flush_contacts(living: RefCounted, audio: Node, previous_clock: float,
        current_clock: float) -> int:
    var played := 0
    var remove: Array = []
    for worker_id in _pending:
        if not contact_crossed(previous_clock, current_clock, int(worker_id)):
            continue
        var row: Dictionary = _pending[worker_id]
        if living.on_work_marker(audio, str(row["action"]), int(worker_id),
                int(row["marker"]), row["point"]):
            played += 1
        # An attempted event must not replay on the next contact cycle, even
        # if throttled by the mixer's voice budget or mute setting.
        remove.append(worker_id)
    for worker_id in remove:
        _pending.erase(worker_id)
    return played
