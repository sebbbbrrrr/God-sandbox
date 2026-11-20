# God Sandbox D2 — Physical item custody, ownership and persistence

Branch: feature/items-physical-inventory-d2 (stacked on D1 PR #12).

## Implemented

- A deterministic authoritative custody ledger: scripts/items/physical_inventory.gd.
- Holders: citizen:<id> moves with its carrier (20 kg mass cap); settlement:<nation> is positioned at its capital; ground:<tile_index> stores recoverable drops at real terrain coordinates.
- Read-only inspections: citizen_inventory, settlement_inventory, ground_inventory, ownership and held.
- Atomic transfer of multi-item bundles with source ownership, local depot citizenship and physical proximity checks (Manhattan distance <= 1 at both endpoints).
- Environmental extraction can only create wood from actual finite forest cells and stone from actual finite mountain cells. The source depletion record changes on success.
- Consumption of verified carried materials, item drop on citizen death, and terrain-driven loss for ground drops when destroyed by ash or ocean.
- Bounded audit events alongside persistent minted, consumed and destroyed totals.
- Conservation equation for each catalogue item: extracted / imported = held across all stores + consumed + destroyed.

## Existing system integrations

- Construction workers gather resources into their citizen inventories, physically carry them to depots, retrieve house material bundles, and consume the carried supplies on actual completion.
- Construction.stockpiles is a compatibility alias of the same physical settlement item dictionary, with zero-value wood and stone keys supported for historical tests.
- JSON snapshot and binary SaveStore include inventory snapshot. The existing v4 world envelope remains stable; inventory itself declares version 1.
- Older world saves without inventory migrate existing legacy settlement stock and in-transit construction job cargo once as opening balances. Historical consumed materials in destroyed houses are not fabricated as new inventory.
- A malformed but present inventory section is rejected rather than silently falling back to a second mint path.
- Food Survival B1 continues to own its established physical depots, household pantries and production/consumption ledger. Food is not duplicated in the new ledger.

## Explicit limits

- D2 provides authoritative state and construction hauling, not visible inventory UI, ground pickup rendering, consumer-facing item management, item equipment or autonomous catalogue tool manufacturing.
- Recipient consent, theft, trading and multi-nation diplomacy are follow-up social AI work.
- Ground drops are tile-indexed and presently exist as simulation records, not sprites.
- Limits: <=2000 custody stores, <=1,000,000 units per stack, 20 kg per ordinary citizen, 96 audit events. These are provisional safety budgets.
- D1 item definitions and ability prerequisites are retained without unlocking new professions or technology.

## Validation

Dedicated branch CI: .github/workflows/physical-inventory-validation.yml (Godot 4.5.2 headless import plus tests).
Required test files: item_catalogue_test.gd, physical_inventory_test.gd, construction_test.gd, food_survival_test.gd, era_occupations_test.gd, simulation_test.gd and civilisation_calendar_lifecycle_test.gd.

D2 regressions cover finite extraction, remote-action rejection, ownership, atomic bundles, death drops and recovery, conservation, corruption rejection, JSON/binary save round trips, and old-save migration.

Do not merge the D1 or D2 draft pull requests without explicit approval after validation.
