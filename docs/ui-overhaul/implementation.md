# Android UI implementation

## Shipped frontend

The unified scene uses a 6-category native dock: Terrain (Raise/Ocean), Nature (Forest), Life (Human/Bless), Chaos (Fire), World (real calendar and settlement capability summaries), Menu (inventory, save/reload and preferences). These are the six actual powers already supported by the runtime; there are no placeholder construction, economy or civilisation actions.

A slim tool context row holds Hand, the active tool and brush size. Category changes browse without changing the equipped power. Selecting a power closes its tray. Tapping the equipped name returns to Hand. Three brush choices remain available in terrain trays. Short windows scroll the tray instead of shrinking touch targets.

Minimal view hides all primary surfaces, temporarily uses Hand for navigation, and retains a 48-unit restore target. Restoring brings back the equipped tool. Android Back/Escape closes the current surface, restores a hidden HUD or puts a tool away before opening the world menu.

## Components and proportions

| Token | Logical units / behaviour |
| --- | --- |
| Spacing | 4 / 8 / 12 / 16 / 24 / 32 |
| Minimum actionable target | 48 × 48 |
| Icons | 24, cached SVG; actual D4 pixel icons for physical items |
| Category dock | 68 high; 6 equally weighted labelled icons |
| Context row | 56 high |
| Tool cards | 80 high |
| Panel padding / radius | 12 / 18 |
| Press compression / release | Inner content only; 60 ms / 100 ms |
| Surface entrance | 180 ms opacity; stable interactive geometry |
| Exit | Immediate, no delayed invisible blockers |
| Feedback | Optional 8 ms Android haptic; notices expire after 2.2 seconds |
| Motion preference | Persisted, completes running transitions when enabled |

`ui_tokens.gd`, `ui_icons.gd`, `tactile_button.gd` and `item_icon.gd` centralise components. There are no blur shaders, screen texture reads or permanent animation loops. Icon textures are cached. Inventory rows rebuild only when actual item identities change, preserving scrolling and press ownership during live health/condition refreshes. HUD data refresh is limited to 10 Hz; expanded settlement summaries to 1 Hz.

The canvas uses a square 400-unit reference with aspect expansion, so the short edge stays at 400 in either orientation. A portrait reference would shrink landscape targets. On a 1080px P30 short edge a 48-unit target is about 130 physical pixels. Native safe-area pixels are converted through the inverse viewport screen transform. All active surfaces fit the resulting safe rectangle; settings and inventory scroll on short screens.

## Input ownership

`unified_game.gd` owns world gestures. Any finger beginning over the visible UI belongs to UI for its lifetime and never enters the world pinch map. Touching UI while a world gesture is active cancels that gesture until its fingers lift. Modal opening, tool changes, resizing, Android cancellation and focus loss clear pending strokes. The native GUI receives emulated mouse events; the world ignores those events to prevent duplicate powers.

An 8-unit movement threshold distinguishes a deliberate tap with finger jitter from painting/panning. Entering a panel interrupts the brush segment; re-entering the world cannot bridge across covered tiles. Two world fingers use the existing verified pinch anchor fix. Mouse drags and wheel zoom obey the same world hit rectangles.

## Inspection and files

`inventory_sheet.gd` presents the existing `item_inspector.gd` model. PACK/STORES, exact-serial selection, Take, Equip/Unequip, Drop, Deposit, Pick up and Queue repair retain model eligibility and conservation checks. Citizen age comes from the biological calendar; no legacy update counter is shown as years. Terrain inspection and status dates use actual runtime fields.

`world_files.gd` writes the unchanged JSON snapshot through an atomic temporary-file replacement with full float precision. Its read boundary restores exact integral JSON numbers and the two typed dictionary arrays required by current loaders. Fractional ledger counts remain invalid. This fixes loading the existing JSON format without changing the authoritative inventory or food/demography code. A reload is confirmed in the interface, validates a new world first, then replaces the renderer and clears transient inspection state. A failed reload leaves the current world intact; save success feedback follows the real I/O result.

## Integration contract

Future tools should be added only with an implemented controller action. Keep stable power IDs and extend `CATEGORIES`, `CATEGORY_POWERS`, tool labels/icons and controller signal handling together. Tool trays already scroll and use reusable cards; add labelled subgroup containers when a category outgrows a small grid. World-information content is supplied through `set_world_details`; future construction/economy inspectors should follow the native inventory-sheet presentation and leave decisions in their authoritative model.

No simulation, citizen AI, construction planning, resource logistics or inventory authority file was modified by this overhaul. `game.gd` changes in this branch are inherited from the existing pinch-fix branch, not new simulation work.
