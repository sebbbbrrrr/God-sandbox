# Human AI Phase 2 — implementation and verification

Verified 20 November 2026 on `design/citizen-ai-foundation`, starting at `8cf29bd`.
Baseline repair: `746900d`. Cognitive/social implementation: `612578f`.

The simulation now executes persistent emotional appraisal, event-backed relationships and learning, bounded episodic memory and local knowledge, utility-based goals, and bounded navigation. The renderer remains untouched. AI/simulation tests pass; full-game compilation is blocked by an existing error in a protected graphics-owned file. High-population Android performance remains unverified and requires further work.

## Implemented behaviour

- Identity: stable citizen IDs and seeded curiosity, sociability, diligence, aggression and caution; no AI consumption of the world's RNG.
- Seven affect channels: fear, anger, happiness, sadness, stress, social attachment and confidence. Damage, witnessed fire/damage, actual healing, friendly contact, conflict, support, discovery and failure drive appraisal. Personality modulates responses; fixed-tick recovery returns affect toward individual baselines.
- Directional social ties: familiarity, affinity, trust, respect, fear, rivalry and attachment. Encounters require living nearby people, safe proximity and cooldowns. Reliable positive experiences earn trust; a calm social partner can soothe distress. Different recipients appraise the same encounter differently. Autonomous encounter selection prefers acceptable partners; negative ties bias avoidance. No randomly assigned friendships or scripted groups.
- Structured episodes: kind, participants, cell, tick, significance, outcome, importance, confidence and reinforcement count. Recent duplicates reinforce; salient episodes survive longer; deterministic priority eviction and forgetting bound history. Injury/danger episodes influence navigation.
- Subjective knowledge: direct observations and shared beliefs retain source, source ID, confidence, observation/update times, hop count and visits. Mountain occlusion and radius-four perception constrain observations. Shared information loses confidence, cannot overwrite fresher direct evidence, and stops after two hops. Familiar companions have last-known positions rather than global live tracking. Unknown capitals are not goal targets.
- Learning: bounded numerical reinforcement by executable goal, with recovery toward neutral preferences. Successful discovery, harmful exploration, failed progress, rest and social outcomes update preferences. Social needs improve only through actual contact.
- Executable utility goals: explore, rest, seek safety, avoid danger, socialize, seek settlement, investigate, and return familiar. Utilities combine needs, personality, affect, learned outcomes, memory, travel cost, relationships and information confidence. Target commitments and switching bonuses reduce indecision; immediate danger interrupts routine.
- Navigation: cardinal movement; A* searches capped at 64 expanded nodes and twelve requests per world tick; routes capped at twelve cells. Partial routes and safe local fallback are supported. Every next step is checked against current terrain; direct brush flooding invalidates blocked routes. A flooded person can escape to adjacent ground; a completely trapped person stays put. No teleportation or global per-citizen pathfinding.
- Scheduling: existing one-in-three citizen update slots retained; decision deadlines stagger by ID and run every 12–21 ticks, with arrival/reflex reconsideration. Spatial buckets limit social candidate scans to 32 and results to eight. Local terrain views and derived risk maps are cached within a tick. No citizen nodes, external inference or unbounded event history.
- Inspection: `CitizenAI.inspect(state)` returns detached goals, utilities, emotions, ties, episodes, beliefs and learned preferences for a future inspector. No UI was added.

## Persistence

New snapshots use world version 3 / AI version 2. They store affect, ties, episodes, beliefs, preferences, goals, targets, routes, cooldowns, commitments and scheduling timestamps. Spatial indices and derived perception/risk caches rebuild after load.

World versions 1 and 2 remain accepted. Existing physical citizen fields, terrain, capitals and RNG state are retained; old danger records gain structured defaults and missing cognition is initialized deterministically without consuming world RNG. Nested records are sanitized and capped; duplicate citizen IDs and unsupported future schemas are rejected. Orphan active relationships are removed; historical episode participants may remain.

Snapshots now detach nested live data. RNG state is serialized as a decimal string to avoid JSON floating-point loss of 64-bit precision; old numeric states still load. Precision already lost in an older JSON save cannot be reconstructed. Current-schema JSON save/reload continuation is verified, including powers and settlement growth.

## Executed verification

Engine: official `4.5.2.stable.official.6ce3de25a` on Linux x86_64.

| Check | Result |
| --- | --- |
| Existing simulation suite | PASS — 15 assertions |
| Existing citizen AI suite | PASS — 13 assertions |
| New cognitive/social suite | PASS — 62 assertions |
| Population benchmarks | PASS — 160, 500, 1,500 spread; 1,500 crowded start |
| Bounded records, candidate scans and path work | PASS in every benchmark |
| Populated JSON restore and 30-tick continuation | PASS in every benchmark |
| Protected game/scene/project byte comparison against starting commit | PASS — unchanged |
| Full editor import and main-scene smoke test | FAIL — existing `scripts/game.gd:209` parse error |

The initial code did not compile as committed: `trait` was used as a function name, and dynamic expressions lacked explicit types in AI and its test. Those AI-scope errors were repaired before extending the system; both original suites then passed.

