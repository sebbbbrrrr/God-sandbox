# God Sandbox — Human AI 2.0: Cognitive, Social and Emergent Systems
Status: ARCHITECTURE DESIGN ONLY. Companion to docs/citizen-ai-architecture.md (v1).
Branch: design/citizen-ai-foundation. No implementation or rendering files modified.

## Design objective and boundaries
Build a deterministic, multi-timescale agent society: personalities, feelings, memories, beliefs, relationships, adaptive goals and eventual institutions generate coherent histories without scripted plotlines. No on-device LLM or inference service; no claim that agents are sentient. At prototype scale, 160 initial agents and maximum 1,500; Godot 4.5.2, GDScript, Android-first. Current citizens have {id,nation,x,y,hp,age}, no jobs/food/houses/ownership; current age is an update counter, not years. All advanced ambitions are gated on corresponding world systems actually existing. Renderer remains read-only.

## Cognitive layers
1. Body: health and bounded needs (hunger, energy, social contact, perceived safety), updated by elapsed fixed simulation ticks. Hunger/energy mechanics can be enabled only with meaningful replenishment mechanisms; otherwise use abstract rest/safety/social first.
2. Temperament: fixed initial curiosity, sociability, diligence, aggression, caution (v1), plus OPTIONAL empathy, patience, openness, impulsivity; avoid exploding dimensions until behaviour tests show a gain. All 0..100. Stable traits do not map deterministically to moral alignments.
3. Affect: short-term fear, anger, joy, sadness, stress, attachment activation, arousal. Fixed-point 0..100 with per-tick decay, event appraisal, saturation. Affect influences utilities, never directly writes terrain.
4. Cognitive map / beliefs: subjective records of places, threats, resources, persons and rumours, with confidence [0,100], last observed tick and source id. Distinguish observations (grounded perception) from testimony (uncertain). No omniscient reading of distant world state.
5. Autobiography: small episodic event ring plus aggregated semantic summaries (place dangerous, group trustworthy, former ally) and milestones. Meaningful events only; bounded eviction and recency/importance decay. Avoid unlimited chat logs.
6. Social model: directed relationship scores per familiar citizen: affinity [-100,+100], trust [0,100], respect [0,100], fear [0,100], obligation [-100,+100], familiarity [0,100]. Relationships are not required to be symmetric. Cap direct active ties to e.g. 12; retain small summary/kinship references separately. Don't materialize all-to-all ties.
7. Executive planning: needs + affect + values + beliefs + memory + opportunity -> goal scoring -> bounded multi-step task -> action -> feedback. Planning horizons depend on level and world support.

## An explicit information-flow contract
World events are authoritative: CitizenDamaged, CitizenBlessed, Encounter, HazardObserved, ShelterLost, SettlementChanged, CitizenDied, TerrainChanged, AgreementFulfilled, AgreementBroken (last two reserved until commitments exist).
Perception filters world events by proximity, witnesses and visibility rules; agents only update personal beliefs for witnessed/informed events. Simulation can know all state, citizen cognition cannot. Each event has deterministic (tick, sequence) identifier, source/target ids, cell and small payload. Events are batched with capped queues and stable ordering. No observer-sourced event should be replayed twice.

## Utility and action selection
Score only applicable goals: score = need_pressure + value_alignment + expected_benefit + affect_bias + relationship_pull + memory_bias - risk - travel_cost - switching_cost. Use integer/fixed-point arithmetic and deterministic tie breaks by goal enum and stable id. Threats can override routine; otherwise hysteresis prevents goal thrashing. Each candidate requires preconditions, estimated cost, target selection, validity, progress and fallback:
- Existing-world MVP: rest (abstract), inspect/explore, seek company, travel to familiar safety, avoid hazard, seek settlement.
- When resource model ships: forage, farm, manufacture, eat, trade, save resources.
- When society model ships: courtship/household, care for dependents, mentorship, bargains, leadership, politics, war.
A goal is not equivalent to an executable plan. Represent future plans as finite action sequences with bounded depth (initially 2-4) and revalidate before each execution. Unknown or impossible actions must be filtered out rather than faked.

