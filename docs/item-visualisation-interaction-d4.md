# God Sandbox — Phase D4: Item visualisation and interaction

Branch `feature/item-visualisation-interaction-d4` is based directly on D3 branch `feature/autonomous-toolmaking-d3` (draft PR #14). Godot 4.5.2, GL Compatibility, Android first. No runtime internet requests or third-party art.

## In-game visual changes

- `scripts/ui/item_pixel_art.gd` provides original tiny pixel motifs for wood, stone, flint, plant fibre, cordage, knapped flint, hammerstones, flint knives, stone axes and stone picks. Unsupported catalogue items use a neutral fallback motif. Artwork is painted through `CanvasItem.draw_rect`, retaining the renderer's small-pixel aesthetic and top-left highlight.
- Real `type=tool_area` facilities get a contrasting workshop roof, timber framing, anvil/hearth shape and a very small deterministic glow tied to simulation tick. Buildings are never fabricated for display; the renderer reads the `construction.houses` records.
- Nonempty `ground:<tile>` item stores get a cullable pixel-art item marker rather than an invisible ledger entry. Repaints use existing terrain placement and item custody; no independent sprite registry is persisted.
- Citizens with a valid `toolmaking.equipped` serial show the correct miniature tool adjacent to their nation-coloured sprite above a zoom threshold; near-broken equipment receives a small amber/red wear mark.
- World overlays and item art are culled to the current viewport and fade out below legible zoom scales. No extra per-citizen nodes or draw-call-heavy texture imports.

## In-game UI and interaction

- New bottom-toolbar **ITEMS** shortcut switches to hand mode and opens the acting citizen's physical pack, or the nearest founded settlement's stockpile if no citizen is selected.
- Hand-mode taps on a citizen open their pack; repeated taps can cycle occupants of the same tile. Tapping an actual tool-area structure opens its workshop store. Tapping a dropped-item tile opens its ground cache. Tapping a capital opens settlement storage.
- The inspector displays the **real**, sorted and bounded physical item inventory; rows are windowed/scrollable, with item-specific pixel icons, item quantity or serial, condition/quality and cargo weight. Personal-pack and settlement-store tabs preserve the acting citizen.
- Mobile modal touch streams are consumed by the panel so swipes scroll inventory rows instead of moving the camera or triggering an equipped brush. A close button and outside-tap dismissal keep the existing WorldBox-like control mode.
- Actions are genuine physical transactions, not shortcuts around inventory integrity:
  - **EQUIP / UNEQUIP:** may act only on the selected living citizen's owned, nonbroken unique tool. Selecting a different serial replaces only the equipment slot, not any stack.
  - **DROP:** transfers one selected item (or one unit from a bulk stack) to the actor's actual tile; hazardous terrain is disallowed.
  - **DEPOSIT:** requires the actor within a tile of their own capital.
  - **TAKE:** checks local settlement membership and weight; transferring a tool uses its exact unique serial.
  - **PICK UP:** requires a selected living citizen standing beside a real drop, with actual carrying capacity.
  - **QUEUE REPAIR:** requires an eligible stone toolmaker, workshop, available repair resource and no conflicting work job. It queues a multistep D3 job and **does not** instantly improve durability.

## Consistency/security

- `PhysicalInventory.transfer` now optionally accepts `exact_serial`; `AutonomousToolmaking.can_move/move_instances` verifies exact source custody and quantity before any balance changes, retaining all older call patterns by default.
- Item inspector presentation is transient UI state and is **not** written into the simulation save. All item counts, equipped ownership, job progress, repair resource costs, unique item histories and persisted world state remain authoritative in D2/D3 modules.
- D4 never mints an item, moves a remote actor, teleports cargo, or invents a new workshop; it exposes existing world state.

## Validation

`.github/workflows/physical-inventory-validation.yml` runs headless Godot 4.5.2 import and the previous nine suites plus:

- `tests/item_inspector_test.gd`: exact serial item selection, transfer and custody, panel geometry, pixel icons, equip/unequip, ground recovery, delayed material-paid repair, ineligible command blocking, JSON and binary save round-trips, and conservation.
- `tests/game_item_ui_test.gd`: actual game canvas and input hit-test, one-finger hand mode inspection, panel dismiss without painting, ITEMS shortcut, ground drop selection, and preserved world brush behaviour. Uses a dedicated configured-canvas fallback for headless environments.

**All 11/11 Godot regression suites passed** on [workflow run #44777518154](https://github.com/sebbbbrrrr/God-sandbox/actions/runs/44777518154) at commit `1a69febd9c9a2031b891115f3cf3a647dfacd14c`. Subsequent changes remove only temporary diagnostic prints and add this documentation; final-commit status should be taken from the latest CI run.

## Scope boundaries

- Procedural pixel motifs are functional sprites/overlays; the wider high-definition environmental art overhaul is in a **different branch** and has not been merged into D4.
- No world-space drag-to-move items, multi-select inventory transfer, citizen-to-citizen consent UI, visible construction progress animation, storage buildings beyond the capital, autonomous item trade, equipment comparisons or gameplay recording has been added.
- Full Android export, real Huawei P30 FPS and interaction testing must be separately verified before merge or release.

**Branch is for a draft PR only; do not merge without explicit approval.**