The remaining protected-file error is: `Cannot infer the type of "mode_name" variable because the value doesn't have a set type.` It was reproduced before and after this work. Godot returned exit code zero despite reporting it, so the test runner checks output and pass markers as well as process status. No full-game success is claimed. The graphics owner needs to resolve that declaration, for example by supplying an explicit String type.

To reproduce after Godot's initial project import/class registration:

```sh
python tests/run_ai_tests.py --godot /path/to/Godot-4.5.2
python tests/benchmark_ai.py --godot /path/to/Godot-4.5.2 --ticks 900 --output results.json
```

The first editor import currently emits the protected-file error above; the three script-driven simulation suites still execute independently after class registration.

## Measurements

Shared AMD EPYC 9V74 Linux host; headless Godot, no renderer. Each case used 120 warmup ticks and 900 measured ticks, followed by actual JSON restoration and 30-tick continuation. Population stays fixed in the benchmark by disabling settlement spawns in the fixture. Spread cases sample walkable cells deterministically; crowded cases begin on one walkable cell and then evolve autonomously.

| Population / start | Mean ms | p50 ms | p95 ms | p99 ms | Max ms | World static delta MiB | JSON MiB | Process CPU seconds |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 160 spread | 4.90 | 4.74 | 7.13 | 9.52 | 12.65 | 8.42 | 0.94 | 5.94 |
| 500 spread | 17.65 | 17.15 | 23.28 | 31.67 | 40.96 | 27.82 | 3.12 | 20.25 |
| 1,500 spread | 57.53 | 56.66 | 71.23 | 82.91 | 96.85 | 85.00 | 9.56 | 64.37 |
| 1,500 crowded start | 50.29 | 48.99 | 85.61 | 103.13 | 135.26 | 85.58 | 9.57 | 56.77 |

World static delta includes live terrain, citizens, cognition and current caches before serialization; it excludes the Godot process baseline, GPU allocation and save/reload peak allocations. Process CPU seconds include setup, warmup, serialization and continuation as well as measured steps. Raw results and cumulative child-process RSS metadata are in [citizen-ai-phase2-benchmarks.json](citizen-ai-phase2-benchmarks.json).

The 1,500-person spread case recorded 12,379 interactions during the measured interval and retained 17,620 directed ties, 17,937 episodes and 23,993 beliefs, all within per-citizen caps. The crowded case also stayed bounded. These are observed simulation outcomes, not forced story events.

At 1,500 people JSON saving took about 1.03–1.09 seconds and loading 1.20–1.35 seconds on this host. Current synchronous autosave can therefore cause a substantial stall. At the cap, both steady-step CPU cost and save allocation/cost need further optimization before mobile release. No Huawei P30, Android GL, rendered FPS or 60 FPS result is claimed.

## Files

| Status | Files | Purpose |
| --- | --- | --- |
| Modified | `scripts/ai/citizen_ai.gd` | State, event appraisal, sensing, social execution, learning/action integration and inspection |
| Created | `scripts/ai/emotions.gd`, `memory.gd`, `relationships.gd`, `perception.gd` | Affect, episodes, directed ties, local observations, shared beliefs and spatial/cached queries |
| Created | `scripts/ai/decision_engine.gd`, `learning.gd`, `navigation.gd`, `persistence.gd` | Goal utilities/commitments, reinforcement, bounded routing, migration/validation |
| Modified | `scripts/simulation.gd` | Lifecycle/spatial hooks, fixed-step preparation, real power events and versioned saves |
| Modified | `tests/citizen_ai_test.gd` | Baseline compile repair, version-neutral label and stronger walkability assertion |
| Created | `tests/citizen_cognition_test.gd`, `citizen_ai_benchmark.gd` | Behaviour scenarios, persistence, population bounds and measured step timing/memory |
| Created | `tests/run_ai_tests.py`, `benchmark_ai.py` | Strict local regression runner and sequential reproducible benchmark runner |
| Created | This report and `docs/citizen-ai-phase2-benchmarks.json` | Verified delivery evidence |

All AI modules in the table are under `scripts/ai/`; both short GDScript test names are under `tests/`.

## Remaining limits and postponed systems

- Android/device and rendered integration testing remain outstanding. Dictionary-based cold state, crowded-step spikes and synchronous save allocation require more performance work; packed state and cheaper/background serialization are the next concrete candidates.
- Navigation is local and budgeted. It does not guarantee globally optimal or successful traversal of a long maze; denied searches use local fallback and invalid targets are abandoned. Direct brush writes are observed by next-step validation and per-tick cache rebuilding; no renderer/brush revision API was changed.
- Positive and negative ties and preferred companions exist. Explicit group plans/cooperative expeditions, formal leadership, political factions, marriage, households, institutions, careers, money, food production and economies are postponed. Respect is a social score, not an implemented leadership office.
- Population fixtures establish bounded behaviour for the measured duration, not an unlimited-duration soak or mobile performance guarantee. Affect/personality values and utility weights are game tuning parameters.
- No changes to `scripts/game.gd`, `scenes/world.tscn`, `project.godot`, graphics assets, rendering, camera or UI. No graphics branch was merged or overwritten. No main merge, Actions dispatch or APK build/publication was performed.
