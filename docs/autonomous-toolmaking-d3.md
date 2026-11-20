# God Sandbox Phase D3 — autonomous toolmaking, equipment and repair

**Branch:** `feature/autonomous-toolmaking-d3` (stacked on D2 PR #13 and D1 PR #12).
**Godot:** 4.5.2 / GDScript. **Platform:** Android-first, GL Compatibility.

## Verified gameplay loop

1. Adult or adolescent-capable citizens are allocated to a bounded toolmaking job per settlement. The task's real state persists across saves and cannot continue while the citizen is dead.
2. The artisan walks to finite forest/mountain cells; extracts physically conserved wood, stone, flint or plant fibre into their individual inventory; hauls the cargo to their nation's real capital; and deposits it in the settlement ledger. Wood and fibre share a forest cell's depletion capacity. Stone and flint share a mountain cell's capacity.
3. The artisan physically constructs a **tool area** using two wood and one stone through a multi-step job. It is a typed, zero-housing-capacity building inside the existing construction structures; the renderer still renders a town tile and does **not** yet have unique tool-yard art. The building must exist before this profession becomes usable.
4. Knowledge remains locked until a real experiment at the built area consumes one flint and one stone to generate a knapped-flint prototype. Only then is `stone_working` locally adopted via `occupations.grant_capability(..., "experiment")`. Time passage and nominal era do not unlock it.
5. The artisan automatically plans a dependency chain from the D1 recipes. On completion, workshop crafting consumes the actual stored materials, generates a bounded physical product, records the transformation in the D2 conservation ledger and gives occupation XP only on real work events.
6. First outputs: hammerstone, knapped flint, cordage, stone axe, stone pick and flint knife. Knapping requires a functioning hammerstone physically present in the settlement's tool area, checks the D1 ability gate and wears the hammerstone.
7. Every durable tool has a unique serial, holder, quality, maximum condition, current condition, origin and bounded history. The item stack quantity and unique tool serials must agree for each holder. Moving, dropping or destroying an item also moves or removes the matching serial.
8. Construction gatherers physically check out stone axes or stone picks from the nearby settlement before travelling to collect wood or stone. Only a valid possessed, usable, equipped tool with the matching D1 ability gate gives a **2-unit extraction action** instead of barehanded **1-unit extraction**. Its condition decreases on successful use. At zero condition it becomes unusable; the citizen retains the item until it is returned to a depot.
9. A worn tool can be put back in the settlement. An eligible local artisan repairs it using **one real unit** of the corresponding raw material at the tool area. Repair raises condition but never mints a new item or duplicates its serial.

## Architecture

- `scripts/items/autonomous_toolmaking.gd` owns work jobs, unique tool instances, equipped slots, physical craft planning and repair actions.
- `scripts/items/physical_inventory.gd` remains the authoritative quantity ledger and validates and commits every transfer, extraction, recipe and repair material debit.
- `scripts/ai/citizen_ai.gd` schedules real toolmaker actions after critical needs/care/food and before ordinary construction tasks. Existing construction jobs are never overwritten.
- `scripts/ai/construction_economy.gd` supports finite flint/fibre, shared biome depletion, non-residential tool areas and tool-enabled work.
- `scripts/ai/era_occupations.gd` marks stone toolmaker playable only when its actual technology and worksite exist.
- `data/catalogue/foundation_abilities.json` marks knapping implemented because its real action and tool-gate now exist.
- `scripts/simulation.gd` and `scripts/ai/save_store.gd` store and restore D3 state alongside D2 inventories, occupation XP and existing food/household/construction state. Old D1/D2 world snapshots with no D3 section load with empty D3 state.
- No additional item/world graphics, monetisation, multiplayer or production machines are introduced.

## Conservation and integrity

For every item ID, the D2 invariant remains:

```
extracted + manufactured + migrated = held + consumed_in_recipes + consumed_in_building_or_repair + destroyed
```

Crafting does not convert one item ID to another by changing an untracked counter; it explicitly logs the input debit and output credit. Failed transactions reject the entire operation. Workshops, capabilities and item serials cannot be reconstructed for free from a corrupt save.

## Bounded mobile cost

- At most one concurrent autonomous artisan job per settlement, with no global per-tick ingredient sweeps.
- Maximum 20 outstanding artisan job entries, 500 unique durable tool instances, 10 per-tool history events.
- Existing citizen update staggering, moving pathfinder and bounded item ledger remain unchanged.
- Tool world state is simulation data; no per-item Node2D is spawned.

## Tests

`tests/toolmaking_test.gd` verifies construction costs, worksite requirement, real research, physical product chains, unique serial custody, failed duplicate withdrawal, **actual two-unit woodcutting and wear**, broken-item gating, material-paid repair, JSON/binary save round-trips, impossible bronze gating and corrupt save rejection.

`tests/toolmaking_autonomy_test.gd` runs **two deterministic 1,400-tick worlds** with no manually seeded tools or capability. Both construct the tool area and discover stoneworking, autonomously craft a hammerstone, stone axe, stone pick and flint knife, retain both the D2 inventory and separate B1 food conservation, and resume identically after a save.

The Godot 4.5.2 import and all **nine headless suites** passed in [Actions run 44771976472](https://github.com/sebbbbrrrr/God-sandbox/actions/runs/44771976472).

## Deliberate next-stage work

D3 does not provide visible handheld equipment sprites, tool-yard-specific art, a citizen inventory screen, citizen-to-citizen tool gifting consent AI, tool theft, combat weapon use, leather/bone extraction, generalised commercial workshops, fully procedural invention combinations, or full profession balancing across the 11 eras. Those belong in later features.

**Do not merge** until approval; Android APK export and Huawei P30 device validation remain outstanding.
