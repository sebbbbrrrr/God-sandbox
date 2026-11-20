# God Sandbox — Civilisation Evolution Phase B1
## Food, farming, survival and context-sensitive practices

**Branch:** `feature/civilisation-food-survival-b1`  
**Stacked on:** `feature/civilisation-households-care` (draft PR #8), itself after lifecycle PR #7 and physical housing PR #6.  
**Master reference:** `God_Sandbox_Civilisation_Evolution_Master_Design.pdf` (20 November 2026).

### Implemented in code

- **Physical food economy**: three initial food categories (berries, fish, grain). Local FOREST supplies berries, MEADOW supplies wild grain, and BEACH adjacent to a real in-bounds OCEAN tile supports fishing.
- **Geography and climate**: eligible sources vary by actual terrain and relative latitude. Colder-edge regions support reduced seasonal foraging. Farms on colder tiles produce less; nearby coastal water improves potential crop yields. Irrigation only provides a boost where real water is within three cells.
- **Calendar and seasons**: natural seasonal harvesting stocks are capped and refresh by season (600 ticks). Berries and wild grain do not produce in winter, whereas coast fishing may remain productive. Winter prevents new crop sowing and harvesting. Growth requires elapsed simulation ticks.
- **Materially gated agriculture**: a settlement without knowledge of cultivation does not farm merely because time has elapsed. Explicit `set_technique(nation, "cultivation")` adoption is provided for later research/teaching integration. Farming consumes **one existing grain seed** and needs a meadow plot. Crops grow over 240 simulation ticks and only yield food when a worker reaches and actually harvests the plot. The plot must be resown and has finite fertility/recovery. Irrigation adoption is separately gated.
- **Physical work and logistics**: bounded gatherers travel from the depot, harvest local finite resource packets and carry them back. Households may send a worker to collect food from a nation depot and physically deliver it to the assigned real house. Actual per-citizen hunger motivates travelling for an available meal. A death in transit records lost cargo rather than teleporting it into storage.
- **Households and consumption**: a ration must be physically available at a nearby home or nation depot. Eating reduces a real citizen's hunger and consumes one stored unit. Dependent minors can eat when a real guardian is nearby. Progressive sustained shortages reduce health and can cause a recorded starvation death. In the initial model, a ration covers a 120-tick hunger interval, a game abstraction rather than a real nutrition claim.
- **Religion and culture as explicit practices**: households can store a chosen `tradition_id`, food preferences, abstentions, adult fasting days and observance strength using `set_customs`. Practices are *not* assigned from nation, genetics, ethnicity, historical era, or any supposed intrinsic character trait. Children are exempt from optional adult fasts; urgent survival overrides practices. This is a cultural/religious **integration hook**, **not yet** an autonomous religious or belief transmission system.
- **Conservation and saves**: food production, actual consumption, planting seed inputs, dead-carrier loss, depots, family pantries, in-transit cargo, wild seasonal extraction and farms are persisted in JSON and atomic binary saves. An explicit per-food ledger validates produced = holdings + eaten + planted + lost. Existing save formats missing food state create no imaginary food; new citizen hunger fields default safely.

### Important intentional limitations

- **No global historical era unlocks**. Adoption comes from explicit techniques. Autonomous scientific discovery, migration-driven sharing, farming knowledge transmission, architecture and future eras will be separate milestones.
- **No predefined real-world religion or culture stereotypes.** Culture and religion are allowed to affect food behaviour only when simulated by future institutions/individual beliefs or deliberately supplied. Existing practices can be changed, and biological calorie needs are not determined by religious identity.
- **No automatic conception/births yet.** Manual/internal birth registration is now gated by real household pantry reserves and both parents' hunger in addition to two living adult parents, a shared household and a vacant real bed. Next phase: conception and births triggered by autonomous household decisions once family food stability, parental capacity and caregiving tests are verified.
- **Food is currently represented in coarse consumable ration units**, not detailed calories, diseases, cooking recipes, livestock, fisheries, nutrition deficiencies or market prices. Terrain biomass naturally replenishes at defined seasonal boundaries; no farming or fishing infrastructure is depicted by the current renderer.
- The current world has **one local capital per nation**. Future technology and culture integration should move settlement-level knowledge from these two prototypes to proper settlement entities instead of assigning every member of a nation identical technology.
- **Caregiver transport is inherited from PR #8** and remains prioritised ahead of food work for guardians. No full feeding animation, infant carrying art, cooking or farming sprites exist yet.

### Suggested validation

```sh
godot --headless --path . --script res://tests/food_survival_test.gd
godot --headless --path . --script res://tests/household_care_test.gd
godot --headless --path . --script res://tests/civilisation_calendar_lifecycle_test.gd
godot --headless --path . --script res://tests/construction_test.gd
godot --headless --path . --script res://tests/citizen_ai_test.gd
godot --headless --path . --script res://tests/simulation_test.gd
```

New regression fixture covers different biomes, cold/warm seasonal access, household voluntary dietary practice, shortage override, actual gathering/pathing and farm harvesting, ledger conservation, hunger and fatal starvation, JSON/binary save continuation, legacy migration and deterministic seeded replay. **Runtime execution is pending**.

### Future expansion aligned to master PDF

1. **Phase B2** — balance food and survival on 160/500/1,500 citizens; genuine caregiver-dependent feeding, household reserves/consumption forecasts, famine migration, food transport constraints and occupation scheduling; activate cautious autonomous reproduction only after adequate food and capacity.
2. **Phase C** — farmer/forager/fisher skills, specialty jobs, apprenticeship and intergenerational knowledge transmission. Different households choose, learn, modify and share traditions through real encounters and institutions.
3. **Phase D** — experimentation/innovation, individual inventor records, local technique adoption and cultural/religious evolution through actual social events, not instant national/global switches.
4. **Later** — regional climates/rivers/soil/water dynamics, production buildings and trade routes, era-specific agriculture, architecture, governance and alternative far-future paths.

**Merge gate:** This is a stacked development branch. Keep all PRs unmerged until Godot 4.5.2 parser and headless tests, save/restore tests, integrated graphics review and Huawei P30 battery/memory/performance validations pass. No workflow or renderer files changed.
