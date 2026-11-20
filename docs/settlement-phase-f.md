# Phase F — operational settlement founding and planning foundations

This draft implements **F1–F3 foundations**, with the local material gathering,
hauling, shelter, repair and food integration needed to demonstrate real founding.
**Full Phase F is incomplete.** It does not implement a satellite road/trade
network, full local occupation/technology propagation or the general settlement
decline/recovery/migration lifecycle. The existing two-capital road/trade slice is
preserved and regression-tested. No claim of Huawei P30 hardware validation.

## Repository audit and dependency selection

Base: `feature/settlement-roads-trade-economy-b-e` at
`cebf8e52dea048e14a90c6d09067306ee9f0f09c` (draft PR #24). Git ancestry confirms
this includes PR #22 at `06f1d3012beafef57bac83a29e4be49f2a6f8fa1` and PR #20
at `29c1a788ce015e266506a59fbe5d2f710f8a2e86`. No source branch or main was merged.
Other frontend/art work remains on separate branches and requires deliberate
integration. Original atlas assets, construction gestures, movement interpolation,
real-time 1x scheduling and GL Compatibility renderer are retained.

Audited: simulation tick/save pipeline; AI cognition/priorities/navigation;
household guardian/reproduction/mortality services; physical inventory and
reservations; food conservation; occupations/local capability gates; gathering,
placement, construction/lifecycle; B–E road/trade; terrain/elevation/ecology;
renderer culling; headless and Android workflows. Findings:

- Material holders `settlement:0` and `settlement:1` were capital/nation aliases.
- Construction workers, material searches, food stores and home assignment used
  those two capital locations, preventing an independent local village.
- Food already has a separate edible-unit ledger. Merging it into the catalogue
  ledger here would duplicate authority, so both existing ledgers are extended.
- Household pantries have physical home locations. Migration must not remotely
  move them. This slice excludes households with stored pantry food.
- Basic occupation preferences, practice and facilities now use local membership.
  Advanced toolmaking/adoption controllers and trade endpoints remain capital-based.
  Satellite toolmaking and road/trade work are explicitly excluded until F4/F5,
  rather than directing settlers back to a distant capital.
- No freshwater, religion, political-disagreement or advanced-city institution
  simulator exists in this base. Coast is a fishing/geography signal, never
  advertised as freshwater. No invented cultural or religious attributes.

## Authorities and data

`settlement_registry.gd` owns identities, political affiliation, location, radius,
founding history/status, local knowledge extension, development plan and derived
resident index. IDs 0/1 retain their exact old holder identities permanently;
new IDs monotonically start at 2. A camp starts with **empty** material and food
stores. A provisional identity supports real local jobs; permanent founding is a
separate milestone after completed housing and gathered food exist.

Citizens, households, sites and completed buildings carry `settlement_id` alongside
`nation`. Buildings remain authoritative in construction, material balances and
reservations in physical inventory, edible units in food, families in households.
The registry never copies quantities into an alternative economy. Plans contain
observations and demand, not spendable stock. Derived membership is rebuilt in
one pass per tick; resident lookup is O(1).

Material withdrawal, delivery and on-site consumption require the actor's local
membership and physical proximity. Sharing a nation no longer grants access to
another settlement store/site. Ordinary gifts between present citizens remain
supported. Legacy `stockpiles[]` and satellite `local_stockpiles` are **dictionary
references into the same custody ledger**, not updated mirrors.

## Runtime founding

1. The normal world tick evaluates one origin every 60 ticks, round robin.
2. At least eight residents, pressure >=48, available healthy households, at least
   two adults, a source population of at least four after departure and a useful
   reachable site are required. Housing deficits, finite material depletion and
   seasonal food opportunities affect pressure.
3. Existing household commitments, hunger, health, pregnancy, infancy, apprenticeships and jobs
   veto departure. Curiosity, diligence, caution and shelter status rank eligible
   households; strong recorded rivalry can veto joining the leader. Households
   stay whole. Travelling families cannot merge or conceive during the journey.
4. A bounded flood (1024 cells, radius 32) yields up to 24 candidate evaluations.
   Sites require separation >=16, safe valid shelter terrain, agricultural land,
   finite wood/stone and seasonal food. No random village placement.
5. Existing citizen AI walks adults one normal step at a time. Children follow
   guardians through the existing dependent AI; guardians wait for lagging
   children. Urgent safety, dependent care, teaching and eating retain priority.
   Optional food hauling and construction do not hijack an active expedition.
6. All living members must arrive within three tiles before household membership
   changes. The site is rechecked; an empty camp store is then registered, local
   shelter requested and ordinary gathering/construction/food AI takes over.
7. The original extraction, reservation, carrying, delivery, on-site material
   consumption and construction stages physically produce the shelter.
8. Completed beds for all survivors and local food >=survivor count establish a
   permanent identity/event. The deterministic demonstration completes this
   without manual founding commands.

Before arrival, hazardous/edited destinations, timeout or essential-worker loss
send survivors back through ordinary navigation; nothing is refunded remotely.
Death drops remain in the existing custody system. After arrival, failed founding
keeps the camp's people, structures and goods where they are, records failure and
marks it struggling. General evacuation/recovery is still F6 work.

## Strategic planning

The original placement/footprint index remains the sole occupancy authority.
The planner extends B–E's bounded functional desirability with a reserved local
communal centre, location-dependent expansion corridor and road preservation.
New-settlement construction stays within a nine-cell Manhattan radius. Homes
cluster near existing homes, roads and local stores. Production, storage,
agricultural and commerce categories have scoring hooks, but only the **two
existing dwelling definitions** are currently constructible; these hooks are
not claimed as operational farm/workshop/market construction.

One settlement receives a development survey every 15 ticks; one receives a
construction demand decision every 15 ticks on a different stagger. Plans record
housing demand, local ecology, food reserve and carrying capacity (6–72).
Additional satellite housing pauses when local food is insufficient. Existing
material/workforce gates still apply. The survey cache is capped at 64 entries,
invalidated locally by terrain/extraction events and used only for the current
authoritative tick, ensuring cold-cache replay after restoration.

Specialisation is currently an **observational descriptor** (subsistence,
forestry, quarrying, coastal foraging, actual existing agriculture). It does not
create jobs, skills, production bonuses, or market transactions.

## Persistence and migration

JSON and compressed GSAI saves include the registry, founding parties/cooldowns,
local food stores, membership, local sites/jobs and all planning cursors. The
binary serializer has its own field list and was extended explicitly. Derived
indexes and founder assignments rebuild after loading. Existing v1–v4 world
formats remain accepted. Missing Phase F fields permit legacy migration; corrupt
present membership/identities fail closed.

No legacy capital balance is renamed, transferred or credited a second time.
Present custody ledgers still must pass their original conservation validation.
Construction uses sorted material IDs when choosing shortages: JSON key sorting
must not alter worker assignments or replay. Pantries retain their physical
location. No infant household or nonempty-pantry relocation is claimed.

## Budgets and Android

- 24 settlement records; two active founding/return expeditions; eight people per
  party; 240-tick origin cooldown; 1200-tick travel/camp timeout.
- Each placement decision scores at most 48 valid candidates; footprint checks
  remain within the original radius-nine search.
- Founding history <=49 expedition records transiently, settlement history <=48.
- Original construction: 128 sites, 64 jobs, four gatherers per settlement,
  one builder per site, 16 site validation checks per tick.
- Food retains its per-settlement gatherer cap plus 24 gatherers / 48 food jobs
  globally, preventing settlement count from multiplying unconstrained searches.
  Seasonal food-capacity lookups share a tick-local terrain cache; harvesting
  still subtracts authoritative wild usage, and shoreline edits invalidate the
  affected neighbours. No food quantity is stored in this derived cache.
- Original shared navigation/path budgets and chunk rendering/culling remain.
- Camps use the original high-density crate artwork for the staging store.
  Founders reuse existing walking/carrying gestures. Finished buildings retain
  their definition-selected original sprites. No art assets were replaced.
- Benchmarks are **Linux headless CPU timings**, six seeded inhabited settlements
  with 120/500 citizens for 240 full simulation ticks. This is not Android FPS,
  touch, thermal, battery or long-session evidence. See benchmark JSON.
- Android debug export is arm64, GL Compatibility, min SDK24, target35. Local
  export uses installed JDK21; CI explicitly uses JDK17. Device installation and
  input/frame pacing on the Huawei P30 remain pending. The debug signing key is
  generated for this workspace/CI run; updating a differently signed prior APK
  is not validated, and save backups should be retained before switching builds.

## Validation and reproducibility

```
python3 scripts/qa/validate_settlement_phase_f.py --godot /path/to/godot-4.5.2
godot --headless --path . --script res://tests/settlement_benchmark.gd
godot --path . res://scenes/settlement_demo.tscn
```

The demo starts twelve citizens on suitable untouched land and waits for the
normal tick to make the decision. It never overwrites normal player saves.
The normal APK keeps its original main scene and existing player-world loading.

The dedicated Phase F Actions workflow imports with Godot 4.5.2, runs the full
regression runner, measures CPU scenarios, exports/signature-checks/CRC-checks
an Android debug APK and uploads APK/reports. Local validation, Actions status
and physical-device testing are separate evidence. Machine-readable reports:
`settlement-phase-f-validation.json`, `settlement-phase-f-benchmark.json`,
`settlement-phase-f-android.json`.

## Delivered and remaining work

| Phase | Status and practical scope |
| --- | --- |
| F1 | Working registry, citizen/household/site IDs, local ledger permissions and safe legacy migration. More UI/analytics remain. |
| F2 | Working pressure-based decisions, whole eligible households, bounded geography selection, travel, camp, real shelter/food, permanent founding and safe failed travel. Infant and stocked-pantry expeditions deferred. |
| F3 | Working dwelling placement/reservations, communal space/access corridor, local demand/carrying limits, terrain/resource invalidation and persisted plans. Full functional districts await real non-dwelling catalogues. |
| F4 | Local construction/gathering/hauling/repair/food used by F2 work. Satellite toolmaking, full occupation and technology propagation, local farms and multiple storage buildings incomplete. |
| F5 | Existing capital roads/trade preserved; arbitrary settlement road/trade network **not implemented**. |
| F6 | Founding failure/history and observational opportunity descriptors only; autonomous general decline, abandonment/recovery, evacuation and specialist economic behaviour **not implemented**. |
| F7 | Headless regression, culling-compatible inherited visuals, CPU benchmark and Android packaging; P30 hardware/visual/performance validation **pending**. |

Do not merge this stacked draft to main until #20/#22/#24 and other concurrent
art/UI work have been reconciled. Existing pre-F binaries do not understand
satellite custody holders; keep a pre-upgrade save backup when testing rollbacks.

## Verified local delivery results

Godot 4.5.2 passed all 26 runner steps (import, 24 suites and demo scene),
including 43 founding checks, 18 local planning checks and 38 touch/input checks.
The input regression was corrected to instantiate the actual unified Android
frontend; its prior base class did not expose the renderer it was trying to test.
JSON and compressed-save replay and both resource ledgers passed.

Final Linux headless CPU measurements (240 ticks, six seeded inhabited settlements):

| Citizens | Median tick | p95 tick | Maximum tick |
| --- | --- | --- | --- |
| 120 | 10.262 ms | 37.152 ms | 112.596 ms |
| 500 | 21.854 ms | 43.888 ms | 124.297 ms |

Both scenarios retained food and material conservation. Maximum costs remain
material for a mobile main thread and require hardware profiling. The APK passed
arm64 packaging, APK Signature Scheme v2/v3 and archive CRC verification. No P30
was attached. GitHub Actions results are tracked separately in the draft PR.
