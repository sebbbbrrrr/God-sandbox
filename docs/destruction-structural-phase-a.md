# God Sandbox — Autonomous Destruction and Structural Damage Phase A

## Scope / integration

Base `feature/audio-world-expansion`; isolated new branch `feature/destruction-structural-phase-a`. This preserves the advanced construction + economy hierarchy and does not edit Sol's concurrently developed Phase F settlement-founding code.

This is a **real implementation of the first destruction vertical slice**, not a claim that a full rigid-body destruction engine for eleven ages is already complete.

## Authoritative destruction mechanics

`scripts/destruction/structural_destruction.gd` handles:
- Per-existing-building ignition, maximum 32 simultaneous fires, at most 12 updated per tick, with deterministic rotating budget. Fire deals material-dependent condition damage every four simulation ticks.
- Real material-based fire resilience: wood/fibre burn more readily than mineral/metal mixes. An original building age is retained as metadata, but an advanced-era label never grants automatic hazard immunity.
- Bounded deterministic fire-to-building spread within two Manhattan cells on specific damage pulses, restricted to vulnerable neighbouring completed buildings. **There is no invented tree wildfire simulation in this phase.**
- Generic explicit event entry points for earthquake, flood, storm and explosion damage. There are no new user-facing quake/storm tools yet; weather is currently visual-only in the shared base, and does not arbitrarily change simulation physics.
- Existing `building_lifecycle.damage/remove` owns final structural collapse, material ledger reconciliation, footprint release, household dirty state, archival, and repair request behavior. Destruction never silently mints salvage or creates citizen repair tasks in parallel.
- Recorded visible rubble (bounded to 192 entries; expiring after 2,400 world ticks) includes original building ID, cause, age, site and materials. **The material field is provenance, not claimable inventory.** Salvage remains controlled by existing demolition procedures.
- Version-1 destruction state embedded as an optional addition to version-2 construction snapshot; old snapshots with no destruction state load with empty fires/rubble. Corrupt/missing building references fail closed.

`scripts/simulation.gd` Fire power now ignites real building footprints rather than converting them instantly to ash and forcing terrain-driven removal. Empty/unbuilt terrain retains its original ash behavior and nearby citizens retain the preexisting hit/event response. Ocean power damages an occupied building through an explicit flood impact instead of immediately bulldozing it; unoccupied terrain still becomes ocean.

`scripts/destruction/destruction_visuals.gd` renders viewport-culled animated pixel flames, smoke flecks, cracks on damaged buildings and rubble at the actual demolished positions; no new GPU particle system, physics rigidbody swarm, overlaid low-detail 3D houses, or frame-wide procedural reconstruction. `scripts/unified_game.gd` plays an existing positional impact sound for recorded collapse events.

## Age / geography expansion compatibility

The destruction engine uses the existing catalogue building ID, material bills, original era, actual positions and local terrain. Architecture differences in eras 1–11 remain governed by `building_catalogue.gd` and the era-specific art atlas, not hardcoded destruction sprites. The same generic contract can later support damage modules for timber beams, masonry walls, iron, steel, glass, concrete, composite structures and advanced materials, without rewriting the hazard scheduler.

## Validation

The isolated `.github/workflows/destruction-phase-a-android.yml` runs Godot 4.5.2 headless import, the existing project integration tests, audio tests, a new `tests/structural_destruction_test.gd`, Android debug export and APK signature verification.

**No passing Godot build, produced APK or device test is asserted.** The current execution environment has no Godot command or Android SDK. The branch stays draft until compilation and Huawei P30 test evidence exists.

## Remaining work before full destruction engine

1. Precise material-layer structural graphs and load-bearing collapse rather than scalar building integrity alone.
2. Multi-stage failure animations for all eleven ages, with matching approved high-density pixel art, per-region geography and architecture.
3. Actual flood hydraulics, earthquakes/landslides, tornadoes, explosions and wildfire ecology, with hazard maps and physical effects. The currently integrated weather controller is intentionally visual-only.
4. Citizen evacuation, injury/rescue, firefighting, debris cleanup, inventory-preserving salvage and autonomous rebuilding. These must integrate with the full Phase F settlement logic after its branch stabilises.
5. Audio asset/mastering pass for collapse, burning, debris and rescue; multi-device Android performance profiling, save/load migration regression, lifecycle/archival and material-accounting property tests.
6. Conflict review of concurrent graphics/UI, weather, building-era atlases and Phase F once ready.
