# Android interface audit — 20 November 2026

Audited actual source and ran the unified integration suite on Godot 4.5.2 before UI edits (20 integration assertions passed).

## Isolated baseline

`feature/android-premium-hud` starts from unified Android integration `e0a62c0`; includes the existing pinch anchoring fix `304d804` and display pacing fix `b50342c` before interface work. These are controller changes only. No new AI, construction, inventory-authority or simulation changes belong to this task.

## Actual surfaces and ownership

| Surface | Runtime implementation | Observed behaviour before overhaul |
| --- | --- | --- |
| Main scene | `scenes/world.tscn` → `scripts/unified_game.gd` | Composes D4 simulator, high-definition renderer and HUD; main branch is an older frontend |
| Gameplay HUD | `scripts/sandbox_ui.gd`, CanvasLayer 10 | Procedural Controls; top 62px bar; bottom 72px dock |
| Tool navigation | `sandbox_ui.gd` | Hand / Items / Powers / active tool / brush; five category tabs buried inside Powers; duplicate powers in overlapping categories |
| Terrain / god powers | `terrain_brush.gd`, `unified_game.gd`, inherited `game.gd` | Six actual powers: Raise, Fire, Forest, Bless, Spawn, Ocean; terrain brush supports three radii |
| Touch / camera | `game.gd::_input`, overridden by `unified_game.gd` | Raw ScreenTouch plus emulated mouse for native GUI; brush drag, hand drag, two-finger camera; pinch fix retained |
| Input hit regions | `sandbox_ui.gd::blocks_world_input` | Manually enumerated rectangles; any touch including UI-origin enters inherited gesture map, allowing UI fingers to become camera fingers |
| Citizen / inventory inspection | `ui/item_inspector.gd`, `ui/item_overlay.gd`, `ui/unified_world_overlay.gd` | Hand-drawn modal at layer 20; fixed 188px legacy toolbar allowance; fixed row/39px close/29px tabs; raw modal handler intercepts before native Controls |
| Terrain / citizen card | `sandbox_ui.gd` | Small fixed card; citizen age uses old counter instead of biological calendar; refresh string contains literal escaped newlines |
| Pause / speed | `unified_game.gd` | Working pause and 1×/2×/4×; top targets only 42px; old HUD reports year as tick/3600 instead of actual 2400-tick calendar |
| Save / load | `game.gd` | Single automatic `user://world.json` plus manual write; restore only on launch; no load interface, slot picker or world regeneration UI |
| Settings | `sandbox_ui.gd` | Fixed unscrollable popup; animation preference not persisted; manual save announces success regardless of IO result |
| Motion | `sandbox_ui.gd` | Starts press animation after release; repeated presses create competing tweens; palette travels full panel height; separate inspector tween |
| Scaling / orientation | `project.godot`, `sandbox_ui.gd::_layout` | 480×850 canvas, fixed 10px margins; no physical safe-area conversion; landscape sidebar can overflow on short screens |
| Assets / components | `assets/pixel`, `pixel_atlas.gd`, embedded HUD SVG strings | Original atlas and pixel art preserved; no shared UI token, button, icon or motion component |

## Refactor boundaries

Keep all six power IDs, conserved physical inventory actions, save schema, world picking, brush radii and renderer. Use native Controls for the complete active frontend. Reuse `item_inspector.gd` as the inventory model, without modifying its authority or legacy tests. Read calendar/occupation summaries rather than inventing era progression. Add UI-only extension surfaces for later tools. Do not expose categories without working actions.