## Learning without expensive ML
Update expectations through limited deterministic experience: predicted outcome vs observed outcome, incremental confidence and utility adjustments; use decayed, bounded tables by action category + context bucket, not neural networks. Exploration uses stable per-agent probabilistic diversity or deterministic hash noise within bounded range; no global RNG state consumption for AI. Positive outcomes may reinforce a behaviour; negative outcomes reduce preference; context prevents every citizen collapsing into a single policy. Revisit stale beliefs after direct contradiction.

## Planning hierarchy and schedules
- Reflex: every relevant event or fixed-step safety gate; e.g. imminent fire or newly unwalkable tile.
- Tactics: every ~10-30 steps per agent, staggered; choose immediate goal.
- Strategy: every 300-900 steps per agent or on life event; review aspirations, commitments and home region.
- Institution: every 150-900 steps per settlement, aggregate needs/resource/political signals; only activate when settlement entities exist.
These are proposed scales; benchmark and tune. All use simulated tick, not frame time or wall time. Prevent starvation with age-of-last-evaluation priorities under global budgets.

## Spatial awareness and navigation
Use 8x8-cell dynamic spatial buckets for social queries; static spatial cache for settlement/terrain summaries; pathfinding on current cardinal walkability. Cap path nodes, route length and requests per tick; use partial routes and safe fallback. Terrain mutation contract must publish changed cells or revision so AI invalidates routes; until integration check every next step's walkability. Preserve direct brush painting semantics. No renderer-dependent perception or sprite collision logic.

## Emotion event appraisal example
If citizen sees a fire adjacent to their current cell: threat confidence increases from observation; fear rises based on cautiousness and proximity; anger may rise if identified actor caused damage (only if evidence is known). Evaluate flee_hazard immediately, set target safer tile and execute next valid step. Later memory biases travel away from that cell. If blessed/healed, decrease perceived distress and (if witnessable source exists) update relationship. Never magically infer identity of an unseen attacker.

## Social systems and emergence
Interaction opportunities are based on nearby agents, shared settlement and availability; maintain cooldowns to prevent per-tick spam. Trust grows from reliable cooperation, declines from betrayal; affection can diverge from respect. Strong negative ties may drive avoidance; kinship/care priorities are planned once households/reproduction exist. Gossip exchanges a bounded number of beliefs, attaching provenance and lower confidence (confidence = min(source confidence, recipient trust factor) minus transmission loss). Cap gossip hops, dedupe by event id, expire old rumours. No explicit dialogue generation required. Group membership, coalitions, factions and collective decisions are future opt-in components and require actual social institution entities; avoid overfitting plot outcomes.

## Life stages and generational systems
Introduce an explicit simulated calendar/time unit before age-based biology: birth_tick, age_ticks, life_stage enum; migrate legacy age into historical counter rather than silently treating as human years. With reproduction enabled later: family graph by stable IDs, inheritance and household care. Avoid overly simplistic traits-as-genetics: inherited tendencies are bounded signals plus variation and social/environmental influences. Family bonds must persist across death as historical references, but entity deletion cleans active pointers.

## Jobs, economy, politics (interfaces only until implemented)
Agent intent interface exposes desired_task and social ties; economy returns resource availability/prices/occupation slots, political subsystem exposes offices, laws and institutional decisions. No generated money, trading outcomes, warfare or property ownership in the AI subsystem by itself. Use event records to connect these eventual systems with cognition. Avoid circular module dependencies.

## Data layout and memory budgets (proposed)
Separate lightweight hot state from cold state keyed by citizen ID:
- Hot: current goal/action, priority, next tick, needs, few emotions, target, last decision: compact packed arrays or fixed-width data if profiling warrants.
- Warm: personality/values, current beliefs (<=16), relationships (<=12), semantic memories (<=8).
- Cold: episodic memories (<=12), milestones (<=8), optional plan (<=4 steps).
Use integer enum IDs, small packed fields and spatial indices. Individual Dictionary prototypes are fine at 160; avoid heavy nested per-agent dictionaries at 1500 without measurements. Set per-agent byte budget only after Godot profiling, since GDScript Variant/Dictionary overhead is substantial. Fixed caps ensure growth O(N) not O(N²).
Event queue capped per tick; record overflow counters and deterministic drop/merge priority (never drop lethal/movement invalidation events). Aggregate duplicates.

