# God Sandbox — Citizen AI Foundation (Design v1)
Status: DESIGN ONLY. No simulation or renderer code changes.
Branch: design/citizen-ai-foundation

## Verified current baseline
- Godot 4.5.2 / GDScript; OpenGL Compatibility; Android first.
- scripts/simulation.gd owns a fixed-step authoritative simulation: 96x128 tiles, INITIAL_PEOPLE=160, MAX_PEOPLE=1500.
- Citizens are Array[Dictionary] with id, nation, x, y, hp, age. One of three staggered ticks performs random cardinal movement; age increments on those updates. Terrain is PackedByteArray. Walkability excludes OCEAN and MOUNTAIN.
- Simulation RNG is seeded and rng.state is serialized in v1 snapshots. Settlement growth runs every 150 ticks. Six powers have gameplay effects. The UI in scripts/game.gd reads citizens directly for drawing.
- tests/simulation_test.gd checks seeded generation, 200-tick determinism, snapshot/restore, brush semantics.
- Android workflow builds on pushes to main, not feature branches.
- Current 'age' counts updates, not real years. Existing 'town' is a terrain type, not a building entity.

## Architectural principles
1. World/SandboxSimulation remains the authoritative state; renderer only reads.
2. Preserve current citizen keys and world coordinate space for compatibility with graphics branch. Never make renderer import AI modules.
3. All AI decisions are deterministic by world seed + tick + stable citizen ID. No wall clock, randomize(), unseeded randomness, network requests or LLM dependency.
4. Fixed CPU/time budgets and staggered updates; simple reactive interrupt path for fire/danger; avoid O(N^2).
5. Simulation mechanics evolve incrementally. V1 prioritizes meaningful activities, reproducibility and persistence, not elaborate dialogue.

## Proposed modular structure (new files, integration deferred)
- scripts/ai/citizen_ai.gd — main budgeted scheduler, prioritization and action selection.
- scripts/ai/personality.gd — deterministic trait initialization and score modifiers.
- scripts/ai/needs.gd — fixed-step hunger/rest/safety/social updates.
- scripts/ai/perception.gd — local cell/neighbour queries and cached settlement signals.
- scripts/ai/memory.gd — bounded episodic records, decay, retrieval.
- scripts/ai/goal_planner.gd — utility scoring, action validation and deterministic tie-breaks.
- scripts/ai/pathfinding.gd — bounded A* or BFS on world tiles, invalidation after brush changes.
- scripts/ai/ai_serialization.gd — schema validation, v1 migration, v2 save/load.
- tests/citizen_ai_test.gd — determinism, migration, behavior, load tests.
No AI work in scripts/game.gd or art assets during this branch.

## Data schema and persistence
Keep id,nation,x,y,hp,age and augment via companion citizen_ai_by_id Dictionary initially, to reduce disruption to renderer loops. AI state per ID:
- personality: curiosity, sociability, diligence, aggression, caution (0..100, seeded immutable).
- needs: hunger, fatigue, safety, social (0..100; define 100 as urgent need for uniform scoring).
- current_goal, action, target_cell, target_id, remaining_ticks, next_decision_tick, last_update_tick.
- relationships: bounded entries {other_id, affinity, trust, last_interaction_tick}; 8-16 per citizen.
- memories: bounded 8-16 records {event_type, source_id, target_id, cell, tick, intensity, valence}; cap and aggregate duplicates.
- ai_rng_state only if a per-agent PRNG is genuinely required; prefer stateless stable hash / world seed derivation.
Cap record growth and purge dangling IDs. Keep deterministic integer scores as far as practical.
Save schema v2 with ai_version, citizen_ai_by_id and optional caches only if essential. from_snapshot() accepts v1 and v2. Derive migrated traits from seed + citizen ID; initialize needs to neutral values; preserve existing terrain, age, hp, nation, coordinates and global rng state. Do not consume world rng while migrating. Validate IDs, bounds, field types, record counts and references. Restore continuation must match uninterrupted simulation when starting from v2.

## Decision pipeline
Each fixed tick:
1. Update relevant global/settlement signals (infrequent).
2. Advance citizen needs using elapsed ticks, not frame delta.
3. Evaluate high-priority interrupts for nearby hazards (damage, fire, unwalkable tile).
4. Select a deterministic, bounded subset of agents for decision reconsideration (stagger by ID).
5. Collect nearby facts from a spatial index and capped radius.
6. Score valid actions, choose highest utility (deterministic ID/goal tie breaking).
7. Move/execute a single bounded step, update state/events, and schedule next decision.
Actions v1: idle, wander purposefully, explore, return_to_safe_tile, rest, socialize, flee_hazard, approach_settlement. Food-gathering, professions, housing and family logic remain interfaces/placeholders until resource/economy systems exist. Avoid pretending a virtual food economy exists.

