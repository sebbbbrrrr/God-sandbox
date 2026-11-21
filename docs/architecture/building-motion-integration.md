# Building assembly and operational animation — initial integration

Base: `feature/architecture-batch-b-bronze` (PR #38). No change to construction quantities, labour costs, AI decisions, production output or saves.

## Implemented
- Existing construction presentation now reveals twelve foundation blocks, six uprights, seven wall courses and nine roof courses incrementally using the **persisted real stage labour progress**. Material families influence visible blocks and boards.
- Facility motion pass is connected to the existing building-state overlay, is screen-culling aware, caps animated structures per frame and runs only when a real `operate` job is on site or a paid water-lift service remains in effect.
- Grain-grinding shelter: rotating mill mechanism; water lift: rotating wheel and water detail; timber and masonry yards: reciprocating work; weaving and cordage: tool oscillation; pottery, charcoal, bronze smelting and forge: embers.
- Idle production buildings do not falsely animate as working. Existing architecture sprite identity remains unchanged, and no low-resolution replacement building assets are introduced.

## Remaining before the full user-requested 11-age art pass
- Authored layer-by-layer pixel construction for each individual atlas sprite, not shared procedural overlays.
- Individual brick/plank-level exact material custody mapping for every building (the incremental artwork currently follows stage labour; units are decorative, not a one-to-one count of consumed materials).
- Animation sheets, correct silhouettes and anchoring for each specific facility, including planned later-age windmills, powered mills, pumps, chimneys, industrial machinery and future technologies.
- Screen captures, Godot headless tests, Android export and Huawei P30 testing; **not run on this branch**. Inspect visual alignment and performance before merge.
- Reconcile parallel branches and ensure the construction/state visual draw pass is wired into the actual integrated game entrypoint; these scripts already existed on the parent branch.

## Acceptance tests to run
1. Begin a new build and verify that each visual course arrives only after a real advancement, freezes on paused sites, and survives save/reload.
2. Verify site resources remain conserved and a delivery alone does not complete a wall.
3. Verify milling wheel only rotates while a worker performs an `operate` job, and that kiln and smelter effects stop when idle.
4. Verify paid water-lift activity expires, damaged/abandoned buildings do not animate, and no new motion appears in the wrong sprite.
5. Profile zoom, accelerated time and many simultaneous buildings on Huawei P30 with GL Compatibility.
