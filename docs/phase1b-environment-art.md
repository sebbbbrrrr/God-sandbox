# Phase 1B environmental art expansion

Implemented on `dev/phase1-pixel-art`, based on Phase 1A commit `d89f695e8a9cf127fb01898ee2b548556a9c7575`. No merge with main or the citizen AI branch. Simulation, input, camera, UI and save schema are unchanged.

## Shipped artwork and exact locations

The original 231 regions remain. The atlas now contains **330 regions**, all on **one 1024 × 1024 RGBA runtime page** at `assets/pixel/sprite_atlas.png`. Its uncompressed base texture footprint remains 4 MiB (driver/import overhead excluded). The additional 99 regions comprise:

| Addition | Regions | Authoring source |
| --- | ---: | --- |
| Vegetation | 23 | `tools/source/nature_phase1b.png`, cells 0–22, row major, 8 columns |
| Landscape objects | 9 | Same source, cells 23–31 |
| Buildings, two designs per type | 20 | `tools/source/settlement_phase1b.png`, cells 0–19 |
| Settlement props | 12 | Same source, cells 20–31 |
| Ground materials | 16 | `tools/source/terrain_phase1b.png`, 4 × 4 grid |
| Connected paths, shadows, cliff overlays and shoreline scatter | 19 | Pixel geometry authored in `tools/expand_pixel_assets.py` |

`assets/pixel/README.md` lists every region's exact packed rectangle, page and provenance. `assets/pixel/atlas.json` is the authoritative machine inventory; `pages.json` identifies runtime pages. `expansion.png` is the authoring cutout atlas. Authoring sheets are excluded from Android export by the existing export preset.

Vegetation includes oak, birch, willow, beech, maple, spruce, cedar, juniper, two saplings, dead/fallen trees, shrubs, ferns, wildflowers, tall grass, moss logs, reeds, cattails, leaves, mushrooms, roots and branches. Landscape objects include pebbles, granite/sandstone/moss boulders, a mountain spire, cliff debris, driftwood, coastal stones and shells. Buildings include huts, cottages, stone houses, workshops, stores, farmhouses, barns, market stalls, watchtowers and town halls. Props include fences, walls, gardens, crops, wells, a cart, crates, hay and a chopping block.

## Source provenance and authoring

The three new source sheets are original images generated for this project, then sampled onto the project's pixel grid. No external game assets were copied. Generation briefs specified crisp top-down pixel art, angled roofs, earthy olive/teal/warm stone colours, top-left lighting, isolated transparent sprites, no text, consistent scale and clearly distinct silhouettes. Nature and settlement sheets use eight columns and four rows; the ground sheet uses four columns and four rows. Source files are reduced with nearest-neighbour sampling to 1024 × 512 and 512 × 512 respectively to avoid shipping unnecessarily large authoring images.

Run `python tools/expand_pixel_assets.py` with Pillow installed. It first reproduces Phase 1A using the existing generator, then extracts the new cells, removes translucent generation fringes, resamples with nearest-neighbour interpolation and packs the unused atlas quadrant. Ground material borders are irregularly blended offline against the existing material; grass colours are conditioned to its palette. This prevents obvious square colour seams without additional runtime draws. Trees and buildings keep their distinctive source artwork. New cutouts have binary alpha and content fingerprints in the metadata.

Overflow is supported: after the 64 free object slots, the packer creates `sprite_atlas_1.png` and subsequent 1024-pixel pages in deterministic order. The loader, thumbnail bake and command draw select the correct page. Phase 1B needs no extra page or texture switches. Automated checks exercise overflow boundaries, uniqueness, bounds, transparency, overlap and byte-identical regeneration.

## Renderer integration

- Coordinate hashes select new ground textures, mixed tree species, sparse understory, deadwood, coastal debris and mountain formations without touching simulation RNG.
- The 16 × 16 chunk architecture, visible culling, row depth sorting, static caches and three screen-tile LOD thresholds (13 / 30 pixels) remain intact.
- Trees/buildings receive cached grounding shadows; cliffs receive directional edge highlights, strata and debris. No lighting pass or full-screen postprocessing was added.
- Settlement buildings use the existing TOWN/capital data. Deterministic local anchors leave separation between large footprints; other town tiles show gardens, crops or wells. Fifteen directional path joins connect surrounding ground to existing town/capital routes. All buildings are visual representations; they do not imply a new economy or construction system.
- Four cardinal terrain masks are calculated once per rebuilt tile. Paths are recalculated for settlement changes and blocked/restored connections; ordinary walkable material edits keep the path cache. Terrain signals still dirty the complete one-cell chunk halo.

## Repeatable validation

