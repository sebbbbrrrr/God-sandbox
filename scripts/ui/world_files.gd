extends RefCounted
## Atomic frontend save adapter; the existing simulation snapshot is unchanged.
static func write_world(world: RefCounted, path: String) -> Error:
    var temporary := path + ".tmp"
    var file := FileAccess.open(temporary, FileAccess.WRITE)
    if file == null:
        return FileAccess.get_open_error()
    file.store_string(JSON.stringify(world.snapshot(), "", true, true))
    file.flush()
    var error := file.get_error()
    file.close()
    if error != OK:
        return error
    return DirAccess.rename_absolute(temporary, path)

static func read_snapshot(path: String) -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parser := JSON.new()
    if parser.parse(file.get_as_text()) != OK:
        return {}
    var value: Variant = parser.data
    if value is Dictionary and int(value.get("version", 0)) in [1, 2, 3, 4] and value.has("terrain") and value.has("citizens"):
        # Restore JSON's exact integral numbers before authoritative validation.
        value = _restore_numbers(value)
        for pair in [["food", "techniques"], ["demography", "tombstones"]]:
            var domain: Variant = value.get(pair[0], {})
            if domain is Dictionary and domain.has(pair[1]):
                var incoming: Variant = domain[pair[1]]
                if not incoming is Array:
                    return {}
                var rows: Array[Dictionary] = []
                for row in incoming:
                    if not row is Dictionary:
                        return {}
                    rows.append(row)
                domain[pair[1]] = rows
        return value
    return {}

static func _restore_counts(counts: Variant) -> void:
    if not counts is Dictionary:
        return
    for key in counts:
        var number: Variant = counts[key]
        if typeof(number) == TYPE_FLOAT and is_finite(number) and number == floor(number) and absf(number) <= 9007199254740991.0:
            counts[key] = int(number)

static func _restore_numbers(value: Variant) -> Variant:
    if value is Dictionary:
        for key in value:
            value[key] = _restore_numbers(value[key])
    elif value is Array:
        for index in range(value.size()):
            value[index] = _restore_numbers(value[index])
    elif typeof(value) == TYPE_FLOAT and is_finite(value) and value == floor(value) and absf(value) <= 9007199254740991.0:
        return int(value)
    return value
