# Batch B delivery — Ages I–III

This phase adds 13 functional designs to the previous 15. The catalogue now contains 37 persistent definitions: 28 authored designs and nine preserved legacy IDs. Each of Ages I–III has eight distinct authored functional archetypes. Housing variants share one archetype. Full eleven-age acceptance remains open.

## New designs and exact recipes

All IDs reuse the existing material catalogue. Quantities are integer item units, with physical masses defined by the item economy. Work excludes travel and deliveries.

| Age | Building ID | Exact materials | Work | Knowledge |
|---|---|---|---:|---|
| 1 | `cordage_canopy` | wood: 3, stone: 1, plant_fibre: 3 | 12 | stone_working |
| 2 | `timber_workyard` | wood: 6, stone: 3, plant_fibre: 3, reeds: 3 | 24 | stone_working, cultivation |
| 2 | `grain_grinding_shelter` | wood: 5, stone: 6, plant_fibre: 3, reeds: 4 | 24 | cultivation |
| 2 | `water_lift` | wood: 5, stone: 4, clay: 3, plant_fibre: 4 | 24 | cultivation, irrigation |
| 3 | `bronze_courtyard` | wood_plank: 4, stone: 5, clay: 14, plant_fibre: 4 | 36 | masonry |
| 3 | `bronze_smelter` | wood: 6, stone: 6, clay: 10, plant_fibre: 3, reeds: 3 | 36 | pottery, stone_working |
| 3 | `bronze_forge` | wood: 6, stone: 8, clay: 8, plant_fibre: 3 | 36 | bronze_working |
| 3 | `ore_mine` | wood: 8, stone: 5, plant_fibre: 4 | 30 | stone_working |
| 3 | `bronze_granary` | timber_beam: 3, stone: 8, clay: 14, plant_fibre: 4 | 42 | masonry, cultivation |
| 3 | `bronze_market` | timber_beam: 2, wood: 4, stone: 5, clay: 10, woven_cloth: 2 | 36 | caravan_trade |
| 3 | `bronze_meeting_hall` | timber_beam: 3, stone: 7, clay: 16, plant_fibre: 4 | 42 | masonry |
| 3 | `masonry_workyard` | wood: 5, stone: 8, clay: 4, plant_fibre: 3 | 30 | pottery, stone_working |
| 2 | `fenced_farmstead` | wood: 5, stone: 3, plant_fibre: 3, reeds: 6 | 24 | cultivation |

## Real operation

Cordage, planks/beams, grain rations/flour, masonry blocks, bronze ingots and tools use the shared facility work system. Operators collect real input cargo, walk to an entrance, perform work and carry output back. Missing materials, qualification, knowledge, condition and abandonment govern operation.

Bronze needs finite copper/tin extraction at a live local mine. A practised adult potter can attempt a paid smelting trial: three copper ore, one tin ore and one charcoal per ingot. Completion teaches bronze locally; subsequent real work trains smithing. Axes and sickles have persistent serials, wear and material-paid qualified repair. Imported goods grant no manufacturing knowledge. Masonry knowledge follows completed real brickwork; completed physical barter teaches local trade practice.

Grain processing spends the edible ledger into physical ingredients once, returning one consumable ration per two grain. The ration reduces hunger and is consumed. The new farm enclosure enables existing worker-sown plots; its sprite contains empty beds, never fake grown crops.

A water lift requires irrigation knowledge, a real nearby surface-water cell, a qualified keeper, eight work actions and one fibre unit of upkeep. Each cycle supplies two nearby sowing allocations for 120 ticks. It generates no water, seed or food. Abandonment, damage, exhausted allocations and absent water stop service.

The market uses existing physical inventory exchange. The meeting hall uses existing social decisions; it does not claim an implemented government system. Granaries protect finite food reserves. Residential buildings provide finite household capacity. Existing historical architecture survives later knowledge changes.

Planner support goals are keyed by archetype: a charcoal clamp cannot suppress a cordage yard, kiln or forge. Housing, food reserves, workforce, knowledge, stock and finite resource plans remain gates. Water and deposits are hard site requirements. Proposals retain demand, site score, reason, priority and projected benefit. Facility purposes, inputs, completed cycles and active irrigation capacity are exposed in settlement inspection.

## Artwork and review

Two source sheets were produced with built-in reference-guided image generation. Exact prompts are in `source-prompts.json`. The original premium sheet and all original 330 atlas entries remain intact. The added page now holds 28 unique cutouts, up to 64×64 logical pixels: two runtime texture pages total. Binary alpha and nearest sampling preserve crisp pixel edges.

The old saw-equipped source cell remains withheld. A separate stone-tool timber workyard supplies that role. New Batch B furnace sprites have no static fire and the farm has no grown crops. Contact sheets show actual packed runtime pixels. Internal review covers silhouette, material/roof detail, lighting and scale; final phone/owner visual approval remains pending.

Evidence: the three age contact sheets, `batch-b-reference-comparison.png`, `chronological-i-iii.png`, `batch-b-world.png`, `batch-b-bronze-detail.png`, `batch-b-damage.png`, `batch-b-abandoned.png` and `batch-b-inspector.png`. Terrain captures use real Linux GL Compatibility rendering, not Android screenshots.

## Validation

The 28-suite runner passes 72 Batch B checks, the previous 96 architecture checks and 26 regression suites. Construction and production use finite terrain resources and real worker jobs. Controlled knowledge/XP establishes earlier prerequisites; a finite opening grain credit is disclosed for processing tests. These fixtures do not prove autonomous invention of agriculture, pottery, weaving or irrigation from an unseeded world. Bronze and masonry discovery are exercised through paid real work.

Tests include material scarcity, absent operating inputs, finite irrigation capacity, qualified tool repair, independent specialist proposals, labour distribution, mid-service compressed saves, persistent serials, JSON restoration, deterministic replay and rejection of fabricated service capacity. `validation-results.json`, `performance.json` and `android-build.json` record results and platform details.

The Linux simulation benchmark still exceeds a 100 ms p95 tick at 1,500 citizens. Accelerated simulation and mobile frame pacing remain open. No Huawei P30 gameplay or GPU measurements were performed.

## Remaining gates

Batches C (Ages IV–VI), D (VII–IX), E (X–XI) and full F have not been executed. This is a Batch B content/integration delivery, not full eleven-age completion.

- Coastal/island, alpine, steppe and wetland artwork, live geographic/climate selection and cultural diffusion remain open. Current real regional gates use the existing settlement context.
- Shared construction stages, worker choreography, cracks, abandonment overlays and persistent rubble work. Authored individual construction/damage/ruin sprites, multi-crew public projects and advanced roof occlusion remain open.
- The engine exposes a single surface-water mask and seeded mountain resources. Freshwater/salinity, flow, aquifers, underground geological discovery and distribution networks are not implemented. The lift is constrained by that mask, not a full hydrology model.
- Missing early-age categories include dedicated husbandry/hunting facilities, defence, religious institutions, recordkeeping/government, roads/drainage variants and comprehensive maritime infrastructure. They are not counted as delivered because a role ID exists.
- Later-age iron/steel/concrete/electronics and advanced manufacturing, power grids and scientific/medical/military institutions remain later work.
- Full Android gameplay, dense-city/accelerated phone profiling and Huawei P30 owner visual approval are pending. No overnight or scheduled workers were started.