Example utility score: 0..1000 fixed integer; urgency from needs; personality modifier; proximity/cost penalty; memory modifier; safety override. Hysteresis: keep current goal unless new goal score exceeds by 15%, or hazard makes it invalid. Evaluate 3-6 candidate actions rather than constructing complex plans. Events are data, not hardcoded stories.

## Memory/relationships
Record meaningful events only (damage, rescue/blessing, social encounters, home lost, settlement formed). Include event IDs if needed for dedupe. Use small bounded ring buffers and deterministic eviction: low importance/oldest first, tie by stable key. Memory affects later scores: avoid recently dangerous cells, favor familiar settlement, remember friendly/rival units. Relation scores change gradually with repeated interactions and are not guaranteed friendships after one encounter. Limit encounter candidates by spatial grid and per-agent cooldown. No quadratic every-pair loops.

## Navigation and edits
Use one-tile movement over existing cardinal grid. Compute local short path on demand with capped nodes, route caching and bounded replanning; if path unavailable, choose safe neighbor or idle. Maintain walkability checks at each movement. Every terrain edit (including direct Brush.paint_segment writing world.terrain) must notify an AI passability revision counter via a future shared change API, or invalidate paths through explicit integration hook. This is a high-priority graphics integration contract. Until it exists, validate next step every time and abandon invalid routes to guarantee correctness. Never change brush coordinate transforms.

## Performance budgets (targets, unverified)
Initial 160 citizens; cap 1500. Goal: deterministic fixed-step simulation without mobile frame stalls.
- Think/replan only 1/10 to 1/30 simulated steps per citizen depending on urgency.
- Cap pathfinding nodes per request (e.g. 64-128) and global requests per tick.
- Cache local spatial buckets (e.g. 8x8 tiles) and update on movement.
- Social encounter checks only in neighboring buckets, not all citizens.
- Enforce max memories and relationships per citizen.
- Use benchmark measurements of median and p95/p99 simulation-step CPU time; target frame budget should be measured on Huawei P30 and adjusted. No FPS guarantee.
- No citizen Node2D trees or per-agent _process callbacks.
- If profiling shows Array[Dictionary] hotspots, migrate internal hot fields to packed arrays in later phase while exposing legacy citizen dictionaries to renderer.

## Integration boundaries
Graphics branch owns scripts/game.gd, scenes/world.tscn, project.godot, terrain sprite assets and rendering changes.
AI branch will own scripts/ai/** and tests/citizen_ai_test.gd, and eventually minimal targeted edits in scripts/simulation.gd for scheduling, save/load, citizen lifecycle and movement. No changes to scripts/game.gd or terrain art.
Both branches depend on stable {id, nation, x, y, hp, age}, terrain constants, at(), index_of(), is_walkable(), apply_power(), snapshot()/from_snapshot(). Coordinate interface and IDs remain stable.
Agree on a shared terrain mutation event API before integrating cliff/terrain editing and pathfinding; tests must include direct brush writes, world powers and settlement terrain edits.
Merge order after graphics stabilizes: rebase AI branch, resolve simulation.gd overlap carefully, run complete Godot tests and Android build on an approved integration branch; main remains unchanged pending explicit approval.

## Implementation slices (future, not done)
A: Schema/versioned saves, seeded personality + needs; v1 migration and tests.
B: Utility scorer and staggered scheduler with purposeful actions; deterministic replay.
C: Hazard reaction and bounded pathfinding, brush invalidation.
D: Bounded memories and social relationships with spatial buckets.
E: Citizen inspect-data API only; renderer team can display later.
Each slice must provide deterministic unit tests and performance counters.

## Acceptance gates
- Same seed/input/tick sequence -> identical AI state, terrain and citizens.
- Saving/restoring v2 mid-simulation -> identical future results to uninterrupted run.
- Old v1 snapshots load without losing existing citizens, positions, health, nationality, age, terrain or RNG continuity.
- Six powers, settlement growth, brush drag, save/load unchanged semantically.
- Hazard movement reacts by next scheduling opportunity; citizens never step into invalid tiles.
- Bounded RAM and CPU at 160/500/1500 citizens under controlled benchmarks.
- No code/art conflicts with rendering branch; no Actions run without deliberate approval.
