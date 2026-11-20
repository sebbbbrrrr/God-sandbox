# Human AI Phase 2.5 — verified optimisation report

Verified 20 November 2026. Branch: `design/citizen-ai-foundation`. Baseline: `476e3a7`. Implementation: `50b20ed`.

Large-population mean CPU cost improved, with a separate uncapped experiment demonstrating improvement at matched completed-work counts. Saves are smaller and faster. **The provisional CPU targets were not met.** Small-population performance is slightly worse; rendered Android/Huawei P30 performance remains unverified.

## A. Profiling and methodology

Engine: `4.5.2.stable.official.6ce3de25a`. Host: AMD EPYC 9V74 80-Core Processor, Linux-6.18.57-x86_64-with-glibc2.41. Both primary runs were serial on this same host and engine. Baseline code was frozen before edits and passed the original 90 assertions.

Both runs use seed 20261120, the same terrain and spread/crowded spawn rules, fixed population, 120 warm-up ticks and 900 measured ticks, followed by populated JSON restoration and 30-tick continuation. Settlement spawning is disabled only in the original benchmark fixture to hold population constant. Timers surround `world.step()`; serialization and verification run outside the step timer. There is no renderer/GPU workload. Wall-clock measurements never control simulation work.

An isolated source-copy profiler records inclusive times/call counts; nested counters must not be summed. In the baseline diagnostic, sensing took 5.02 seconds, selection 3.88 seconds and navigation execution 3.45 seconds within 17.15 seconds of citizen-step work. Numerical emotion/relationship/memory maintenance was much smaller. Profiling did not justify a wholesale rewrite of personality/vital storage.

Allocation patterns included temporary observation dictionaries/deep copies, redundant belief indexes, expanded utility dictionaries, repeated membership arrays, neighbourhood scans and snapshot duplication. `plan()` was entered 53,387 times, often only to reject an exhausted search budget; optimized diagnostic entries fell to 4,308 by checking before dispatch.

| Inclusive diagnostic cost per call | Before, microseconds | After, microseconds |
| --- | --- | --- |
| citizen_ai.sense | 124.04 | 110.65 |
| perception.observe | 4.78 | 2.82 |
| decision_engine.choose | 95.87 | 87.93 |
| navigation.next_step | 19.43 | 11.26 |

These diagnostic wrappers add overhead; the primary benchmark is uninstrumented. Scheduling setup and belief retention remain significant. Allocation/release churn is supported by inspected paths and measurements; no separate allocator-event or garbage-collection-pause measurement is claimed. An interned-key experiment showed no repeatable benefit and was removed.

## B. Implemented improvements

- **Stable IDs and scheduling:** integer ID-to-index/mind registries; three packed ID update slots retain canonical movement order. Earliest-deadline/ID routine scheduling is capped at 96 decisions per tick. Deferred work retains its deadline. Urgent danger bypasses that cap. Needs, emotions, movement, relationships and slow learning/forgetting continue; configuration/deadlines survive saves. No camera or wall-clock policy controls outcomes.
- **Update tiers:** immediate safety/events, staggered tactical reasoning and slower fixed-tick memory/belief/tie/learning maintenance. All citizens remain individual. Geographic aggregation and camera-driven detail reduction were deliberately deferred until conservation and behavioural equivalence can be tested. No nonexistent ambition/economy systems were fabricated.
- **Perception/social work:** integer bucket keys, reused belief indexes and in-place direct observations avoid temporary merge/copy graphs. Risk maps persist until knowledge revisions change. A packed hazard mask uses detached terrain bytes and native equality to detect legacy raw edits. Record caps, confidence/provenance, directional ties and actual encounter cooldowns remain unchanged. Additional tie indexes were not justified by the measured cost of bounded 12-record scans.
- **Navigation/terrain:** powers, settlement edits and a one-line brush change use the shared terrain setter. Live next-step walkability checks remain. The same bounded A*, route cache and safe fallback are retained; denied-budget calls avoid redundant dispatch/allocation. No global per-citizen pathfinding was added.
- **Decision data:** every applicable candidate is still scored. Integer goal IDs and packed utility rows replace retained dictionary diagnostic graphs; `CitizenAI.inspect()` materializes readable explanations when requested. This changes diagnostic storage, not available goals or utility rules.
- **Compact JSON:** default snapshots use world v4 / AI v3 fixed-order tables and goal/event IDs. Repeated labels and derived traces/indexes are omitted; behaviour, provenance, commitments, cooldowns and routes persist. The existing renderer's `JSON.stringify(world.snapshot())` call gets the smaller representation without editing its source. `from_snapshot()` accepts v1/v2/v3/v4. `snapshot(true)` exposes the older readable layout. Derived diagnostics rebuild after the next decision.
- **Safe file API:** `prepare_save_bytes()` synchronously produces detached engine-serialized/Zstd bytes with SHA-256 integrity metadata. `save_atomic()` writes/flushes a same-directory temporary file then replaces the destination; failed writes preserve the prior save. `load_file()` accepts binary and old JSON. No worker reads live state. Preparation remains synchronous and can still stall.

