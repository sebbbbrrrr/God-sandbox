# God Sandbox — Item & Ability Catalogue D1 (foundation implementation)

> Status: first data/runtime slice; **not a new in-game crafting UI or autonomous craft job**.
> Branch: `feature/items-abilities-foundation-d1` based on `feature/civilisation-era-occupations-c1`.
> No renderer, input code, Android workflow, or existing snapshot schema modified.

## Long-range catalogue contract

- Target: 2,200 item definitions across 16 categories and 410 citizen abilities across 8 domains.
- Development waves: 100 items/35 abilities, then 175/45, 225/55, 200/50, and 1,500/225.
- Every definition has a stable ID. An instance can have independent owner, quality, condition, modifications and provenance.
- Never infer a technological capability from calendar time or a global era label. Local knowledge, facilities, materials, actual practise, transport and real work events determine use.
- Biome metadata is an acquisition requirement, not a shortcut to conjure resources. No invented ores, woodland, fish or building output.
- An imported finished tool does not grant a manufacturing process.
- Lost workshops, mines or know-how must make production unavailable while preserving surviving objects and personal history.
- Religion, ethnicity, nationality or gender must not apply essentialist ability multipliers. Beliefs and traditions can shape demand and use without deciding universal aptitude.
- All production and consumption must be authoritative, bounded, deterministic and saveable. Renderers never control item ownership, stock or crafting.

## Existing 11-era alignment

The current era-occupation branch uses these **first appearances** (not unlock years):
1. Early Stone Age
2. Agricultural Age
3. Bronze Age
4. Iron & Classical Age
5. Medieval Engineering
6. Early Scientific
7. Industrial
8. Electrical & Modern
9. Information
10. Advanced Technological
11. Far Future

This is the current implementation's era taxonomy. It remains compatible with the broader proposed prehistoric-through-post-singularity vision. Region-specific divergence is always permitted.

## Delivered this slice

- `data/catalogue/foundation_items.json`: exactly 100 stable items spanning resources, material transformations, tools, weapons, clothing, food, medicine, structures, household goods, culture, transport and research.
- `data/catalogue/foundation_abilities.json`: exactly 35 abilities spanning survival, craft, intellect, society, combat, agriculture and medicine.
- `scripts/items/item_catalogue.gd`: read-only catalogue lookup; cross-reference validation; prerequisite checks; an atomic caller-supplied inventory craft operation; per-item instance creation; live-citizen context adapter for occupations, adopted local technology and completed facilities.
- `tests/item_catalogue_test.gd`: loading and referential integrity, ingredient conservation, atomic failure, technology/facility gates, batch quantity, age gates, unavailable abilities and instance state.

### Deliberate boundaries

The existing world currently has **separate** construction stockpiles (`wood`, `stone`) and food depots (`berries`, `fish`, `grain`). They are not converted to catalogue inventories here: duplicating these would break physical resource conservation and save compatibility. The JSON's `raw_fish` is a future catalogue mapping, not an extra pile of fish. Recipes currently operate only on an explicitly owned inventory dictionary supplied by a real simulation work event.

The role `stone_toolmaker` and specialised `kiln`, `forge`, `smelter` and other facilities are currently **catalogued but disabled** in C1 until physically implemented. `context_for_citizen()` intentionally returns a closed gate when a role/facility is not operational. Crafting transaction support does **not** imply autonomous citizens already know how to perform those jobs.

Ability `implemented` flags represent staged availability for checks; `can_use_ability()` returns eligibility and never performs action effects. Existing food/woodcutting/building/teaching work loops have not yet been altered to require equipment. Thus the first set is a foundation, **not** a claim that the player can equip or observe these items in-game.

The initial physical numbers (mass, hardness, flammability, durability) are placeholders for balancing and materials science work; destruction simulation is not yet wired to them. Item `first_era` is a historical earliest plausible appearance; production checks ignore this field.

## Example action flow to connect next

1. A woodcutter physically extracts `wood` from a finite source. Existing simulation still owns the extraction ledger.
2. At an actual depot, a delivery event transfers a precise quantity from that ledger into one inventory: subtract first, then deposit to the catalogue inventory. Never credit both stocks.
3. A citizen and workstation are identified; build a context using `context_for_citizen(world, person, item_id)`.
4. Validate profession/skill, technology, facility and inventory with `can_craft`.
5. Spend bounded work time and consume inputs once, then call `craft` for actual output; record item owner, quality, origin and usage.
6. Credit occupational XP from that finished work event only.
7. Persist inventory, outstanding jobs and unique item instances. Deterministic continuation after save/load must pass regression tests.

## Follow-on engineering order

1. **D2 inventory custody and ledger:** finite inventories for person/home/worksite/settlement, capacity/weight, physical pickup/transfer/delivery, no double counting, bounded save schema.
2. **D3 first true craft loop:** gatherer -> actual toolmaker workstation -> craft stone axe/knife -> equip -> tool efficiency, wear, repair and recycling.
3. **D4 food/medicine/equipment:** physical storage, cooking, clothing durability, healing, age/skill checks; preserve household customs.
4. **D5 manufacturing and economy:** settlement-local knowledge, actual facilities, metallurgy, regional trade, apprenticeship, migration, prices and degradation.
5. **D6 invention:** evidence-linked prototype attempts, experimentation costs, failures, incremental upgrades, invention transmission and loss.
6. **D7 later generations:** progressively add mechanical, modern and far-future categories only after prerequisite infrastructure/jobs and corresponding simulation work exist.

## Verification

Run using Godot 4.5.2:

```sh
godot --headless --path . --script res://tests/item_catalogue_test.gd
godot --headless --path . --script res://tests/era_occupations_test.gd
godot --headless --path . --script res://tests/construction_test.gd
```

No on-device verification is claimed for D1. Before merging, run all existing AI/simulation tests plus Android build and Huawei P30 testing. No automated Actions workflow was dispatched by this task.
