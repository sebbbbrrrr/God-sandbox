extends RefCounted

static func create(id: int, nation: int, row: Dictionary, cell: Vector2i,
        orientation: int, tick: int) -> Dictionary:
    return {"id": id, "nation": nation, "definition_id": row["id"],
        "x": cell.x, "y": cell.y, "orientation": orientation, "stage": 0,
        "stage_work": 0, "stage_started": false, "progress": 0, "reserved": 0,
        "required": row["materials"].duplicate(true), "delivered": {}, "consumed": {},
        "remaining_labour": int(row["labour"]), "assigned_workers": [],
        "skills": row["skills"].duplicate(true), "tools": row["tools"].duplicate(true),
        "quality": 100, "paused": false, "pause_reason": "", "accessible": true,
        "created_tick": tick, "last_progress_tick": tick, "history": [],
        "original_terrain": []}

static func history(entity: Dictionary, tick: int, kind: String, detail: Dictionary = {}) -> void:
    var rows: Array = entity.get("history", [])
    rows.append({"tick": tick, "kind": kind, "detail": detail.duplicate(true)})
    # Per-entity bounded recent history; origin fields retain provenance forever.
    if rows.size() > 32:
        rows.pop_front()
    entity["history"] = rows
