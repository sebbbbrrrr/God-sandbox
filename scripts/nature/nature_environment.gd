extends RefCounted
class_name NatureEnvironment

# Phase A1: compact, deterministic environmental state, independent of rendering.
# Values are quantised 0..255 to keep mobile saves and memory bounded.
const FORMAT_VERSION := 1
const CHUNK_SIZE := 16
const ECOLOGY_INTERVAL := 30
const CELLS_PER_UPDATE := 256

var width: int
var height: int
var world_seed: int
var ecology_tick := 0
var update_cursor := 0

var temperature := PackedByteArray()
var moisture := PackedByteArray()
var fertility := PackedByteArray()
var biome := PackedByteArray()

# Biome values are environmental labels, distinct from the existing terrain IDs.
enum Biome { OCEAN, COAST, GRASSLAND, WOODLAND, HIGHLAND, BARREN }

func _init(map_width: int, map_height: int, seed_value: int) -> void:
    width = maxi(1, map_width)
    height = maxi(1, map_height)
    world_seed = seed_value
    var size := width * height
    temperature.resize(size)
    moisture.resize(size)
    fertility.resize(size)
    biome.resize(size)

func generate(terrain: PackedByteArray) -> bool:
    if terrain.size() != width * height:
        return false
    var wet_noise := FastNoiseLite.new()
    wet_noise.seed = world_seed + 14321
    wet_noise.frequency = 0.032
    var heat_noise := FastNoiseLite.new()
    heat_noise.seed = world_seed + 29179
    heat_noise.frequency = 0.017
    for y in range(height):
        var latitude := absf((float(y) + 0.5) / float(height) * 2.0 - 1.0)
        for x in range(width):
            var i := y * width + x
            var kind: int = terrain[i]
            var heat := 0.85 - latitude * 0.63 + heat_noise.get_noise_2d(x, y) * 0.13
            if kind == 4:
                heat -= 0.22
            temperature[i] = quantize(heat)
            var wet := 0.52 + wet_noise.get_noise_2d(x, y) * 0.30
            if kind == 0:
                wet = 1.0
            elif kind == 1:
                wet += 0.15
            moisture[i] = quantize(wet)
            var soil := 0.50 + (wet - 0.5) * 0.33
            if kind == 0 or kind == 4:
                soil = 0.0
            elif kind == 5:
                soil = 0.17
            fertility[i] = quantize(soil)
            biome[i] = classify(kind, moisture[i])
    ecology_tick = 0
    update_cursor = 0
    return true

static func quantize(value: float) -> int:
    return clampi(roundi(clampf(value, 0.0, 1.0) * 255.0), 0, 255)

static func classify(terrain_kind: int, wetness: int) -> int:
    match terrain_kind:
        0:
            return Biome.OCEAN
        1:
            return Biome.COAST
        4:
            return Biome.HIGHLAND
        5:
            return Biome.BARREN
        3:
            return Biome.WOODLAND
        6:
            return Biome.GRASSLAND
        _:
            return Biome.WOODLAND if wetness > 185 else Biome.GRASSLAND

func get_cell(x: int, y: int) -> Dictionary:
    if x < 0 or y < 0 or x >= width or y >= height:
        return {}
    var i := y * width + x
    return {
        "temperature": temperature[i],
        "moisture": moisture[i],
        "fertility": fertility[i],
        "biome": biome[i]
    }

# Call once per authoritative simulation step; updates only a small batch.
# Deliberately avoids frame delta and random state to ensure reproducibility.
func step(simulation_tick: int, terrain: PackedByteArray) -> void:
    if simulation_tick % ECOLOGY_INTERVAL != 0 or terrain.size() != width * height:
        return
    ecology_tick += 1
    var limit := mini(CELLS_PER_UPDATE, width * height)
    for offset in range(limit):
        var i := (update_cursor + offset) % (width * height)
        var kind: int = terrain[i]
        if kind == 0:
            moisture[i] = 255
            fertility[i] = 0
        elif kind == 4:
            fertility[i] = 0
        elif kind == 5:
            moisture[i] = maxi(0, int(moisture[i]) - 1)
            fertility[i] = maxi(0, int(fertility[i]) - 1)
        else:
            var target := 150 if kind == 3 else 120
            if moisture[i] < target:
                moisture[i] += 1
            elif moisture[i] > target:
                moisture[i] -= 1
            if fertility[i] < 175 and moisture[i] > 85:
                fertility[i] += 1
        biome[i] = classify(kind, moisture[i])
    update_cursor = (update_cursor + limit) % (width * height)

func snapshot() -> Dictionary:
    return {
        "version": FORMAT_VERSION,
        "width": width,
        "height": height,
        "seed": world_seed,
        "ecology_tick": ecology_tick,
        "update_cursor": update_cursor,
        "temperature": Marshalls.raw_to_base64(temperature),
        "moisture": Marshalls.raw_to_base64(moisture),
        "fertility": Marshalls.raw_to_base64(fertility),
        "biome": Marshalls.raw_to_base64(biome)
    }

static func from_snapshot(data: Dictionary) -> NatureEnvironment:
    if int(data.get("version", -1)) != FORMAT_VERSION:
        return null
    var w := int(data.get("width", 0))
    var h := int(data.get("height", 0))
    if w < 1 or h < 1 or w > 4096 or h > 4096:
        return null
    var size := w * h
    var t := Marshalls.base64_to_raw(str(data.get("temperature", "")))
    var m := Marshalls.base64_to_raw(str(data.get("moisture", "")))
    var f := Marshalls.base64_to_raw(str(data.get("fertility", "")))
    var b := Marshalls.base64_to_raw(str(data.get("biome", "")))
    if t.size() != size or m.size() != size or f.size() != size or b.size() != size:
        return null
    var result := NatureEnvironment.new(w, h, int(data.get("seed", 0)))
    result.temperature = t
    result.moisture = m
    result.fertility = f
    result.biome = b
    result.ecology_tick = maxi(0, int(data.get("ecology_tick", 0)))
    result.update_cursor = clampi(int(data.get("update_cursor", 0)), 0, size - 1)
    return result
