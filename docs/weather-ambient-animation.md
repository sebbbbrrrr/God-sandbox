# Weather-driven ambient animation

This change is based on `dev/phase1-pixel-art` and is intentionally kept separate from the citizen AI, movement and main branches. Weather is visual-only: it does not create storms that harm citizens, change crops, ignite fires or mutate terrain. It has no save-schema migration.

## Cycle and saved worlds

`scripts/weather_cycle.gd` samples the simulation clock (world tick × 0.1 seconds). It passes through Calm → Breezy → Windy → Rain → Breezy → Storm → Calm → Rain, each lasting 75 simulated seconds. Transitions ease over 14 seconds. Seeded horizontal wind direction and sine-based gusts vary smoothly without consuming the simulation RNG. Pausing freezes ambient motion, and the simulated speed control accelerates both weather and sway. Reloading a world resumes the same weather phase from its existing saved tick.

## Rendering and layering

- Normal terrain, building props and cliffs remain static and retain the current dirty-chunk and three-level LOD architecture.
- Only tree species, meadow saplings, shrubs, reeds, selected wildflowers and ferns are placed in per-row `wind_rows` CanvasItems. Small rotations are anchored at each sprite's foot; the drawing positions and seed-derived phase keep neighboring trees from moving identically.
- The visible vegetation nodes redraw at most 15 times per second; no chunk re-bake or terrain invalidation happens for weather. At distant zoom, trees remain baked and stationary.
- A separate overlay draws at most 110 semi-transparent rain streaks over the visible world in rainy/stormy phases. No particle system, shader, texture allocation or simulation entity is involved.
- Water ripple alpha responds slightly to wind. The top bar shows the current named weather state where there is enough horizontal room.

## Review/testing

The existing `tests/rendering_test.gd` now covers phase selection, smooth weather values, deterministic re-sampling, starting clear, metadata alignment, rain overlay construction, animated vegetation presence, and avoiding static chunk rebuilds. The standard GitHub Android workflow already runs this test, performs benchmark captures and exports a debug APK when manually dispatched on the feature branch. The branch has **not** been physically tested on Huawei P30; compare warm/cold performance and visually inspect full-speed rain and foliage before merging.

Manual checks: play for eight 75-second phases (or run a scripted time sampler), pause and change simulation speed, pan/zoom through forests and coasts, paint new forest while weather is active, verify tree feet do not shift, inspect rainfall at low/medium/high zoom, and load an older world save.