In-memory citizen dictionaries remain compatible with the renderer. Packed ID slots and utility traces are incremental data-oriented changes; dictionary-heavy cold records remain a future CPU/memory target.

**Integration boundary:** the binary/atomic APIs are tested but are not wired into graphics-owned save/load call sites. That integration must adopt `save_atomic()` and `load_file()` together; an older JSON-only reader cannot read the binary container.

## C. Comparable measurements

Times are milliseconds per simulation step. Memory is the live-world static allocation increase before serialization, in MiB; it excludes the Godot process baseline, GPU and save/replay peak copies.

| Population/start | Mean before → after | p95 before → after | Worst before → after | World MiB before → after |
| --- | --- | --- | --- | --- |
| 160 spread | 4.69 → 5.02 | 6.72 → 7.63 | 12.44 → 38.36 | 8.42 → 8.02 |
| 500 spread | 16.68 → 15.50 | 21.23 → 22.07 | 38.50 → 49.26 | 27.82 → 26.47 |
| 1,500 spread | 53.93 → 40.37 | 68.53 → 54.20 | 91.96 → 93.21 | 85.00 → 80.81 |
| 1,500 crowded | 48.15 → 37.14 | 79.94 → 49.10 | 117.17 → 79.57 | 85.58 → 81.21 |

Small-population mean/p95 did not consistently improve. The requested <2/<5/<10 ms mean targets and 1,500-person p95 <16 ms were not achieved. Worst-case variation is retained, not excluded. No 60 FPS or P30 result is claimed.

### Algorithm versus scheduling effects

With the new routine budget raised to 1,500, a spread run completed exactly the baseline's **111,608 decisions, 12,379 interactions and 121,070 path nodes**, with matching final relationship/memory/belief/goal-count summaries. Mean was **46.75 ms**, versus 53.93 ms before. The default 96 budget reduced mean further to 40.37 ms. This separates per-work efficiency from the intentional cadence change.

Budgeting changes trajectories: the 500-person case deferred nine decisions during warm-up even though its measured interval had no deferrals. An uncapped 500-person replay exactly matches 48 original checkpoints. The default 160-person replay matches 15 original powers/brush checkpoints. Both compare physical state, cognition and utility scores; only new derived-cache fields and scheduler configuration are normalized out. Severe-overload tests verify every citizen is eventually served. Encounters are not disabled in crowded regions.

### Save costs on an identical Phase 2 fixture

Three serial samples reuse the exact same 1,500-person Phase 2 state at tick 300. This isolates representation/IO from trajectory differences. Values below are medians in milliseconds; file sizes use decimal MB.

| Stage | Before | Compact JSON |
| --- | --- | --- |
| Snapshot generation | 167.65 | 91.42 |
| JSON encoding | 258.89 | 64.47 |
| Write + flush | 10.05 | 2.99 |
| Total JSON save | 444.48 | 159.10 |
| Read + parse + restore | 731.80 | 612.76 |

JSON size fell from **8,416,320 to 1,835,363 bytes** (8.416 → 1.835 MB). The optional atomic binary container is **552,467 bytes**, with median preparation 167.48 ms, write/flush/replace 0.47 ms and loading 716.48 ms. It adds integrity/atomic replacement and a smaller file, but is not uniformly faster than compact JSON. Disk IO was not the dominant latency.

The mature tick-1020 benchmark world contains more ties: 1,500-spread JSON snapshot/encoding improved from 739.89 to 467.27 ms; size fell from 10,027,550 to 2,251,986 bytes. Atomic preparation there took 426.08 ms. Neither path is cheap enough to promise no mobile save stall; loading still allocates and validates many dictionaries.

### Sustained run

The 1,500-spread soak passed **3,600 measured ticks**, with **47,578 interactions**, bounded records and deterministic save/replay. Mean 40.54 ms, p95 55.67 ms, worst 151.27 ms. Early-third mean was 40.39 ms and late-third 39.71 ms. Memory after histories filled was about 85.04 MB at tick 1320 and 84.92 MB at tick 3720 (roughly 81 MiB), rather than continuing to grow. This is stability for the tested duration, not an unlimited-duration guarantee.

Raw timings, counts, inclusive profiles, memory samples, save stages and fixture hash are in [citizen-ai-phase25-results.json](citizen-ai-phase25-results.json).

## D. Verification and changed files

