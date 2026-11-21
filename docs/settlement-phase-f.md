# Phase F — autonomous settlements, local industry and physical networks

Phase F now includes the early-age runtime across F1–F7: autonomous household
founding, independent inventories, strategic construction, local industry/farming,
physical road/barter/food journeys, specialisation, decline, evacuation and recovery.
Huawei P30 installation, visual inspection and hardware performance remain pending;
Android packaging and headless input tests do not establish device performance.
Later-age content remains gated extension work, as specified in the phase brief.

## Repository audit and dependency selection

The development branch is `feature/phase-f-autonomous-settlements`, draft PR #31.
Base: `feature/settlement-roads-trade-economy-b-e` at
`cebf8e52dea048e14a90c6d09067306ee9f0f09c` (PR #24). Ancestry includes PR #22 at
`06f1d3012beafef57bac83a29e4be49f2a6f8fa1` and PR #20 at
`29c1a788ce015e266506a59fbe5d2f710f8a2e86`. No merge into main was performed.
Other art, audio and frontend branches require deliberate integration.

Audited the tick/save pipeline; AI cognition/priorities/navigation; household
care, reproduction and mortality; physical custody/reservations; edible-unit
conservation; occupations/knowledge; gathering/construction/placement/lifecycle;
roads/trade; terrain/elevation/ecology; renderer culling and Android workflows.
The original capital-only holder IDs and jobs prevented independent local towns.
Those authorities are extended rather than replaced. Original premium sprites,
construction gestures, smooth movement, real-time 1x and time controls remain.

No freshwater, religion, ethnic identity or political-disagreement simulator exists
in this base. Coast contributes geographic/fishing opportunity, never drinkable
water. Social cohesion uses actual households/personality/recorded rivalry.

## Ownership and persistence

| Authority | Responsibility |
| --- | --- |
| `settlement_registry.gd` | Stable IDs, political affiliation, centre/radius, residents index, knowledge, plans, prosperity, stress, history/status. |
| `physical_inventory.gd` | All item/material balances, serial ownership, reservations, physical transfer and atomic barter. |
| `food_survival.gd` | Existing edible-unit ledger, local depots, household pantries, carried rations/seeds/shipments, plots and conservation. |
| Construction | Occupancy, projects/stages/material consumption, buildings, damage, transitions, repair and abandonment. |
| Households/citizen AI | Family membership, care, reproduction, survival priorities and physical movement. |
| `local_logistics.gd` | Bounded transport assignments between actual local storage holders; never a second balance. |
| `road_trade_economy.gd` | Built trails, arbitrary endpoint links, price observations and real merchant journeys. |
| `settlement_lifecycle.gd` | Policy over actual registry, resources, inhabitants and infrastructure; no separate economy. |

Capital IDs 0/1 permanently retain `settlement:0` / `settlement:1`. New IDs begin
at 2, increase monotonically and remain in history after abandonment. Camps begin
with empty stores. Local aliases reference the existing custody dictionaries;
no capital inventory is renamed, credited twice or remotely moved.

Citizens, households, projects, completed buildings, farms, roads and jobs carry
`settlement_id` alongside political `nation`. `store:<building_id>` represents a
real completed local warehouse with capacity 64. Withdrawal/deposit requires
local membership and proximity. Sharing a nation alone grants no access to
another town's stock. A merchant exchange is a validated, explicit exception.
Destroyed warehouses drop actual stock and serials onto physical ground holders.

JSON and compressed GSAI saves include registry, local stock/knowledge, households,
founding/migration/provisions, plans/cursors, local logistics, construction,
farms and road/trade state. Derived membership, caches and assignments rebuild.
Existing v1–v4 worlds remain accepted. Road-network version 2 accepts the original
version-1 capital route. Missing optional fields migrate old saves; invalid present
membership/owners and failed conservation reject restoration. Material choices
and expedition order are stable across JSON key sorting. Earlier binaries do not
understand satellite holders; retain a pre-upgrade save for rollback.

## F1–F2: founding and migration

The normal tick considers one origin every 60 ticks, round robin. Population >=8,
pressure >=48, two healthy available adults, at least four source residents after
departure and a useful reachable site are required. Housing deficits, finite
wood/stone depletion and seasonal food opportunities affect pressure. Curiosity,
diligence, caution, housing and actual rivalry influence whole-household selection.
Pregnancy, existing jobs, teaching, illness and urgent hunger constrain eligibility.

A bounded flood (1024 cells, radius 32) evaluates up to 24 sites. Separation >=16,
safe valid shelter ground, agricultural land, finite wood/stone and seasonal food
are required. There is no random instant village placement.

Families pack existing pantry provisions into real carried edible units, up to
three per adult; families exceeding that carrying budget wait. Guardians physically
collect and carry infants through the existing care controller; older children
follow. Guardians wait for lagging dependents. Eating, care and immediate safety
retain priority over travel. Founding does not replace citizen cognition.

All survivors must physically arrive within three cells before membership changes.
The site is rechecked, a provisional camp identity/store is registered, and normal
local gathering/hauling/construction/food jobs begin. Completed beds for all
survivors and a local food reserve at least their population establish the permanent
settlement milestone. No completed building or material is spawned at founding.

Hazardous destinations, travel/camp timeout and loss of required adults can fail
an expedition. Survivors return through existing movement. Cargo stays owned where
it physically is; deaths retain the existing item drops/edible loss accounting.
A failed camp preserves people, buildings, balances and history for lifecycle policy.

General evacuation reuses this same household journey pipeline. Receiving towns
must share affiliation, be safe and have spare beds after other incoming families
are counted. A bounded reachability check rejects isolated destinations. Residence
changes only on physical arrival; nobody is duplicated or teleported.

## F3–F4: planning, growth and local production

The original footprint/occupancy authority validates terrain, elevation, spacing,
road preservation, active crop plots and reservations. Up to 48 valid candidates
receive desirability scores. Homes favour existing homes, streets and access;
forestry/quarry placement scores nearby finite deposits; farms require meadow;
storage/markets favour hubs. A modest communal centre and a location-dependent
access corridor remain clear. Radius grows from 9 to 16 with actual population
and connections. No identical fixed city blueprint is applied.

One settlement survey and one construction-demand decision run on separate
15-tick staggers. Housing demand, local food, labour/material availability,
environmental carrying capacity and lifecycle status constrain growth. Support
facilities compete using actual food/resource shortages, workers, population and
connections. One active demand project per settlement prevents unlimited queues.
Shelter upgrades use the existing paid transition engine and require enough other
beds to avoid displacing the population. Destruction allows later reconstruction.

Nine definitions use existing high-density atlas sprites and real staged recipes:

| Definition | Function | Wood | Stone | Gate/effect |
| --- | --- | --- | --- | --- |
| primitive_shelter | Housing | 3 | 1 | Existing six-bed shelter. |
| timber_hut | Housing | 6 | 2 | Existing knowledge-gated dwelling/upgrade. |
| tool_area | Workshop | 2 | 1 | Actual workstation for physical knapping/tool production. |
| local_storage | Storage | 4 | 1 | Separate physical holder; 64-unit capacity. |
| forest_camp | Forestry | 3 | 1 | Improves finite local timber gathering. |
| quarry_camp | Quarry | 2 | 3 | Improves finite local stone gathering. |
| cultivation_field | Agriculture | 2 | 1 | Enclosure for a local experienced worker's seed experiment. |
| market_square | Commerce | 4 | 2 | Requires local stoneworking; permits a second local merchant. |
| gathering_hall | Civic | 4 | 1 | Population >=8 demand; real nearby social destination. |

Every new support building uses material delivery/consumption and eight labour
units across three visible stages. Building definitions retain 11-age capability
extension fields; this does not unlock advanced content by date.

Gatherers choose nearby real warehouse/depot delivery points. Local couriers
physically retrieve secondary stock when central materials are scarce. Construction
and toolmaking reserve/use the correct town's materials and cannot simultaneously
assign a citizen already hauling, trading or building roads.

Toolmakers are selected from actual skill, diligence and curiosity, with stable
ID tie breaks. One artisan per town gathers inputs, picks them up, walks to a
real workstation, performs labour, creates catalogue tool serials and returns
products. Local experiments/teaching establish actual stoneworking. Satellite
knowledge no longer automatically remains prehistoric or unlocks for all towns.

Cultivation requires existing local knowledge or a successful experienced
forager's physical seed experiment at a built farm. Workers carry a real grain
seed, walk to the plot and plant. Seasonal growth creates harvest opportunity;
only real harvest work credits edible units. Mature unharvested winter crops can
fail, reducing fertility and recording history. Harvested plots can be replanted;
fallow soil recovers on the existing annual ecology cycle. Agriculture and both
ledgers retain independent authoritative accounting.

## F5–F6: networks, specialisation and decline

Road planning considers arbitrary inhabited towns, bounded to nearby endpoints.
Citizens walk and work on every trail tile; roads are never created by drawing a
connection. Existing local streets extend to homes. Terrain/building changes
invalidate affected links. Broken merchant routes return actual cargo physically.

Each town has observations of local scarcity/prices. Reciprocal wood/stone
surpluses and shortages create one-unit barter offers; a merchant picks up local
cargo, follows actual built road waypoints, exchanges at the other depot and
returns imports. Same-nation food relief uses the food ledger and actual carried
edible units, with surplus and receiving-shortage checks. No remote balancing,
monetary account, taxation, phantom generation or free transaction is introduced.

Specialisation changes with real facilities, resources, practiced skills, active
farms and road connections: subsistence, forestry, mining, agriculture, crafting,
trading or coastal work. Facilities affect actual work. Names/history/descriptors
are evidence-derived rather than assigned random permanent economic classes.

Hazards, food depletion, high mean hunger or loss of adults accumulate stress.
At 180 stress ticks a town struggles and pauses optional growth; a suitable
household can evacuate. Empty towns accumulate 240 ticks before abandonment.
Buildings, stock and historical identity persist; projects pause/release unused
reservations. Returning residents in improved conditions recover that identity,
reoccupy intact structures and resume paused work. Existing damage/repair/removal
systems remain authoritative. There is no calendar-based settlement tier upgrade.

## F7: presentation and performance budgets

Founders reuse walking/carrying gestures; camps use the original crate artwork;
construction retains its high-density premium sprites and stages. Material/food
couriers show carried objects; sowing uses work gestures. Abandoned/damaged
structures tint existing artwork. Citizen inspection shows local settlement,
status, population and specialisation. Existing chunk culling and touch UI remain.

- 24 settlement records, two active expeditions, eight members/party, 240-tick
  origin cooldown and 1200-tick journey/camp limit.
- 64-entry tick-local survey cache; terrain/extraction invalidates nearby entries.
  Observations are never inventory balances. Cold-cache save replay remains stable.
- 48 road links, 2048 nodes/route search, 320 route cells/road queue, four road
  workers and six global merchants; one merchant/town, two with a real market.
- 128 construction sites, 64 jobs, four gatherers/town, one builder/site and
  16 site validation checks/tick (inherited construction budgets).
- 12 local logistics jobs, 20 tool jobs, 48 food jobs, 24 global food gatherers
  and 96 farm plots. Shared navigation budgets prevent per-person unbounded paths.
- Street updates inspect at most 24 buildings; road source planning is staggered
  every 120 ticks. Seasonal food capacity uses a non-authoritative tick cache.

Benchmark JSON reports Linux headless CPU tick timing for six seeded inhabited
towns at 120 and 500 citizens over 240 full ticks. These are not Android FPS,
thermal, battery or GPU measurements. Device profiling must establish Huawei P30
frame pacing and long-session behaviour before claiming hardware validation.

## Regression coverage and reproduction

```sh
python3 scripts/qa/validate_settlement_phase_f.py --godot /path/to/godot-4.5.2
godot --headless --path . --script res://tests/settlement_benchmark.gd
godot --path . res://scenes/settlement_demo.tscn
```

The dedicated runner imports with Godot 4.5.2, runs 26 suites and the demo scene
(28 steps total), failing on nonzero exits, script errors and failed assertions.
The demo starts twelve citizens and waits for normal autonomous founding; it
never overwrites player saves. The APK retains the original main scene.

| Required coverage | Tests |
| --- | --- |
| Founding triggers, valid/invalid sites, physical travel, paid initial shelter, identity | settlement_founding, settlement_planning |
| Whole-family/infant travel, provisions, actual planting and crop failure | settlement_family_farm, household_care, food_survival |
| Local ownership, placement, demand/expansion, materials and transitions | physical_inventory, settlement_planning, universal_construction, construction |
| Arbitrary roads, barter, food relief, couriers, technology, abandonment/recovery/evacuation | settlement_network_lifecycle, regional_economy |
| Ledger conservation, JSON/compressed save, deterministic replay | founding/network/family suites, physical_inventory, unified_integration |
| Existing cognition, demographic/era/occupation/tool production | inherited AI/cognition/lifecycle/demography/occupation/tool suites |
| Scene, rendering, touch controls, inspector and pinch input | demo_scene, rendering, input, game_item_ui, item_inspector, pinch_zoom_anchor |

The Actions workflow repeats regression and benchmark, then exports an arm64
Godot 4.5.2 GL Compatibility debug APK with JDK17, minSDK24/target35. It validates
APK signatures and archive CRC and uploads APK plus reports. Local export uses
the installed JDK21. Debug keys are generated per environment; upgrading an older
APK signed with another key may require backup/uninstall/reinstall.

Machine-readable evidence: `settlement-phase-f-validation.json`,
`settlement-phase-f-benchmark.json`, `settlement-phase-f-android.json`.

## Remaining boundaries and integration risks

- Physical Huawei P30 installation, visuals, input feel, accelerated-time frame
  pacing and sustained hardware profiling remain unverified. No attached device
  was available; headless/packaging checks cannot substitute for those tests.
- The 11-age schema and evidence gates are operational extension points. Advanced
  era architecture/industry, institutions, maritime shipping, bridges, freshwater
  hydrology and unsupported cultural/political systems are not simulated here.
- Trading currently exchanges wood/stone; food relief is same-nation aid, not a
  complete market for every catalogue item. No money/banking/tax system.
- Warehouse capacity is a unit budget; food remains in the established edible
  ledger at local depots/pantries rather than duplicating into item warehouses.
- Dense/high-population worlds need Android profiling of bounded planning spikes.
  Towns and parties are intentionally capped; candidate search can miss distant
  viable land rather than perform expensive whole-map scans.
- Evacuation requires an available whole household and safe receiving capacity.
  Households with pregnancy, work/teaching commitments or provisions beyond carry
  limits wait; unsupported sea routes cannot rescue isolated towns.
- This PR is stacked on #24, which depends on #20/#22. Reconcile those branches
  and concurrent art/UI/audio changes before integration into main. No main merge.

## Verified local results

Godot 4.5.2 passed all 28 regression-runner steps (import, 26 suites and the demo),
including 43 founding checks, 18 planning checks, 37 network/lifecycle checks,
58 family/farm checks and 38 input checks. JSON and compressed restoration,
deterministic replay and both custody ledgers passed.

Six seeded active towns were exercised for 240 full ticks per scenario:

| Citizens | Median tick | p95 tick | Maximum tick |
| --- | --- | --- | --- |
| 120 | 8.057 ms | 26.943 ms | 109.948 ms |
| 500 | 28.257 ms | 50.337 ms | 143.036 ms |

Both scenarios conserved food and materials. These Linux headless CPU costs
include startup/planning spikes, which remain relevant for mobile profiling;
there is no claim of P30 frame-rate or accelerated-time hardware validation.

The local arm64 APK passed APK Signature Scheme v2/v3 verification and archive CRC
checks. Its SHA-256 is recorded in the Android report. No Android device was attached.
