extends RefCounted

# Main-thread serializer. Only detached bytes may be passed to a future IO worker.
# Header: GSAI, format u32, uncompressed length u32, SHA-256 (32 bytes), Zstd payload.
const HEADER_SIZE := 44
const MAX_BYTES := 64 * 1024 * 1024
const MAGIC := [71, 83, 65, 73]

static func digest(bytes: PackedByteArray) -> PackedByteArray:
    var hash := HashingContext.new()
    hash.start(HashingContext.HASH_SHA256)
    hash.update(bytes)
    return hash.finish()

static func prepare(world: RefCounted) -> PackedByteArray:
    var minds := {}
    for id in world.citizen_ai_by_id:
        # Native shallow copies remove derived diagnostics, without copying every nested episode.
        var state: Dictionary = world.citizen_ai_by_id[id].duplicate()
        state.erase("utilities")
        state.erase("utility_rows")
        state.erase("risk_revision")
        minds[id] = state
    var view := {"version":3, "ai_version":2, "seed":world.seed, "tick":world.tick, "next_id":world.next_id,
        "citizen_ai_by_id":minds, "citizens":world.citizens, "terrain":Marshalls.raw_to_base64(world.terrain),
        "visual_elevation":Marshalls.raw_to_base64(world.visual_elevation),
        "capitals":[[world.capitals[0].x,world.capitals[0].y],[world.capitals[1].x,world.capitals[1].y]],
        "rng_state":str(world.rng.state), "routine_budget":world.ai_context.routine_budget,
        "construction":world.construction.snapshot(), "calendar":world.calendar.snapshot(),
        "lifecycle":world.lifecycle.snapshot(), "households":world.households.snapshot(),
        "food":world.food.snapshot(), "demography":world.demography.snapshot(),
        "occupations":world.occupations.snapshot(), "inventory":world.inventory.snapshot(),
        "toolmaking":world.toolmaking.snapshot()}
    # No yield, callbacks or threads between borrowing state and producing the immutable byte buffer.
    var payload := var_to_bytes(view)
    var header := PackedByteArray(MAGIC)
    header.resize(HEADER_SIZE)
    header.encode_u32(4, 1)
    header.encode_u32(8, payload.size())
    var checksum := digest(payload)
    for i in range(32):
        header[12 + i] = checksum[i]
    header.append_array(payload.compress(FileAccess.COMPRESSION_ZSTD))
    return header

static func decode(bytes: PackedByteArray) -> Variant:
    if bytes.size() < 4 or bytes.size() > MAX_BYTES:
        return null
    if bytes.slice(0, 4) != PackedByteArray(MAGIC):
        var parser := JSON.new()
        if parser.parse(bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary:
            return null
        return parser.data
    if bytes.size() < HEADER_SIZE or bytes.decode_u32(4) != 1:
        return null
    var size := bytes.decode_u32(8)
    if size <= 0 or size > MAX_BYTES:
        return null
    var payload := bytes.slice(HEADER_SIZE).decompress(size, FileAccess.COMPRESSION_ZSTD)
    if payload.size() != size or digest(payload) != bytes.slice(12, HEADER_SIZE):
        return null
    var data: Variant = bytes_to_var(payload)
    return data if data is Dictionary else null

static func replace(path: String, bytes: PackedByteArray) -> Error:
    var temporary := path + ".pending"
    var file := FileAccess.open(temporary, FileAccess.WRITE)
    if file == null:
        return FileAccess.get_open_error()
    file.store_buffer(bytes)
    file.flush()
    var error := file.get_error()
    file.close()
    if error != OK:
        DirAccess.remove_absolute(temporary)
        return error
    error = DirAccess.rename_absolute(temporary, path)
    if error != OK:
        DirAccess.remove_absolute(temporary)
    return error