- **118 assertions passed:** original suites (90) and new scalability/save/cache tests (28).
- **63 Phase 2 state checkpoints passed:** 15 checkpoints with 160 citizens/powers/brush edits and 48 per-tick checkpoints with 500 spread citizens and the new budget disabled.
- Four primary population cases, uncapped ablation and sustained run passed bounds and deterministic continuation. Tests cover directed ties, actual social contacts, memory-informed routing, learning, six powers, editing, population caps and old save migration.
- Save tests include malformed compact rows, checksum corruption, owned-buffer isolation, atomic round trips and failed-write preservation.
- Full import and scene smoke remain **blocked by the existing `scripts/game.gd:209` `mode_name` type-inference error**. Godot returned zero despite logging it; output was checked. No full-game startup success is claimed.
- Game/scene/project files are byte-identical to the starting commit. No rendering, asset, UI or camera edits, main merge, Actions dispatch or APK build/publication occurred.

| Files | Change |
| --- | --- |
| `scripts/ai/citizen_ai.gd`, `decision_engine.gd`, `perception.gd`, `navigation.gd` | Budget integration, packed diagnostics, indexes, observation/risk/terrain caches and bounded navigation dispatch |
| `scripts/ai/emotions.gd`, `memory.gd`, `relationships.gd`, `persistence.gd` | Reused constants, knowledge revisions and persistence validation |
| `scripts/ai/save_codec.gd`, `save_store.gd` | New compact wire format and detached/checksummed/atomic file APIs |
| `scripts/simulation.gd` | Packed update slots, registry/terrain hooks, save APIs/migrations and restore without throwaway world generation |
| `scripts/terrain_brush.gd` | One direct write delegated to the shared terrain setter |
| `tests/citizen_ai_benchmark.gd`, `citizen_cognition_test.gd`, `run_ai_tests.py` | Measurements, runner and explicitly legacy migration fixtures |
| `tests/citizen_scalability_test.gd`, `citizen_ai_trace.gd`, `citizen_ai_500_trace.gd` | Budget fairness, cache/save correctness and reference replays |
| `tests/profile_ai.py`, `save_ai_benchmark.gd`, `tests/fixtures/` | Isolated profiling, stage-separated save benchmark and original-state fixtures |

Short AI names are under `scripts/ai/`; short test names are under `tests/`. Source changes comprise 23 files plus this report and raw results.

Reproduce after Godot project import/class registration:

```sh
python tests/run_ai_tests.py --godot /path/to/Godot-4.5.2
python tests/benchmark_ai.py --godot /path/to/Godot-4.5.2 --ticks 900 --output after.json
Godot-4.5.2 --headless --path . --script tests/citizen_ai_benchmark.gd -- --population=1500 --ticks=900 --routine-budget=1500
Godot-4.5.2 --headless --path . --script tests/citizen_ai_benchmark.gd -- --population=1500 --ticks=3600
python tests/profile_ai.py --godot /path/to/Godot-4.5.2
Godot-4.5.2 --headless --path . --script tests/save_ai_benchmark.gd -- --fixture=/tmp/phase2-save.json
```

For the save comparison, generate the fixture using the helper against baseline `476e3a7`, then reuse the same file for the new build. Profiling accepts `--source <baseline-copy>` and changes only a temporary copy. The initial editor import still emits the protected-file error; script-driven suites execute after class registration.

## E. Remaining work and readiness

**Not ready to claim 5,000+ citizens, Android frame targets or stutter-free saves.** The cap remains 1,500. Remaining costs are sensing/retention/selection loops, dictionary cold records, synchronous save preparation, loading/validation and small-population scheduling overhead. Urgent mass events bypass the routine cap and can still spike. Buckets rebuild each tick, and very crowded membership removal can become expensive at larger scale.

Based on the measured hotspots, the next prototype should compare packed bounded cold-record columns and a small native batch kernel for perception, belief retention and utility scoring. A C++ GDExtension may help those demonstrated costs and ordered spatial operations; numerical decay and already bounded A* are lower priorities. No native code or Android build changes were introduced. Require matched replay tests and actual P30 measurements before adopting a native prototype.

For 5,000+: preserve stable ID-to-slot mapping, contiguous hot fields and compact bounded directed-edge/episode/belief stores. Partition count-budgeted work by stable geographic regions with deterministic event ordering, independently of the camera. Do not aggregate citizens until conservation and behavioural equivalence are tested. Keep GDScript orchestration/inspection readable and measure the whole rendered Android frame before raising the cap.

The next phase should resolve the graphics-owned compile blocker, integrate the paired atomic save/load APIs, profile a rendered P30 build, then benchmark the targeted data-layout/native prototype. Broad families/economies/governments would compound the measured limits if added before that budget is established.
