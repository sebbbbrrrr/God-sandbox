# Nature — roadmap and Phase A1 baseline

Repository: `sebbbbrrrr/God-sandbox`
Engine: Godot 4.5.2 / GDScript. Mobile target: Android, GL Compatibility.

## Delivery sequence

1. **A — Environmental foundation:** audited terrain coupling, quantised temperature/moisture/fertility/biome fields, deterministic ecological clock, persisted state and inspection.
2. **B — Living vegetation:** species catalogue, seed dispersal, growth/age/death, fire scars, biome-dependent growth, visual stages.
3. **C — Climate and seasons:** regional precipitation, temperature cycles, drought, wind, snow and seasonal vegetation response.
4. **D — Wildlife:** animal entity budget, habitats, hunger/thirst/reproduction, migration and predator avoidance.
5. **E — Food webs:** producer/consumer/decomposer resources, predator-prey dynamics, biodiversity, disease and ecosystem recovery.
6. **F — Hydrology and geology:** watersheds, rivers, flooding, erosion, deposition and terrain editing interactions.
7. **G — Disasters:** forest fire spread, storms, landslides, volcanic and seismic events with recovery.
8. **H — Civilisation coupling:** farming, gathering, logging, hunting, habitat destruction/restoration and resource trade.

## A1 delivered

- `scripts/nature/nature_environment.gd` is a **self-contained environmental model**, without any new assets or UI changes.
- Four `PackedByteArray` fields use **4 bytes per cell**: 96×128 requires ~48 KiB of field storage, excluding allocation overhead.
- World seed + fixed noise frequencies establish deterministic initial conditions.
- Ecological updates touch at most 256 cells per 30 authoritative steps; frame speed does not change ecological decisions.
- Snapshot serialisation uses base64 and strict length checks; avoids corrupt or mismatched array reads.
- `tests/nature_environment_test.gd` covers seed determinism, updates, bounds, saves and corruption.

## Important integration boundary

**A1 is an engine module, not yet enabled in gameplay.** Do not claim plants are growing, ecological layers are rendered, or these values are saved by `SandboxSimulation`. A2 must compare active feature branches with main, then attach the module to the current authoritative simulation, call `step`, preserve backwards compatibility for existing save files, and expose optional debug inspection.

The default `main` simulation was inspected: `scripts/simulation.gd` contains seven terrain IDs, fixed-step updates, a seeded generator, and version-1 snapshot loading. `scripts/game.gd` handles rendering, controls and saves. Other active work may be ahead of `main`; avoid overwriting contemporary construction, climate or UI branches.

## Recommended A2 acceptance gates

1. Nature state attached on new world creation.
2. Native save roundtrip and older save migration.
3. Editor power changes update relevant environmental cells.
4. Deterministic 1× and accelerated-time equivalence under a fixed number of steps.
5. A performance test on Huawei P30, including high-speed time simulation.
6. All existing citizen, terrain brush, UI and save tests still pass.

Run (when Godot 4.5.2 is available):

```sh
godot --headless --path . --script res://tests/nature_environment_test.gd
godot --headless --path . --script res://tests/simulation_test.gd
```

No APK, build, or headless test run is claimed for A1.
