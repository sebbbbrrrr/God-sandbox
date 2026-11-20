# Universal autonomous construction — Phase A

Status: integrated construction vertical slice; draft review branch. No production merge.

## Audit and integration base

Audited 20 November 2026. Base: `integration/unified-god-sandbox-android-20261120` at `e0a62c0bdcb1e88450bae0a16896d79ba887c5ac` (PR #16). It already includes the D1–D4 item stack and C1 occupations, unlike main or the independent pixel-art branch. Branch: `feature/universal-construction-phase-a`.

The isolated branch also integrates the existing pinch-fix branch through `304d804384bc2b9eb040481c6278446d0d768d46` (PR #19), and cherry-picks frame pacing `b50342c50e8895419c1e3104541d50d72a9df176` (PR #17). Source branches and main are untouched. Finer ground subtiles (PR #18) remain separate. No Actions workflow was dispatched or added to trigger on this feature branch. The Android project now references its existing icon explicitly, resolving a local export diagnostic.

| Existing subsystem | Audit result and reuse |
|---|---|
| Citizen AI | Functional fixed-step, staggered perception/cognition, personality, memory, relationships and survival priorities. Construction continues through its existing `work_step` hook. |
| Movement | Functional bounded A* plus safe fallback in `navigation.gd`; interpolation remains render-only. Construction uses these movements and `ai_context.moved`. |
| Professions | C1 skill XP, work, teaching and local adopted capabilities are functional. Most later-era occupations are definitions with runtime work disabled. |
| Eleven ages | Reuse C1's 1–11 indices and names. No global calendar-driven era unlock system exists. Building provenance reports the local capability evidence floor. |
| Items | D1 provides 100 definitions and 35 abilities. D2 provides conserved custody; D3 provides the playable early toolmaking subset and serial equipment; D4 supplies inspection/actions. The entire broad catalogue is not autonomous production. |
| Prior construction | Functional one-cell housing and finite wood/stone gathering; hard-coded costs, one worker/project, no site inventory or stages. Replaced its house scheduler while preserving gathering/navigation APIs. |
| Households | Actual home IDs and bed capacity are functional. Completed dwellings feed this existing authority. |
| Terrain | 96×128 authoritative grid, two nations and terrain-edit callbacks. Elevation is visual-only, not physical structural simulation. |
| Rendering | Cached atlas/chunks, angled sprites, interpolated citizens, weather and ash transitions are present on the integration branch. |
| Persistence | World v1–v4, optional subsystem schemas, compact cognition and checksummed Zstd saves. Construction sub-schema is now v2. |
| Android/CI | Godot 4.5.2, GL Compatibility, arm64 Android export. Existing branch-filtered workflows inspected; local validation used. |

## Module boundaries

| Module | Responsibility |
|---|---|
| `data/buildings/phase_a.json` | Two playable definitions; stage costs/labour, eligibility, footprint, lifecycle and existing sprite keys. |
| `building_catalogue.gd` | Definition loading, stage/item validation, local knowledge, skills, equipment and explicit regional constraints. |
| `site_state.gd` | Persistent site records and bounded per-entity historical events. |
| `placement.gd` | Orientation, terrain/coast/access/elevation variation, spacing and indexed reserved footprints. |
| `material_gathering.gd` | Existing finite-source harvesting, proximity, movement and gatherer delivery adapter. |
| `physical_inventory.gd` | Single physical custody authority; site holders and atomic indexed resource reservations extend D2. |
| `construction_tasks.gd` | Existing AI work hook: assignment, pickup, physical transport, delivery, stage work and interruption/return journeys. |
| `construction_economy.gd` | Request/estimate interface, shelter demand, bounded site checks, service orchestration and persistence facade. |
| `building_lifecycle.gd` | Completion, condition, damage, maintenance/repair, abandonment, paid upgrades/conversions, demolition and salvage. |
| `construction_visuals.gd` | Culled temporary stakes/frame/roof overlays from actual site stages. No visual construction timer. |
| `demo_world.gd`, `demo_game.gd` | Repeatable playable 20-citizen scene using the actual integrated game frontend and simulator. |

These are RefCounted simulation records/services, with no Node or per-frame process for each building.

## Request and work protocol

`request_construction(world, request)` accepts `settlement_id`, `function`, optional `definition_id`/`candidates`, `priority`, `demand`, `available_workforce`, `resource_constraints`, `preferred_area`, `location`, `orientation` and `require_stock`. Evaluation returns cost/labour/shortage estimates or an explicit rejection. Request knowledge hints cannot manufacture capabilities: the catalogue queries the real settlement capability store.

The default shelter trigger runs every 60 ticks, with one autonomous housing project per nation and the inherited 72-bed demand ceiling. External planners can submit simultaneous requests up to 128 active sites. Settlement IDs currently map to the existing two nation/depot authorities; arbitrary multi-settlement economies remain later work.

An adult may construct a basic shelter without an exclusive profession. Required skill tiers and equipped, unbroken tools are checked for more specialised definitions. A worker scores available projects by priority and distance, using current job commitments. Food, care, teaching and immediate survival retain priority in the established scheduler.

One builder per site collects capacity-safe partial batches from its real depot, walks to the physical site and transfers goods into a `site:<id>` holder. Stages consume only their own materials when real work starts. The primitive shelter requires 3 wood, 1 stone and six work actions across site preparation, structural assembly and finishing; the worked timber dwelling requires local stone-working, 6 wood, 2 stone, ten work actions and a rotated 2×1 footprint. Work-derived quality reflects participating skill tiers.

No gathering or work is awarded from elapsed visual time. A missing shipment blocks its material-dependent stage. Blocked routes produce a pause/retry cooldown; invalid edited terrain pauses sites. Immediate danger releases assignments and returns living-carrier cargo through movement; death uses D2's actual ground drops. Dropped resources are conserved, but autonomous retrieval from arbitrary death caches is not yet implemented.

## Resource integrity

Reservations protect quantities in the **same** settlement balances used by crafting, toolmaking, inventory controls and construction. Both normal withdrawals and material-consuming recipes check unreserved availability. Reserved pickup debits both the physical balance and the matching claim atomically; delivery changes custody rather than minting stock. Site/citizen/depot transfers enforce distance and ownership.

`minted = currently held + consumed + destroyed` remains the inventory invariant. Delivered materials include both loose site inventory and legitimately consumed stage inputs. Cancellation releases uncollected depot claims; unused deliveries remain at the physical site as ground goods; in-transit cargo travels home. Already incorporated material remains consumed. The current demolition rule recovers floor(50% of embodied material) at the actual location by reclassifying consumed quantities, without creating a second provenance credit. Closing operations preflight capacity/overflow before mutation.

## Building continuity and lifecycle

Completed records retain the construction ID, original date, original settlement/worker, original local age, orientation, material provenance, quality, condition, function and bed capacity. Household membership remains the canonical occupant list and is saved with the world. Age changes never replace the definition or sprite.

Condition deteriorates by the definition's tick interval; elapsed intervals are accumulated when maintenance visits a building. Damage has a callable event interface. Repair is actual worker travel plus two labour actions and one wood for 25 health in the example definition. Abandonment removes capacity and clears residency; reoccupation restores capacity.

Declared upgrade/conversion paths use the **same** site/logistics/work pipeline and pay the target definition's full construction cost. This deliberately simple Phase A cost model preserves original material provenance. Original identity/date survive completion. Cancellation restores the previous building. The wider footprint stays reserved during work, and the building's beds are unavailable during conversion.

Controlled demolition requires worker labour, applies salvage once, frees the footprint and restores original underlying terrain where the building still owns TOWN tiles. Painting/fire destruction releases the building without invoking advanced physical collapse.

Recent event history is capped at 32 events/entity and 128 demolished/cancelled archives. Living building origin fields remain permanent; this is not an unlimited historical archive.

## Rendering and placement limits

Construction overlays are temporary hand-drawn crisp pixel stakes, framing and partial roof, with offscreen/zoom culling. Completed examples use existing `hut_a` and `cottage_a` atlas artwork, anchored to real building records. Physical footprints prevent cosmetic extra buildings from being generated on their other tiles. No per-frame atlas generation was introduced.

Placement validates all footprint tiles, overlap, terrain type, access neighbours, orientation, spacing, optional shoreline restrictions and elevation differences supported by the current visual height grid. Global path reachability is confirmed by actual worker movement with bounded failure recovery, rather than a full-map flood fill for every proposal. TOWN remains walkable under the existing navigation convention; doors/walls and building-interior pathfinding are later work. Multi-tile footprint reservation works, while art rotation and a full era-specific architectural library remain deferred.

## Persistence and recovery

Construction v2 is stored by the existing JSON and binary world save routes. It persists projects, stages/work, delivered/consumed inputs, site inventory, reservations, carriers, jobs, building records, condition, histories and round-robin cursors. Indices and pending maintenance references are reconstructed.

Old construction v1 houses receive safe default condition/provenance. Unknown original materials remain unknown and yield no invented salvage. Old active projects retain earned work and carried goods; past stage materials are charged once at the next legitimate site arrival. Legacy optional-construction saves still load. Integral JSON numbers are normalised before constructing holder IDs, preventing `site:1.0` versus `site:1` mismatches. Typed-array JSON restore issues in food techniques and demographic archives were fixed narrowly. Cross-service restore rejects fabricated deliveries, overlapping footprints, invalid IDs and unsupported reservation ownership.

Test fixtures were corrected where they reused a live project ID for a manually added house, retained stale households after replacing the founder population, assumed a pairing interest that their seeded personalities did not have, or jumped calendar years without updating biological stages. Production family/age thresholds were preserved.

## Performance and validation

Use the accompanying machine-readable `construction-phase-a-validation.json`, `construction-phase-a-benchmark.json` and `construction-phase-a-android.json` as the exact results. Benchmarks are Linux/headless CPU timings and do not imply Android FPS.

Validation: all **20 checks** passed (import, 18 headless regression suites and the actual demo scene smoke), including **126 construction assertions**. The autonomous 650-tick replay observed site creation, partial shipments and real stage progression, with a completed six-bed shelter plus the pre-existing D3 tool-yard adapter. Both identical worlds and save continuation remain deterministic. The arm64 APK exported without script/error diagnostics; ZIP CRC and APK signature verification passed. No Actions minutes were used.

Final Linux CPU benchmark:

| Workload | Result |
|---|---|
| 3,000 completed buildings + 128 active sites | Construction service p50 **0.255 ms**, p95 **0.333 ms**, 600 ticks |
| Full world, 100 citizens | Tick p50 **4.567 ms**, p95 **19.570 ms**, 240 ticks |
| Full world, 500 citizens | Tick p50 **17.756 ms**, p95 **36.422 ms**, 240 ticks |
| Separate 500-citizen phase profile | Citizen dispatch p95 **39.111 ms**; construction prune p95 **0.112 ms**, 120 ticks |
| Actual frontend driver, 1×/2×/4× | 80/159/318 authoritative ticks over 240 synthetic 30 Hz frames per run |
| Repeated request/cancel | 60 cycles; zero retained sites and conserved ledger |

Citizen dispatch is the measured dominant phase in the separate 500-citizen profile. It includes existing survival, navigation, cognition and individual work hooks; this measurement does not isolate a particular AI algorithm. Dense-service measurements isolate dormant-building and site-check overhead and do not represent 128 fully staffed simultaneous projects. Frontend tests are headless CPU runs, not GPU or display frame rates. The 4× run can defer excess accumulated time under the existing pacing budget; chronological simulation tasks are not skipped. Host measurements vary and need confirmation on the P30.

Budgets: 128 sites, 64 construction jobs, four gatherers/nation, 16 site validations/tick, 16 condition visits/tick, one worker/site, existing shared pathfinding budgets and 20 kg carrier capacity. Footprints, site/building IDs, reservations and pending repair requests use indices. Idle completed buildings do not run worker-selection eligibility checks per frame. The carried frame-pacing fix limits extra simulation work after an authoritative tick and retains chronological pending work.

Reproduce with Godot **4.5.2**:

```sh
python scripts/qa/validate_construction_phase_a.py --godot /path/to/godot-4.5.2
godot --headless --path . --script res://tests/universal_construction_test.gd
godot --headless --path . --script res://tests/construction_benchmark.gd
godot --path . res://scenes/construction_demo.tscn
```

The playable demo starts with zero construction stock and several real finite nodes. Its save override avoids replacing the player's ordinary world. The normal Android build uses the ordinary game scene with the same autonomous construction engine. Tests run the actual authoritative `world.step()` through demand, gathering, travel, shipment, work and a functional six-bed dwelling, then save/restore it. They also test concurrency, shortages, invalid placement, cancellation while hauling, worker death/interruption, unreachable sites, repair, demolition, salvage, migration and conversion.

No physical Huawei P30 test, rendered screenshot inspection or Android-device performance measurement has been performed. The locally exported arm64 APK is debug-signed with a new development key; compatibility with replacing an older differently signed APK is not verified.

## Phase B readiness

Ready to extend the shared definitions and request interface. Priorities are housing policies beyond two existing depots, explicit settlement geography/culture sources, more early-era material chains, more worker slots/transport policies, source-cache recovery and real capacity-limited stockpiles. Profile and optimise citizen dispatch before promising large-population accelerated Android performance.

Data-only extension points: non-dwelling purpose/catalogues, culture/religion/climate tags without a live generator, storage capacities, detailed structural techniques and animation/destruction asset references. The eligibility evaluator consumes explicit tags, but no demographic or religious traits are inferred. Temporary construction artwork has no dedicated authored animation.

Deferred: eleven complete architectural catalogues, autonomous city planning, district/infrastructure networks, cranes/machinery, markets and economic supply chains, detailed heritage UI, limitless historical logs and advanced destruction physics. D3's legacy tool-yard work remains its own compatible adapter; migrating that older job to a building definition is a later integration slice.
