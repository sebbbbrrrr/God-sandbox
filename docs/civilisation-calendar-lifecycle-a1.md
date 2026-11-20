# God Sandbox — Civilisation Evolution Phase A1: Calendar and biological lifecycle

**Branch:** `feature/civilisation-calendar-lifecycle`
**Base:** `feature/citizen-material-construction` (draft PR #6)
**Reference:** `God_Sandbox_Civilisation_Evolution_Master_Design.pdf` (v1.0, 20 November 2026)

## Delivered in this vertical slice

- Deterministic fixed-tick simulation calendar: **8 ticks/day, 300 days/year, 2,400 ticks/year**, four 75-day seasons. These are **provisional gameplay tuning constants**, not real-world historical accuracy.
- Separate `birth_tick` from the existing legacy `age` update counter, which remains untouched for renderer/old-save compatibility.
- Canonical age calculation `floor((world.tick - citizen.birth_tick) / 2400)`. Staggered seeded founder birthdays establish an initial adult population without consuming world RNG or treating previous update counts as years.
- Five life stages: infant (0–2), child (3–12), adolescent (13–17), adult (18–59) and elder (60+). Stage transitions are emitted on their **exact authoritative birthday tick**; cognition may still be scheduled at lower frequency.
- Infants, children and adolescents cannot perform the current material-gathering or housebuilding jobs. Infants do not travel alone; dependent children can follow a known living parent through bounded walking navigation, where applicable. Full caregiving and household assignment remain future work.
- Tunable annual old-age mortality with deterministic checks, plus death events for fatal fire/injury. A bounded 192-event journal records actual births, deaths and life-stage transitions.
- An **internal** `register_birth` API validates two living adult parents nearby and unoccupied built housing capacity. This is deliberately **not** an autonomous reproduction loop: food, pregnancy/care, households and safe population turnover are pending.
- Compatible v1–v4 JSON snapshot restoration; missing birth metadata migrates into a deterministic founding adult age rather than treating the legacy `age` counter as years. Calendar and lifecycle state are optional new v4 snapshot fields.
- **Binary save bug fixed:** the prior construction prototype's `SaveStore.prepare()` accidentally omitted construction data. Binary saves now retain construction, calendar and lifecycle, with a new save regression test.
- Existing god powers, terrain/renderer interfaces, autonomous adult AI and construction material jobs are preserved within this branch.

## Performance and safety

- All authoritative time calculations are integer-only and independent of real-world time and camera/renderer state.
- Life-stage event checks scan citizens once per simulation tick, comparing birthday offsets with a modulo operation; old-age mortality runs at yearly boundaries.
- Life events have monotonic sequence IDs with a capped history. Founder age uses a deterministic seed/ID function, independent of terrain/spawn RNG.
- Do not merge without verifying the local implementation and inherited construction PR #6, all previous regression tests, save consistency, compile/import, and Huawei P30 performance.
- No Godot runtime was available in the authoring environment; **tests are written, not executed**.

## Test commands

```sh
godot --headless --path . --script res://tests/civilisation_calendar_lifecycle_test.gd
godot --headless --path . --script res://tests/construction_test.gd
godot --headless --path . --script res://tests/citizen_ai_test.gd
godot --headless --path . --script res://tests/simulation_test.gd
```

## Explicit next milestones

1. **Phase A2:** persistent household IDs, actual housing occupancy and infant carrying/childcare; parentage and adoption, tombstones and safe dead-citizen cleanup.
2. **Phase B:** physical food sources, harvest/transport/consumption and survival pressure. Only after this should an autonomous pregnancy/birth decision system be enabled, tied to real nutrition and caregivers.
3. **Phase C:** learnable skills and apprenticeships, including generational knowledge transfer and technology loss.
4. **Phase D:** data-driven technologies and validated experiments, recorded discoverer, local diffusion and facility-gated adoption.
5. **Later:** era classifications, architecture, energy, industrialisation, multiple civilisation development paths and far-future branches.

The eleven eras in the master blueprint remain a **design specification**, not gameplay already present in the game.
