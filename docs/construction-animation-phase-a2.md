# Phase A2 — construction work animation coverage (20 November 2026)

## Integration
Branch: `feature/physical-work-animations-realtime-1x`, PR #22, based on the separate Phase A construction PR #20. Never merge main implicitly.

The viewport overlay reads real `world.construction.jobs`, `site_by_id`, `building_by_id`, the actual citizen positions and movement interpolation, actual `cargo`, actual `stage`/`stage_work` and real `delivered`/`consumed` inventories. No animation creates materials, grants labour, completes stages, or changes save data.

### Construction choreography implemented
- Resource extraction: wood chopping and stone mining / pickaxe-like motions, wood chips and stone flecks.
- Movement/logistics: visible bundles of timber/fibre/stone while jobs carry them, stride dust while moving, depot pickup and drop-off handling, site unload gestures.
- Site prep: vegetation clearing, sweeping/brush movement, digging, levelling and survey stake hammering.
- Structural: wood sawing, masonry, lifting beams, nailing/hammering, joining and bracing.
- Finishing: roof placement, thatching, plastering, door fitting, painting and final sweeping.
- Lifecycle: repair hammering and demolition strikes/debris.
- Physical building progress: partial foundations, stones, posts, beams, braces, planks, roofing, ridge strips and door appear as the *authoritative* site stage and work counter advance. Loose material piles are derived from delivered minus consumed counts. Paused sites tint and stop site-labour effects.

The 1× simulation now advances an authoritative tick each real second at normal sustained frame rates. 2× and 4× retain their chronological accelerations. Walk presentation interpolation uses approximately 0.85/0.425/0.2125 seconds per tile change at 1×/2×/4×, without skipping the underlying AI movement. Work visual time advances at game speed and freezes when paused.

## Implementation limitations
These are distinct procedural **visual gestures**, not authored frame-by-frame character sprite sheets or independent profession systems. Phase A has only three underlying building stages, two example dwelling designs, one builder per site and existing repair/demolition jobs. Gesture variants rotate within a stage for visual variety, but *sawing*, *masonry*, *painting*, etc. do not represent independently tracked simulation subtasks until construction AI acquires that structure. Likewise the pickup/drop-off gestures are present in their real job states but are not yet guaranteed to display for a minimum visible duration when a pickup/delivery resolves in a single tick. Workers may use a generic hand-held prop rather than a context-correct equipped tool sprite. No building interiors, roof-climbing navigation, scaffolding collision, crew choreography, full eleven-era regional art catalogue, physics-based debris or sound are implemented. No simulation tick duration equals one real-world hour/day.

## QA
Code committed. The extra `tests/construction_animation_test.gd` checks stage action selection, no stage mutation, loaded renderer, 1× pacing and initial walking duration.

Run:
```sh
godot --headless --path . --script res://tests/construction_animation_test.gd
godot --headless --path . --script res://tests/universal_construction_test.gd
godot --headless --path . --script res://tests/construction_benchmark.gd
godot --path . res://scenes/construction_demo.tscn
```

The first pass has not been executed here because the environment has no Godot binary. Android export, gameplay screen capture and Huawei P30 FPS/thermal testing are not yet verified. Do not treat static code as a passed build. Verify 1×/2×/4×, pause/resume, 20 and 500 citizens, interrupted jobs, cargo conservation, pan/zoom, construction/save continuity, reduced-motion preference and performance culling before merge.
