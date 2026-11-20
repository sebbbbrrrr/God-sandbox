# God Sandbox — Civilisation Evolution Phase B2
## Autonomous households, reproduction and survival adaptation

**Stacked branch:** `feature/civilisation-autonomous-population-b2` (base: `feature/civilisation-food-survival-b1`, draft PR #9). It inherits draft PRs #8, #7 and #6. **Do not treat this as merged or Android-tested.**

### What this phase actually implements

**1. Autonomous partnership and family formation**
- Existing real citizen AI relationships are consulted through `relationships.gd`; both adults must have mutually positive, observed trust and affinity and be physically near one another.
- Eligible adults can form households through the previously implemented `households.form_household` operation. Partners are tracked by persistent stable citizen IDs; no random national mass-coupling or invented marriages.
- Existing known parent-child or sibling relationships block close-kin partnership selection.
- Personal interest and explicit local household social-adulthood preferences influence choice. Biological adulthood (18+) is separate from optional later social-adulthood norms (18–30). **No ethnicity, nation, historical age label or religion imposes a default family preference.**

**2. Gestation, births, safety and historical parentage**
- A deterministic `can_gestate` flag provides a simple reproductive-role abstraction, independent of gender labels, culture, nationality and personality. This is not a detailed real-world sex or fertility model.
- An eligible adult with gestational capability (18–44 in this game model), a living partner, good health, low hunger and a shared household with a genuinely vacant completed-house bed can begin pregnancy only after sufficient local pantry reserves and stable observed food security.
- A pregnancy lasts **1,800 ticks** under the existing 2,400-tick/year calendar, approximately 225 of the game's 300-day year.
- A due adult travels **physically** to an assigned safe home (the existing bounded movement system) before giving birth; the newborn is created only when actual shelter, a bed and local food exist. Pregnancy is tracked across saves and may be delayed or end following prolonged severe deprivation; it never generates a baby purely because a timer expires.
- Death of the non-gestational partner does not retroactively erase the conception. The surviving parent can give birth, and both biological parent IDs remain in the child's recorded ancestry.
- Pregnancy, birth, bereavement and family-formation events are real simulation history records; birth counts and last-birth times are saved, with an initial two-year minimum spacing and an optional household preference for longer spacing or no children.
- Manual/internal births use the same lifetime household birth ledger. This phase deliberately does **not** implement sex categories, genetics, detailed reproductive health, contraception, pregnancy healthcare or household law.

**3. Responsive food survival and household logistics**
- Extends Phase B1's biome-season food production and real depot-to-house transport with a **dynamic household reserve target** that scales by living household members and reserves extra supplies during autumn/winter.
- Under low national food reserves, severely hungry non-specialist adults may join the emergency foraging workforce instead of waiting for a predetermined occupational role. There are at most 12 active food gatherers per nation.
- Pregnancy adds an additional food requirement to actual citizen hunger. Adults who cannot safely give birth can continue obtaining food rather than being stuck in a delivery-only state.
- Expensive food-source discovery is staggered and its per-citizen cooldown persists in saves. Idle scan records are pruned when citizens die.
- The existing food-conservation invariant remains: *actual edible harvest = stored supplies + consumed rations + seeds planted + cargo lost*. No food is fabricated as a reward for choosing reproduction.

**4. Time, location, belief, culture and economics**
- **Time:** biological ages, real gestation duration, seasonal reserve planning, mortality and birth spacing all use the fixed authoritative calendar. No universal birth/technology unlock in a specific historical era.
- **Location:** housing scarcity, locally accessible food, terrain and weather/season constraints influence actual family prospects. Same calendar year can produce different demographic outcomes in distinct settlements.
- **Culture and religion:** household-specific opt-in `set_household_preferences` accepts `desired_children` (0–4), `minimum_spacing_years` (1–8), `partnership_interest` (0–100) and `social_adulthood_age` (18–30). If two adults have different explicit choices, their shared family respects the smaller desired-child target and the longer spacing request. This supports future culture/religion institutions, but **does not simulate religion or derive behavioural preferences from faith, ancestry or nation**.
- **Knowledge and economy:** real physical stockpiles and adopted farming capability from Phase B1 determine food availability. Skill acquisition, technological discovery, trade, social institutions and autonomously evolving belief systems are planned separate slices.

**5. Generational continuity and bounded performance**
- The active simulation still caps at 1,500 citizen entries. Dead citizens are retained for at least two simulation years, then archived into bounded tombstones (up to 1,000) with stable ID, parents, birth/death ticks and cause. A separate cumulative archived-death counter persists, as do the bounded lifecycle event journals. No ID is reused.
- At the exact archival tick, household membership and dangling citizen relationship references are reconciled before saving; long-run population turnover should no longer become permanently blocked by dead renderer records.
- Partnership planning runs every 180 ticks using the existing local spatial-neighbour and bounded relationship caches, not all-pairs matching each frame. Pregnancy health monitoring runs every 120 ticks; archival cleanup runs at annual boundaries.
- No AI or technological era requires external AI models or network calls. No renderer, HUD, Android workflow, sprites, physics or main branch are changed.

### Tests written — not executed

The new `tests/autonomous_demography_test.gd` checks independently seeded households, observed social ties, cultural social norms, non-partnering of close kin, voluntary preferences, real resource limits, conception events, non-instant pregnancies, due delivery through actual AI scheduling, gestational food scarcity, bereavement, preserved parentage, population-slot archives and both JSON and binary save continuity.

Previous tests should continue to run; validation requires Godot 4.5.2:
```bash
godot --headless --path . --script res://tests/autonomous_demography_test.gd
godot --headless --path . --script res://tests/food_survival_test.gd
godot --headless --path . --script res://tests/household_care_test.gd
godot --headless --path . --script res://tests/civilisation_calendar_lifecycle_test.gd
godot --headless --path . --script res://tests/construction_test.gd
godot --headless --path . --script res://tests/citizen_ai_test.gd
godot --headless --path . --script res://tests/simulation_test.gd
```

**Not yet verified:** Godot parser/compiler, Android APK, 160/500/1500-person long-duration soak, battery draw on Huawei P30, actual pregnancy and family-life animations, compatibility with active pixel-art/HUD/walking PRs. Stacked PR must stay draft and unmerged pending these gates.

### Subsequent phases

**B3:** real food emergency migration along known paths, child-carrying fidelity and food relief institutions; meaningful household economy/care workload, shelter allocation and famine adaptation.

**C:** individual occupational skills, practiced expertise, apprenticeships and skills carried across generations; social and cultural traditions spread and change through observation, interaction and institutions.

**D onward:** verified experiments, individually owned knowledge, recorded inventors, education and technology transfer; town production chains, era capabilities and distinct visual development paths through the far future.
