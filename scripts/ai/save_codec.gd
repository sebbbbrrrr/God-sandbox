extends RefCounted

# v4 world / v3 AI wire schema. In-memory dictionaries and public inspection stay readable.
# Field order is a format contract; append new columns only with a schema version change.
const TRAITS := ["curiosity", "sociability", "diligence", "aggression", "caution"]
const NEEDS := ["fatigue", "social", "safety"]
const EMOTIONS := ["fear", "anger", "happiness", "sadness", "stress", "social_attachment", "confidence"]
const GOALS := ["explore", "rest", "seek_safety", "avoid_danger", "socialize", "seek_settlement", "investigate", "return_familiar"]
const EVENTS := ["danger", "damage", "witness_damage", "healed", "support", "friendly", "discovery", "failure", "conflict"]
const CONTROL := ["id", "goal", "target", "target_id", "last_decision", "next_decision",
    "last_needs_tick", "last_emotion_tick", "last_memory_tick", "last_social_decay", "last_belief_tick",
    "last_learning_tick", "commit_until", "next_path_tick", "next_social_tick", "last_hazard_tick",
    "danger_cell", "last_outcome_tick", "blocked_steps"]

static func values(data: Dictionary, fields: Array) -> Array:
    var result: Array = []
    for field in fields:
        var value: Variant = data[field]
        result.append(value.duplicate() if value is Array else value)
    return result

static func encode(states: Dictionary) -> Dictionary:
    var result := {}
    for id in states:
        var s: Dictionary = states[id]
        var memories: Array = []
        for r in s["memories"]:
            var kind := EVENTS.find(r["kind"])
            memories.append([kind if kind >= 0 else r["kind"], r["cell"][0], r["cell"][1], r["tick"],
                r["significance"], r["outcome"], r["importance"], r["confidence"], r["repetitions"], r["participants"].duplicate()])
        var ties: Array = []
        for r in s["relationships"]:
            ties.append([r["id"], r["last_cell"][0], r["last_cell"][1], r["last_tick"], r["familiarity"],
                r["affinity"], r["trust"], r["respect"], r["fear"], r["rivalry"], r["attachment"]])
        var beliefs: Array = []
        for r in s["beliefs"]:
            beliefs.append([r["cell"][0], r["cell"][1], r["terrain"], r["confidence"],
                1 if r["source"] == "shared" else 0, r["source_id"], r["hops"], r["observed_at"], r["updated_at"], r["visits"]])
        var control := values(s, CONTROL)
        control[1] = GOALS.find(s["goal"])
        result[id] = [values(s["personality"], TRAITS), values(s["needs"], NEEDS), values(s["emotions"], EMOTIONS),
            values(s["learned"], GOALS), memories, ties, beliefs, s["route"].duplicate(true), control]
    return result

static func expand(row: Variant, fields: Array) -> Variant:
    if not row is Array or row.size() != fields.size():
        return null
    var result := {}
    for i in range(fields.size()):
        result[fields[i]] = row[i]
    return result

static func decode(rows: Variant) -> Variant:
    if not rows is Dictionary or rows.size() > 1500:
        return null
    var result := {}
    for id in rows:
        var row: Variant = rows[id]
        if not row is Array or row.size() != 9:
            return null
        var s: Variant = expand(row[8], CONTROL)
        if s == null:
            return null
        var goal: Variant = s["goal"]
        if typeof(goal) == TYPE_FLOAT and not is_finite(goal):
            return null
        if typeof(goal) not in [TYPE_FLOAT, TYPE_INT] or int(goal) < 0 or int(goal) >= GOALS.size():
            return null
        s["goal"] = GOALS[int(goal)]
        var groups := ["personality", "needs", "emotions", "learned"]
        var columns := [TRAITS, NEEDS, EMOTIONS, GOALS]
        for i in range(4):
            var group: Variant = expand(row[i], columns[i])
            if group == null:
                return null
            s[groups[i]] = group
        for i in range(4, 8):
            if not row[i] is Array or row[i].size() > (16 if i == 6 else 12):
                return null
        s["memories"] = []
        for r in row[4]:
            if not r is Array or r.size() != 10:
                return null
            var kind: Variant = r[0]
            if typeof(kind) == TYPE_FLOAT and not is_finite(kind):
                return null
            if typeof(kind) in [TYPE_INT, TYPE_FLOAT]:
                if int(kind) < 0 or int(kind) >= EVENTS.size():
                    return null
                kind = EVENTS[int(kind)]
            elif not kind is String:
                return null
            s["memories"].append({"kind":kind, "cell":[r[1],r[2]], "tick":r[3], "significance":r[4],
                "outcome":r[5], "importance":r[6], "confidence":r[7], "repetitions":r[8], "participants":r[9]})
        s["relationships"] = []
        for r in row[5]:
            if not r is Array or r.size() != 11:
                return null
            s["relationships"].append({"id":r[0], "last_cell":[r[1],r[2]], "last_tick":r[3], "familiarity":r[4],
                "affinity":r[5], "trust":r[6], "respect":r[7], "fear":r[8], "rivalry":r[9], "attachment":r[10]})
        s["beliefs"] = []
        for r in row[6]:
            if not r is Array or r.size() != 10:
                return null
            s["beliefs"].append({"cell":[r[0],r[1]], "terrain":r[2], "confidence":r[3], "source":"shared" if r[4] == 1 else "direct",
                "source_id":r[5], "hops":r[6], "observed_at":r[7], "updated_at":r[8], "visits":r[9]})
        s["route"] = row[7]
        result[id] = s
    return result
