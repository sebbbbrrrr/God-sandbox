# God Sandbox — Civilisation Observatory (Android UI)

Development branch: `feature/civilisation-observatory-ui`  
Parent: Phase F at commit `823d5d366dc1b576e6e7a5ef621831859ec05970`  
Primary scene: `scenes/world.tscn` → `scripts/unified_game.gd`

## User experience

The **Towns** shortcut in the premium top status bar opens a touch-safe village/town sheet. Clicking within three Manhattan cells of a settlement centre in Hand mode also opens its sheet, unless a live citizen is on the exact touched cell (citizen inspection retains priority). The sheet lists all known settlement identities including camps, active towns, struggling settlements and abandoned settlements; choose one from the dropdown.

Five views provide:

1. **Overview** — actual population, status, speciality, position and planner prosperity; derived housing, depot-food-buffer and average-health percentages; evidence-based strengths and bottleneck alerts.
2. **Economy** — real depot stocks, physical building counts, farms, unique workers and job types, pending projects and their outstanding materials/labour, most recent ecological planner survey.
3. **Routes** — connected/building/blocked endpoints, built road-tile progress, pending work and active traders; trade event ledger exports/imports, and cross-settlement citizen social ties.
4. **People** — households, population, current workers, health, hunger, lifecycle stress/hazards, mean observed trust/rivalry.
5. **History** — actual settlement event ring buffer (up to 25 shown), no fabricated GDP or growth series.

**Locate** centres the world camera on the selected town. **Routes** toggles a non-interactive map overlay that remains visible after the inspector is closed. Solid green means connected roads; amber dotted lines are *plans*, green dots are physically built segments, and red dotted lines indicate blocked attempts. A red straight-line fallback is an untraversable attempted connection, never a claimed road. The settlement markers show actual centres and political affiliation; distressed towns use red rims.

On 480×850 portrait devices the sheet sits under the top status bar, scrolls within its bounded area and leaves the bottom game dock accessible visually. Landscape uses a bounded right-side inspector. The sheet and dark scrim intercept world gestures; native buttons remain tappable. Buttons have at least approximately 43–46 logical pixel tap heights.

## Data provenance and semantics

The implementation *does not add a new simulation authority* and does not create resources, trade or social relationships.

- `settlements.records`, `settlements.residents`, and `settlements.housing` determine identities, statuses, population and housing. One-pass house-capacity projection follows the same capacity sum as the registry.
- `settlement_planner.update_one` owns `record.prosperity`, `record.plan` and the latest ecological survey.
- `settlement_lifecycle.evaluate` supplies food-insecurity assessment, safety, stress, status and speciality.
- `inventory.settlement_inventory` and `food.store/total` supply actual depot stocks. Household pantries are not included in the food-buffer bar.
- `construction.houses/projects/jobs`, `food.farms/jobs`, `toolmaking.jobs`, `local_logistics.jobs`, and `regional_economy.road_jobs/trade_jobs` supply work, facilities and pending material progress.
- `regional_economy.links/roads/recent_trades` supply real status, actual built road segments and completed physical barter events. Food-relief completions have a separate backend counter and are **not** invented as recent barter-ledger entries.
- `citizen_ai_by_id.*.relationships` supplies **personal** trust/rivalry and cross-town social ties. No governmental alliance/diplomacy model is claimed. Observed undirected pairs are deduplicated.
- Inactive or unassessed settlements show **Not assessed** on bars rather than false zeros.

Derived UI ratios: housing coverage is `min(100, 100 * housing_capacity / population)`. Depot food buffer uses a transparent **three units per resident** benchmark for the bar; this is *not* a claim of three days' supply. Average resident health and hunger use live citizen values. The backend's `prosperity` is a planner index, not monetary GDP. No fabricated happiness, growth, productivity, diplomatic alliance or economic time series is displayed.

Bottlenecks are rules over actual inventory, housing, route status, construction delay or lifecycle flags, not an independent AI assessment. A 240-tick construction warning describes observed lack of progress, not proven cause.

## Performance/merge notes

- The insight layer only refreshes when the authoritative `world.tick` changes and the sheet or map is active. No background polling when both are closed.
- Houses, projects, farms, households, merchants and roads are projected in single passes. AI relationship inspection is bounded by the backend's relationship capacity; road drawing samples up to 64 waypoints per link.
- Existing simulation state, saving and authority are unchanged. All new files live in `scripts/ui/` except tests; existing frontend integration is deliberately confined to the premium HUD and `unified_game.gd`.
- Do **not** merge this branch directly into `main`. It depends on Phase F (PR #31), which is based on the earlier roads/trade branch (PR #24). The separate premium UI PR #21 may need reconciliation when integrating its component layout.
- Android validation should include Huawei P30 touch, scrolling, panel bounds, orientation, 1× and 4× frame pacing, and zoomed route overlays. Engine regressions can be run through `scripts/qa/validate_settlement_phase_f.py` (includes `civilisation_observatory_test.gd`).
- No hardware APK performance claim is made before an on-device run.
