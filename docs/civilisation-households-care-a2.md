# God Sandbox — Civilisation Evolution Phase A2
## Households, physical occupancy, guardianship and caregiving

**Branch:** `feature/civilisation-households-care`  
**Stacked on:** `feature/civilisation-calendar-lifecycle` (PR #7), which itself builds on the physical construction prototype (PR #6).  
**Blueprint:** `God_Sandbox_Civilisation_Evolution_Master_Design.pdf`.

### Implemented gameplay rules

1. **Stable household entities.** Each living founder begins in a separate household with a stable integer ID, nation, member list, current home ID, steward ID and founding tick. Citizens also store `household_id`, `home_id`, `guardian_id`, `carried_by`, `last_care_tick` and `care_visits`. A bounded, derived ID index avoids scanning the entire household list for each citizen AI update.
2. **Household formation.** The `form_household(world, citizen_a, citizen_b)` API lets two nearby living adults join households, preserving existing members and choosing a home only if there are enough actual beds. Existing co-residents are not double-counted. Formation is a validated operation; **romance, marriage and autonomous partnership proposals have not been implemented**.
3. **Physical housing occupancy.** A completed `construction.houses` record supplies actual bed capacity; town terrain alone is never housing. Families are assigned to nearby valid homes on a 60-tick cadence or after a change, in deterministic proximity/ID order, without splitting families. Multiple small households may share one house within capacity. Destruction or terrain invalidation releases resident claims rather than generating replacement housing.
4. **Care and infant carrying.** A designated adult guardian performs periodic childcare visits (36 ticks) as an actual activity before ordinary construction/gathering work. When an infant is separated from its assigned home, the guardian approaches using existing bounded pathfinding, picks up from the same or neighbouring cell, carries one tile at a time and sets down at a safe home. No long-range teleportation or free infant walking is introduced. Infants are still too young for jobs; older dependents follow their assigned guardian rather than needing a biological parent to remain alive. Care is a first-stage visit/carry model, **not yet a complete feeding, health or daily dependency simulation**.
5. **Birth eligibility.** The existing manual/internal `register_birth` API now requires two eligible living cohabiting adult parents, a completed nearby house assigned to their household and at least one genuinely vacant bed. A newborn joins the existing household, uses a bed and records its two biological parent IDs plus a living guardian. **No automatic pregnancy or birth scheduling** exists until food/nutrition/care is implemented.
6. **Death and succession.** When the steward dies, a living adult from the same household assumes stewardship. If a dependent loses their guardian and no eligible adult remains, a nearby existing household with a living adult and free bed can take them in. That creates a guardianship event but preserves biological ancestry. These are *custodial stewardship and care*, not yet laws of private property inheritance, inheritance of national resources or adoption consent/legal processes.
7. **Save and migration.** `households` is now part of the existing JSON and binary world snapshots. Old saves without household data deterministically generate individual founding households; they never reinterpret old age counters. A `dirty` reconciliation flag is preserved to avoid save/reload changes between two authoritative ticks. In-the-moment saves after death but before household reconciliation must remain readable.
8. **Compatibility.** The six existing God powers remain present. Bless restores health to living citizens; it does not silently resurrect a citizen after their historical death has been recorded. A dedicated resurrection mechanic, if desired, requires its own explicit life/household restoration rules. The existing construction, AI, save versions and rendering interfaces are otherwise left intact.

### Deliberate limitations and safety gates

- **Not yet:** autonomous family formation, co-parent preference/compatibility or conflict, food, childcare nutrition, work-time balancing, property title, adoption institutions, migration/household relocation planning, distinct housing sprites and individual furniture.
- No new graphics changes, UI interactions, assets, physics, build workflow or Android package are introduced on this branch.
- In scarce housing conditions, unassigned residents remain homeless; babies cannot appear in fully occupied homes. Orphans without an available adult and an extra bed remain in the simulation as dependents requiring support, rather than being deleted or assigned an imaginary caregiver.
- Citizen and household caps remain 1,500; active caregiver and home searches operate on stable local relationships and bounded existing lists. Actual Huawei P30 performance must be measured once Godot tests and branch integration are complete.
- The new `households.gd` is a CPU-side simulation module only. The graphics branch may later draw occupant badges, family links, caregivers carrying babies and house occupancy.
- Do not merge this draft PR, PR #7 or PR #6 into main or graphics branches until all staged build/test/Android gates succeed.

### Validation commands

```sh
godot --headless --path . --script res://tests/household_care_test.gd
godot --headless --path . --script res://tests/civilisation_calendar_lifecycle_test.gd
godot --headless --path . --script res://tests/construction_test.gd
godot --headless --path . --script res://tests/citizen_ai_test.gd
godot --headless --path . --script res://tests/simulation_test.gd
```

The new test fixtures exercise founder IDs, household joining, real occupancy, birth capacity, childcare visits and carrying, orphan guardianship, stewardship succession, catastrophic housing loss, co-resident merges, JSON/binary save continuity, determinism, and legacy migration. The scripts have **not** been executed in a real Godot runtime in this session.

### Next phase: food, survival and generational livelihoods

Implement finite edible resources, physical harvesting and transport, family stockpiles/food consumption, need-sensitive labour decisions, food shortages and caregiving needs. After those mechanics are verified, introduce bounded autonomous reproductive decisions, consistent household capacity, parental readiness, inherited knowledge and stable historical chronicles.

The eleven civilisation eras and advanced technological development remain the approved master **design**, not already running gameplay mechanics.