## Serialization and migrations
Extend proposed v2 schema (or use ai_schema_version=2 within snapshot v2) with separate keyed AI state; do not alter renderer-visible citizen records. Save only authoritative persistent cognition: traits, needs, affect, beliefs, ties, memory summaries, goals and commitments, deterministic scheduler state. Rebuild spatial buckets/path caches after load. Validate IDs and values, omit orphan references, cap lengths and reject pathological payloads gracefully. A v1 save must load with legacy citizens unchanged and neutral AI baseline using seed/id-derived traits without affecting main rng. v2 snapshot continuation must be bit-for-bit deterministic under identical inputs. Explicitly record any non-replayable cache recomputations.

## Life-event and consequence design
Examples with prerequisites:
- Disaster witness -> distress + hazard memory -> avoidance/fleeing.
- Repeat cooperative encounters -> mutual but asymmetric trust -> chosen company.
- Reliable trading partnership (future economy) -> obligation, familiar trade route and reputation.
- Severe shortage (future economy) -> change occupation, migration, collective unrest.
- Leadership succession (future institutions) -> coalition negotiations or rivalry.
Emergence requires feedback loops and meaningful resource/territory constraints; do not insert scripted rebellion chance merely to create spectacle.

## Inspectability and tuning
Add optional debug state access through read-only CitizenAI.inspect(id) returning current goal, top 3 competing utilities, emotional levels, known threats, brief important memories, and relationship count. No UI edits in AI branch; graphics team can display data later. Instrument decisions per step, path nodes, social candidates, events queued/dropped, p50/p95/p99 fixed-step latency, memory footprint and save size. Maintain deterministic record/replay fixture seeds and scripted interventions for reproducible failures.

## Phase roadmap
A. Save migration, stable identity/traits, needs, deterministic scheduling; preserve current movement until gated replacement.
B. Affect and observable threats; reflex prioritization, safe movement.
C. Bounded beliefs, episodic memories, confidence and local perception.
D. Social ties, meetings, reputation exchange and bounded gossip.
E. Simple hierarchical goals, action plans and outcome learning.
F. Household, career, economy and institutional interfaces after corresponding world systems ship.
At each stage test 160/500/1500 agent cases, correctness before speed. Do not run GitHub Actions merely for a documentation phase.

## Tests and concrete acceptance scenarios
- Same seed + intervention sequence -> same citizen AI state, movements, event order, snapshot.
- Save at tick T, restore, run to T+K -> identical to uninterrupted run (including scheduler and AI).
- Old v1 saves preserve citizenship, health, original age counters, locations, terrain, capital data, global RNG state.
- Flood tile beneath a cached route -> agent never enters flooded cell, chooses fallback; brush and powers behave as before.
- Fire adjacent -> affected agent is prioritized above a non-urgent wanderer within bounded latency; event recorded only for valid witnesses.
- Repeated positive interactions increase trust; one bad interaction doesn't automatically make a lifelong enemy; social states are asymmetric when experience differs.
- Unwitnessed attack does not reveal culprit to uninformed citizen; repeated rumour may alter belief but does not turn into verified fact.
- Long 1500-citizen run keeps bounded social/memory/event data and no exponential query growth.
- UI and graphics branch are untouched; no visual outcomes claimed.

## Integration / conflicts
Renderer owns scripts/game.gd, scenes/world.tscn, project.godot, art and chunks. AI owns scripts/ai/** and AI tests. Future minimal simulation.gd hooks (citizen lifecycle, step scheduler, save/load, terrain revision) must be rebased against graphics branch when ready. Do not merge to main or publish an APK without approval. Docs are not functioning AI.
