# Architecture integration — Batch A and Batch B

**Status: Batch B content and functional integration completed for Ages I–III. Full eleven-age, regional/state artwork and physical-device acceptance remain open.**

This phase adds 13 designs on `feature/architecture-batch-b-bronze`, stacked on PR #37. See [Batch B delivery report](batch-b-delivery.md) for exact scope and limitations.

This branch starts from premium UI commit `9bc108b21f30d14442a12291a939b02ea09fd029` (PR #36) and deliberately integrates workforce/tool fixes from PR #35. It does not merge either PR into main. No scheduled workers were created.

## Audit and preserved dependencies

All 16 pages of *God Sandbox Civilisation Evolution Master Design* were reviewed. Its era labels describe demonstrated capability; they grant no technologies. Its original implementation-status page is historical, so current source and tests were used for this audit.

| System | Audited state and treatment |
|---|---|
| Original art | `tools/source/settlement_phase1b.png` is the visual reference. Original 330 atlas entries and original texture pages remain intact; deterministic rebuilding is tested. |
| Earlier architecture PR #25 | Its 80 low-detail procedural buildings were visually compared and left out of this branch. They have not been silently merged or counted. |
| Original atlas pipeline | Existing `build_pixel_assets.py` / `expand_pixel_assets.py` preserved. `pack_architecture.py` appends a separate page. |
| Construction | Existing material custody, reservations, staged work, repair, conversion and demolition remain the authority. No parallel construction engine. |
| Citizen work | PR #35 source claims, congestion handling, priorities and compact equipped tools integrated. A Godot 4.5.2 inferred-type error was corrected. |
| Settlements / roads / trade | Phase F ancestry retained. Existing planner, real road ledger, storage and barter reused. |
| Skills / technology | Existing per-settlement knowledge and per-person XP used. Pottery and weaving operational paths added; arbitrary calendar unlocks remain absent. |
| Physical economy | Original item IDs reused. Finite clay, sand and reeds extraction added with shared shore depletion. Brick firing now consumes charcoal. |
| Saves | Nine original building IDs, their recipes/stage counts and original art references retained. Optional architecture provenance persists; legacy saves and compressed saves are regression-tested. |
| Parallel audio / destruction / nature | PR #30 and Nature A1 #32 are not included here. Their separate branches have not been overwritten. |
| Later ages | Specialist role IDs already exist, but most later-age manufacturing, utilities, infrastructure and scientific discovery remain unfinished. No later-age buildings are falsely enabled. |

Initial inventory: [initial-inventory.json](initial-inventory.json).

## Actual delivered content

- **28 authored integrated building designs**, including 13 added in this phase. Each of Ages I, II and III now has **eight distinct authored functional archetypes**. Housing variants share one archetype.
- **37 canonical definitions** including the nine preserved legacy IDs, in `data/buildings/catalogue.json`. It replaces the old phase-specific data file; all runtime references use the canonical catalogue.
- The exact eleven age names and eight extensible regional grammar slots. Actual authored regional adaptation covers woodland, cold, desert and tropical structures only.
- One separate 1024×512 RGBA runtime page containing 28 new, alpha-thresholded, nearest-sampled cutouts, up to 64×64 logical pixels. Terrain remains 32×32; new footprints occupy 2×2 cells.
- Original commissioned source sheets plus a reproducible packer, exact sprite metadata, ground anchors and fingerprints. Built-in image generation was used, with the original premium sheet as the style reference. These are generated source artworks, not a claim of manual pixel-by-pixel authorship.
- The old saw-equipped source cell remains withheld; a separate stone-adze timber workyard replaces its intended function with era-appropriate art.
- Exact integer recipes, stage costs, repairs, supported workstations, inputs/outputs, construction work, occupancy, storage, regional restrictions, operating limits and purposes.
- New factories use actual citizen jobs: pick up physical inputs, walk to the facility, spend work actions, commit an atomic recipe, carry outputs back. Charcoal, brick, woven cloth, cordage, planks/beams, masonry, bronze ingots/tools and edible grain rations use this path. A qualified potter can learn bronze from a paid ore/fuel trial; real practice trains the smith. Irrigation uses labour and fibre upkeep for two time-limited allocations. Knowledge, trained roles, tools where relevant, condition and input availability govern work.
- Live nearby granaries protect at most 120 grain units per Age II granary and 180 per Bronze granary from annual recorded 5% exposed-grain loss. Abandonment or insufficient condition removes protection. No grain is generated by a granary.
- Explainable site scores, source allocation, projected service capacity, priority and blocked prerequisites in settlement inspection. Shared-source allocation cannot spend the same forest/shore units twice.
- Saved architectural identity survives later knowledge changes. New roof silhouettes are not assigned merely because a year or age label changes.
- Normal 1× remains one real second per authoritative tick, with existing movement interpolation. Construction remains capped at one worker per current site; operational recruitment is capped at two workers per settlement and one per building.
- Operational candidate IDs are cached by building revision and settlement. No per-frame per-building simulation loop or individual sprite nodes were introduced.
- Actual building ground uses original terrain. False automatic path grids and square garden/foundation props were removed from physical footprints; actual constructed roads remain authoritative.
- Shared condition cracks, abandonment vegetation and persistent collapse rubble supplement existing construction/worker choreography. These are explicitly **not a completed set of authored damage/state sprites**.

## Validation evidence

`tests/run_architecture_qa.py` executes two architecture integration suites plus 26 existing regression suites with Godot **4.5.2**, rejects script errors even when the engine returns zero, and writes [validation-results.json](validation-results.json).

The two suites construct all twenty-eight designs through finite extraction, real delivery, material consumption and worker stages. It covers production fuel, weaving, regional construction gates, knowledge loss, scarce supply plans, architecture persistence, corrupted visual identities, repair, collapse and both JSON/compressed saves. Controlled scenario knowledge/XP establishes prerequisites; this is **not evidence of a complete autonomous pottery/weaving invention system**. Separate regression tests run actual `world.step()` shelter founding and deterministic continuations.

- [Atlas rebuild checks](../../tests/atlas_integrity.py): 358 non-overlapping regions, original art fingerprints, binary alpha and deterministic rebuilds.
- [Integration tests](../../tests/architecture_integration_test.gd).
- [CPU benchmark](performance.json): 160 / 500 / 1,500 citizen scenarios, 240 ticks each, percentile timings, memory, save size and conserved food/material ledgers.
- [Android build verification](android-build.json): local arm64 debug export, signature and ZIP verification. This records an APK build, not a physical-device test.

Commands:

```sh
python3 tests/atlas_integrity.py
godot --headless --editor --path . --import --quit
python3 tests/run_architecture_qa.py --godot /path/to/Godot-4.5.2
godot --headless --path . --script res://tests/architecture_benchmark.gd
godot --path . --script res://tests/capture_architecture.gd
godot --path . --script res://tests/capture_architecture_batch_b.gd
```

The benchmark measures Linux CPU simulation cost, not Android FPS. The 1,500-citizen p95 exceeds 100 ms/tick, so accelerated simulation and phone frame pacing remain outstanding. Source sheets and documents are excluded from Android export; runtime atlas data stays included.

Source artwork: [Stone Age sheet](../../tools/source/architecture_stone.png), [Agricultural sheet](../../tools/source/architecture_agricultural.png), [runtime atlas](../../assets/pixel/architecture_early.png). [Exact generation prompts and mode](source-prompts.json) are retained alongside the deterministic packing instructions.

## Visual review

- [Original/new reference comparison](reference-comparison.png).
- [Age I contact sheet](age-1-contact.png), [Age II contact sheet](age-2-contact.png), [Age III contact sheet](age-3-contact.png).
- [Batch B reference comparison](batch-b-reference-comparison.png), [I–III progression](chronological-i-iii.png).
- [Batch B actual terrain](batch-b-world.png), [Bronze detail](batch-b-bronze-detail.png), [facility inspector](batch-b-inspector.png).
- [Regional geometry comparison](regional-comparison.png).
- [Actual world showcase](world-showcase.png) and [close detail](world-detail.png).
- [Damage and abandonment](damaged-abandoned.png), [collapse rubble](collapsed-ruin.png), [survey](construction-survey.png), [construction work](construction-work.png).

World captures use the actual Godot GL Compatibility renderer under Linux software OpenGL. Showcase buildings are constructed with real resources in a controlled comparison scenario. They are **not Huawei P30 screenshots**, a naturally evolved regional world or evidence of Android GPU performance. Internal comparison found coherent density, roof/material detail and silhouettes at logical scale; final visual approval on the phone remains pending. Static kiln glow and general shared construction/damage overlays still need state-specific art refinement.

## Coverage and remaining acceptance gates

[coverage.json](coverage.json) and [coverage.csv](coverage.csv) enumerate all eleven ages × eight regions, exact asset counts, categories, integration, recipes, animation and visual approval. No empty age or recolour is counted as complete.

| Batch | State |
|---|---|
| A — audit, reference, catalogue and integration foundations | Implemented and locally validated |
| B — Ages I–III | Content benchmark and real production/construction integration implemented: eight authored archetypes per age. Full regional/state/mobile gates remain in F. |
| C — Ages IV–VI | Not executed |
| D — Ages VII–IX | Not executed |
| E — Ages X–XI | Not executed |
| F — full regional/state art and end-to-end mobile verification | Not executed; only shared effects and early regression coverage delivered |

Outstanding work includes: complete eight-archetype coverage for Ages IV–XI; Ages IV–XI source artwork and functional buildings; iron/steel/concrete/electronics/advanced-material inventories and manufacturing; physical power/water/utility networks; scientific, medical, military, maritime and far-future institutions; transport/finance prerequisites where appropriate; complete live geographic/climate selection and cultural diffusion; coastal/alpine/steppe/wetland authored families; multi-crew public construction; authored per-building construction, operating, damaged, neglected and ruin sprites; advanced collision/entrance/roof-occlusion rules; full eleven-age scenarios; dense-city/accelerated Android profiling and **Huawei P30 gameplay testing**.

This branch is a reviewable foundation and early-age implementation, not the full eleven-age completion requested.
