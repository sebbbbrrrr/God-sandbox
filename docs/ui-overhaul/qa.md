# Android UI QA — 20 November 2026

## Verified

Godot **4.5.2 stable**, GL Compatibility. The actual `world.tscn` uses the unified runtime with the D1–D4 backend and the high-definition renderer. The UI is not a separate demo scene.

The dedicated workflow runs **19 suites**: premium HUD, native input, save/controller restore, legacy input, pinch anchoring, unified scene, legacy item UI, item inspector, item catalogue, physical inventory, toolmaking, autonomous toolmaking, construction, food survival, occupations, simulation, calendar/lifecycle, households and citizen AI. It rejects script errors even when Godot exits with code zero.

- **441 HUD/layout/state assertions** across 320×568, 360×780, 400×866, 480×850, 866×400, 640×360, 1024×768 and 1280×800 logical canvases, plus P30 1080×2340 / 2340×1080 physical-density checks.
- **33 native interaction assertions**, including actual viewport-dispatched button events, each working tool category, power selection, pause/speed, UI/world finger isolation, modal interruption, jitter, Android cancelled events, minimal-view restoration and exact-serial Take → Equip → Drop with a conserved ledger.
- **38 existing input assertions**, now targeting the actual unified frontend rather than the discontinued renderer shell.
- **19 pinch checks**, retaining finger midpoint anchoring, camera pan, zoom reversal, clamps and mouse wheel anchoring.
- Atomic JSON save/reload with full float precision, exact inventory counts, typed food/demography arrays, real crafted tools, in-flight work and deterministic continuation. Actual reload replaces both authoritative world and renderer. Failed save displays failure; corrupt reload keeps the current world.
- Android debug APK export, project import and scene smoke tests.
- Real Godot GL captures: portrait gameplay, Terrain, Nature, World information, menu, empty and stocked inventory, minimal view, landscape tray/menu, small phone and simulated safe-area insets. The stocked inventory capture uses a test fixture that physically harvests and crafts two axes; no test fixture runs in gameplay.

## Visual review and fixes

The first GL capture exposed zero-width text in horizontal button content despite correct hit rectangles. The shared component now allocates expanding caption width, with geometry assertions. The reviewed captures show readable labels, consistent target sizes and clear selected states. Physical item rows reuse D4 pixel icons. Tool/menu close headers remain pinned while their bodies scroll. Smaller viewports retain full-size targets and scroll content. Safe-area controls stay inside the simulated insets.

## Inherited suites outside this UI change

A broader audit additionally ran three older suites against the untouched shared baseline `e0a62c0` and reproduced their failures:

| Suite | Reproduced baseline issue | Boundary |
| --- | --- | --- |
| `autonomous_demography_test.gd` | Untyped `first` / `second` Variant inference fails Godot 4.5.2 parsing | Existing backend test; no demography edits in this branch |
| `citizen_cognition_test.gd` | Raw `Simulation.from_snapshot(JSON.parse_string(...))` bypasses integer/typed-array restoration; an older manually cleared fixture also fails restore | UI file adapter is verified; the direct backend entry point remains unchanged for the parallel simulation work |
| `rendering_test.gd` | Raw JSON restore returns null, then the test dereferences it and does not terminate normally | Same bypass; the missing application icon check was separately corrected in project settings |

These are not represented as passing. The application frontend uses the tested file adapter. The backend JSON loader should adopt equivalent boundary normalization in its own coordinated change.

The legacy item UI fixture previously queried viewport geometry during SceneTree initialization. Its execution is now deferred until its viewport is actually in the tree; its original assertions remain intact.

## Physical device work still required

No physical Huawei P30 was connected. Do not interpret desktop software-rendered captures as a device FPS or touch-comfort benchmark. Check taps and brush drag on the P30, two-finger zoom, Android Back, rotation/cutout insets, inventory swipes, haptic preference, save/restart/reload and 1×/2×/4× frame pacing before merging. No claim of a locked 60 FPS, production signing or a store-ready release is made.

The feature branch and draft PR remain separate from main and the autonomous construction work.