`tests/capture_environments.gd` captures forest, coast, mountain/cliffs, populated settlement and an unmodified procedural world. Seed 424242, identical fixture edits/heights, 160 citizens, fixed simulated steps and camera settings are shared with the baseline. These are actual Godot GL Compatibility screenshots, including the game UI.

`tests/benchmark_renderer.gd` uses a 480 × 850 viewport, 40 warm-up frames and 180 measured frames per case, with 160 / 500 / 1500 citizens. The simulation is paused except for one explicit step every six measured frames, so both versions advance identically. It reports mean, p50, p95, worst frame time, draw calls, visible chunks and Godot static memory. This is a revised deterministic version of the Phase 1A benchmark, so older unpaused figures must not be compared directly. The 150th simulation step deliberately retains real settlement expansion and any resulting rebuild spike.

`tests/benchmark_paint.gd` times CPU brush mutation plus synchronous chunk rebuild, separately from GL presentation: radius-two strokes from (44,62) to (52,66), alternating Raise/Ocean, four warm-ups and 24 measured strokes at each of 8 / 24 / 48 screen pixels per tile. No no-op strokes are timed.

The Android workflow archives the exact baseline commit, copies the same diagnostic helpers into it and captures/benchmarks both versions on the same runner. It records a 12-second, 360-frame Godot movie at 480 × 850 / 30 fps, encodes MP4, and exports the ARM64 debug APK. The movie is a scripted camera tour with real simulation stepping and a blessing effect, not a manual touch-control recording.

Local and Actions numbers describe Linux software GL, not Huawei P30 hardware. Detailed measurements and artifact references are recorded after validation. The simulation/AI performance figures from Phase 2.5 concern another branch and are not rendering baselines for this work.

## Deliberately postponed / limitations

No economy, building functionality, construction, new AI, weather, full-screen lighting or population aggregation. Shore geometry remains the existing grid and transition-mask system. Individual tree spacing and town planning are stylised rather than a full biome/urban simulation. Dense forests still intentionally overlap tree canopies. Headless/GPU-software checks do not establish Android thermals, touch latency, memory pressure or sustained hardware frame rate; Huawei P30 testing remains required.

## Verified local measurements — 20 November 2026

Godot 4.5.2, Linux Xvfb, Mesa 25.0.7 llvmpipe software GL. One sequential matched run per version; shared-runner timing noise applies. Same seeds, cameras, resolution, simulation schedule and sample counts as above. These are frame times, not simulation-step timings.

| Zoom / citizens | Mean ms before → after | p95 ms before → after | Worst ms before → after | Draw calls before → after |
| --- | --- | --- | --- | --- |
| 0.5 / 160 | 5.03 → 5.36 | 8.82 → 12.54 | 21.43 → 23.36 | 74 → 74 |
| 1.0 / 160 | 6.88 → 7.82 | 11.98 → 11.51 | 18.61 → 19.16 | 38 → 38 |
| 2.0 / 160 | 5.66 → 6.16 | 12.14 → 8.90 | 18.31 → 42.96 | 38 → 38 |
| 1.0 / 500 | 7.60 → 8.31 | 11.76 → 11.94 | 51.94 → 35.32 | 38 → 38 |
| 1.0 / 1500 | 8.25 → 9.19 | 13.25 → 15.00 | 77.33 → 70.82 | 38 → 38 |

| Brush screen pixels per tile | Mean CPU rebuild ms before → after | p95 ms before → after | Worst ms before → after |
| --- | --- | --- | --- |
| 8 | 23.72 → 15.72 | 25.32 → 16.46 | 25.68 → 16.66 |
| 24 | 18.82 → 11.10 | 20.55 → 11.67 | 32.12 → 12.01 |
| 48 | 18.39 → 11.98 | 19.12 → 16.57 | 19.94 → 26.79 |

Godot tracked static memory at the end of the 1500-citizen case: 41.90 → 42.51 MiB. This excludes driver memory and is not Android process RSS. The single-edit diagnostic measured 20.54 → 11.44 ms. The sustained brush benchmark is more representative than that single sample.

The extra artwork increases routine close/medium rendering cost on software GL; unchanged batching does not remove pixel-fill or command-processing cost. Painting improves on average. Full network invalidation on real settlement growth still causes a visible worst-case rebuild spike; this was retained in the measurements rather than excluded. No physical Android performance claim is made.

Baseline regression suites passed (306 rendering and 26 input assertions plus simulation suite). Expanded suites passed (482 rendering and 26 input assertions plus simulation suite). Godot editor import and main-scene startup passed. Atlas integrity and byte-identical regeneration passed. Existing save round-trip, legacy migration, RNG continuation, all six powers, raised picking, terrain editing and renderer/simulation isolation remain covered.
