# GOD SANDBOX — PHASE C1: ERA-CONDITIONAL OCCUPATIONS & LIVED SKILLS
**Repository:** `sebbbbrrrr/God-sandbox`  
**Branch:** `feature/civilisation-era-occupations-c1`  
**Based on:** `feature/civilisation-autonomous-population-b2` (draft PR #10, itself stacked on food PR #9, households #8, lifecycle #7, construction #6)  
**Reference:** `God_Sandbox_Civilisation_Evolution_Master_Design.pdf` (20 November 2026).

## Locked design contract

**Eleven eras are descriptive, not global job-unlock calendars.** The first-era tag is when an occupation first becomes technologically plausible. A specific settlement can move ahead in metallurgy while another remains agricultural; a city may be technologically mixed; older occupations persist alongside new ones when useful. Loss of equipment, resources, facilities or practiced skills may disable jobs without rewriting history. Religion, language, ethnicity and nation are not immutable job multipliers or assigned stereotypes.

**Availability requires evidence:**
1. **Practical role implementation** — a profession must have actual work behaviour. Later-era occupations are catalogued for future releases but intentionally not spawned as simulation jobs yet.
2. **Locally adopted technical capability** — e.g., cultivation for farming, computing for software engineering, steam technology for industrial operators. Capability is tracked against the currently represented capital/settlement key. The existing food module's cultivation/irrigation bridge is reused.
3. **Physical infrastructure** — e.g., actual farms, homes, kilns, forges, laboratories, factories or spaceports. Terrain `TOWN` does not automatically count as a factory or workshop.
4. **Regional opportunity** — coast, forests, nearby mountains, productive fields, dependents, water and work projects.
5. **Living candidate and relevant skill** — people have individually retained experience, aptitude/interest and other genuine responsibilities; different citizens in the same settlement can perform different work.

## Full occupation catalogue (66 curated first-appearances)

| Era | First-appearance occupations |
| --- | --- |
| **I — Early Stone Age** | Forager, fisher, woodcutter, quarry worker, shelter builder, caregiver, food courier, oral mentor, hunter, stone-toolmaker, ceremonial facilitator |
| **II — Agricultural Age** | Crop farmer, herder, potter, basket weaver, irrigation keeper, granary keeper |
| **III — Bronze Age** | Bronze smith, copper miner, scribe, caravan trader, urban mason, temple caretaker |
| **IV — Iron / Classical Age** | Iron smith, road engineer, physician, aqueduct builder, market clerk |
| **V — Medieval Engineering** | Millwright, guild craftsperson, fortification mason, shipwright, merchant, monastic scholar |
| **VI — Early Scientific Age** | Printer, instrument maker, navigator, scientific researcher, cartographer |
| **VII — Industrial Age** | Factory worker, steam engineer, rail conductor, coal miner, machine fitter |
| **VIII — Electrical / Modern Age** | Electrician, power technician, automotive mechanic, aircraft pilot, hospital clinician, community mediator |
| **IX — Information Age** | Software engineer, network engineer, robotics technician, data scientist, renewables engineer, digital ethicist |
| **X — Advanced Technological Age** | Fusion engineer, biotechnology researcher, autonomous systems operator, materials scientist, vertical farmer |
| **XI — Far Future** | Orbital engineer, habitat architect, astrogeologist, planetary ecologist, off-world logistician |

All roles are in the source **data catalogue** `scripts/ai/era_occupations.gd` with stable IDs, domain, first-appearance era, prerequisite technical capability, required facility, geographical context and an explicit `implemented` flag. Current executable work remains limited to **foraging, coastal fishing, timber/stone extraction, shelter building, crop farming, food deliveries, childcare and teaching**. Other catalogue entries describe *future* jobs and remain disabled until the real mechanics exist.

### Era behaviour examples

- A Stone Age coastal community can sustain fishers but a landlocked village cannot. A potter does not appear until clay, fire technology, appropriate facilities and an implemented pottery-production recipe exist.
- An Agricultural Age town cannot produce a farmer's living simply by passing a calendar milestone: it must have cultivated land and locally usable knowledge. Losing cultivation can render farm labour unavailable.
- A Bronze Age metalworker requires both metallurgy and an actual smelter; importing one finished bronze tool does not automatically create a whole bronze industry.
- A Medieval shipwright requires coastal access, shipbuilding knowledge and a physical shipyard, while inland settlements can still develop mills and other industries.
- An Industrial society with no rail network cannot invent railroad employment by label alone.
- A Modern city may use tractors and professional electricians, yet retain foragers and handcraft workers when appropriate.
- Information Age computing needs electronics and working computer infrastructure. The presence of one imported device is not a software industry.
- Far Future orbital workers cannot exist on a planet without the required launch/orbital industrial facilities and successful technology adoption.

### Faith, custom and local institutions

Cultural and spiritual occupations are represented as **conditional institutional activities**, not a hard-coded religion/ethnicity-to-profession mapping. Ceremonial facilitators, temple caretakers, monastic scholars and later community/ethical mediation require real local institutions and, in later phases, interested individuals and culturally transmitted practices. Secular societies, pluralistic cities and alternative community institutions remain possible. The same job's meaning, prestige and conditions may vary through time, local law and individual belief.

## Mechanically implemented skills

**Individual practical experience:** per stable citizen ID, bounded to 24 profession skills (0–1,000 XP each). Tier thresholds: 0 novice; 50 practised; 160 skilled; 360 expert; 700 master. The existing decision-learning system remains intact; occupational skill is a separate competence. Simulated personality may bias career interests but cannot replace resource/knowledge access.

**Physical practice:** extract food, deliver actual meals, extract timber/stone, advance a real construction site, or complete childcare. These hooks credit corresponding skill only after the authoritative physical event. No knowledge or expertise is granted for standing idle, becoming older, holding a badge, or advancing a calendar. Work drives career history and improvement events.

**Tangible benefits:** trained harvesters/couriers can carry one extra actual resource unit; expert builders can advance construction by an extra labour point per physical work step. Material and food conservation still apply.

**Apprenticeships:** teacher must be an actual nearby living adult with at least 50 XP in an available practical trade; pupil must be at least 13, local, and less experienced. Automatic pairing requires established reciprocal trust, verified by existing AI relationships. Each lesson requires teacher time and travel/contact, and cannot interrupt carried resources. A real scheduled lesson grants bounded pupil practice and builds teaching expertise; it neither fabricates resources nor instantly grants nationally adopted technology. Education can proceed orally before schools or libraries exist.

**Disuse and legacy:** unused skills gently fade after five simulated years; learned expertise and teacher–student links survive JSON and binary saves. When dead citizens are archived, active skill records are released, while occupation/mastered-skill summaries remain in historical tombstones.

## Integrations

- `simulation.gd`: initialise per-citizen career records, run bounded career/education planning every 180 ticks, and persist skill system in v4 JSON snapshots.
- `save_store.gd`: include all career/knowledge state in atomic compressed binary saves.
- `food_survival.gd`: skills from real foraging, fishing, harvest and delivery; job preference guides source selection and emergency recruitment, without overriding survival.
- `construction_economy.gd`: skilled builders can seek projects; actual gathering/build actions grant relevant experience and improve labour efficiency.
- `households.gd`: completed infant care creates caregiver experience.
- `citizen_ai.gd`: mentors teach through real AI-scheduled actions, while danger and dependent care remain priorities.
- `autonomous_demography.gd`: professional history persists after citizen death archival.

### Explicit exclusions (future phases)

- Catalogue entries **do not yet** magically create industries, trade, wages, goods, machinery, schools, religious institutions or far-future science.
- The adoption hook `grant_capability(world, nation, tech, evidence)` requires a declared evidence origin but does **not yet validate a complete experiment/learning transaction**. Production discovery and real resource/institution proofs belong in the separate innovation system; this API must not be mistaken for finished autonomous research.
- Current adopted skills are attached to the two prototype capital-based settlements. Multi-settlement economies, town districts, schools, professional licensing and knowledge-transfer between nations require a richer settlement graph.
- Full job-selection utility scores, household budgets, equipment wear, worker wages, production quality, safety and occupational injury are later slices.
- The original 11-era master PDF remains the authority for chronological depth, cultural variation and multiple independent progress paths.

## Tests and release gates

New `tests/era_occupations_test.gd` checks every era represented, profession gating, unchanged time-only progress, cultivation acquisition/loss, relevant skill from real food harvesting, relationship-based local apprenticeship, real teaching, saved skills/abilities, legacy migration, birth compatibility, career archive and deterministic continuation.

```bash
godot --headless --path . --script res://tests/era_occupations_test.gd
godot --headless --path . --script res://tests/autonomous_demography_test.gd
godot --headless --path . --script res://tests/food_survival_test.gd
godot --headless --path . --script res://tests/household_care_test.gd
godot --headless --path . --script res://tests/civilisation_calendar_lifecycle_test.gd
godot --headless --path . --script res://tests/construction_test.gd
godot --headless --path . --script res://tests/citizen_ai_test.gd
godot --headless --path . --script res://tests/simulation_test.gd
```

**Not verified in the current environment:** Godot 4.5.2 parser and actual headless execution, real 160/500/1,500 agent timing, Android APK and Huawei P30 responsiveness. No workflow manually triggered, no merges, no change to pixel-art renderer or HUD. Do not merge until integration tests and long-session benchmarking pass.

## Next milestones

**C2:** genuine settlement-level demand for work; jobs compete for labour, produce materials with upkeep, and link directly to household survival; regional hiring and migration. Introduce skill types that workers teach across travel and trade only after interactions.

**D1–D3:** individual discovery, repeated experiments, real research facilities, cumulative knowledge exchange, documents and practical adoption of new production methods. Enable the next era's roles one recipe/working building at a time, preserving disjoint historical trajectories and local customs.
