# God Sandbox — Human Civilization 3.0: Deep Emergent Society Architecture
Status: DESIGN ONLY, not implemented. Extends citizen-ai-architecture.md and human-ai-2-cognitive-social-design.md.
Repository: sebbbbrrrr/God-sandbox. Branch: design/citizen-ai-foundation.
Constraints: Godot 4.5.2/GDScript; Android GL Compatibility; 96x128 world, 160 starting citizens, 1500 cap, fixed-step deterministic simulation. Preserve id/nation/x/y/hp/age, six powers, brush, terrain, save/load, renderer-independent simulation. Never silently interpret legacy age counter as years.
Purpose: complex, causally linked society that produces histories instead of scripted plots; staged design and budgets prevent combinatorial explosion.

## 0. Governing principles
- Causal closure: outcomes require actual resources, knowledge, agents, institutions, geography and events. Avoid 'random rebellion', instant resources, fabricated trade or arbitrary tech progress.
- Limited cognition: citizens know only observed or transmitted information, with uncertainty, imperfect memory and varying priorities.
- Scale separation: individuals make local choices; households coordinate; groups bargain; institutions aggregate; nations impose policy. Each layer has authority boundaries and cadence.
- Endogenous feedback: resource scarcity -> prices -> employment/income -> hunger/stress -> crime/migration/trust -> policy -> production and public legitimacy. Break positive feedback via constraints and stabilizers.
- Determinism: authoritative fixed-tick event sequence, stable iteration order, separate deterministic PRNG streams/derived hashes per subsystem; never couple outcomes to render frame or unordered dictionary iteration.
- Explainability: each consequential decision records primary causes and available alternatives; inspectable citizen timeline and regional history.
- Opt-in fidelity: high-detail local simulation and low-detail aggregate distant simulation must preserve conserved quantities and events across transitions. No hidden free creation of food, money, land, population or time.

## 1. Reference simulation layers / data ownership
WorldState: terrain, traversability, climate, physical materials and event log.
EntityRegistry: stable IDs, lifecycle and tombstones for citizens, buildings, households, items/stockpiles, settlements, associations, factions and polities.
CitizenMind: traits, needs, emotions, knowledge/beliefs, commitments, habits, abilities, relationships, aspirations, social role; AI hot/cold split.
Household: members/dependents, pooled finances/storage, home/land access, care/succession decisions.
Workplace/Building: footprint, owner/controller, labour slots, recipes, durability, storage, production queue.
Settlement: population, infrastructure, services, stockpiles, market, local culture, local government and public safety.
Association: guild, faith community, militia, cultural network, faction, political party; membership/obligations/identity.
Polity/Nation: legal regime, treasury, territory, taxation, diplomacy, military chain of command, political institutions.
Environment: seasonal/biome conditions, water & fire & disease once corresponding simulation is active.
History: bounded global event log + historical aggregate statistics, citizen-specific memories, stable historical IDs.
Each module owns authoritative data; communicate via typed intent/command and immutable event data, not directly editing each other's dictionaries. Validate commands centrally; publish effects after successful transaction.

## 2. Time and life course
Introduce explicit SimCalendar {tick, ticks_per_day, days_per_year, season} with documented constants and migration. Legacy age remains as historical counter until migrated; store new birth_tick and elapsed_age_ticks separately.
Life stages: infant, child, adolescent, adult, elder; abilities, schooling, care requirements, health, fertility, dependence and retirement vary with age, condition and culture. Mortality rates are configurable model parameters, not claims of medical accuracy. Protect simulation fairness and avoid simplistic deterministic genetics. Biological ancestry, phenotype and inherited predispositions are separate from learned traits and social positions. Household formation via trust, compatibility, cultural norms, opportunity and legal rules; birth only if eligible adults and resource/care capacity; death generates kinship, inheritance, workplace and political succession events. Non-reproductive partnership and adoption rules can differ by culture/legal model. Track ancestry with compact parent IDs, historical references and bounded family graph queries; never expand all relatives per tick.

## 3. Motivation and psychology
Keep temperament and bounded affect from v2. Add values hierarchy (security, belonging, achievement, freedom, duty, status, curiosity), life satisfaction, identity salience, moral norms, aspiration strength and confidence; most are slow-changing. Habits are context->action preferences learned through outcomes and repetition; can conflict with deliberative plans. Cognitive biases: loss aversion, conformity, in-group preference, recency, status-quo inertia, risk perception; parameters can vary by citizen and context, not racial/ethnic templates. Stress constricts planning horizon; security supports exploration. Recovery and adaptation mechanisms prevent perpetual distress.
Decision outputs: intent with reason codes, ranked candidate utilities, belief confidence and expected cost; validated by world modules. No unconstrained per-citizen LLM calls.

## 4. Knowledge, communication, literacy and information
Agents hold bounded belief graph: subject id/place, proposition enum, confidence, provenance, observed_at, last_updated and expiry. Direct observation has distinct provenance from rumour; observation can still be mistaken when visibility restricted. Communication depends on spatial proximity, shared language/comprehension, relationships, interest and institutional channels. Oral rumours degrade and branch with capped hop counts; official records and literacy preserve higher fidelity but can reflect censorship. Contradiction resolution weighs recency, direct evidence, source reliability and personal bias. Distinguish public information from private secrets. Information flows through routes, markets, messengers, households and later written networks with delays. No global omniscient gossip.

## 5. Culture and language
Culture is an evolving, geographically distributed trait vector at citizen/household/community level, NOT a static property of nations. Examples: hierarchy preference, cooperation norms, property expectations, hospitality, dispute resolution, ritual intensity, family structure, risk-sharing, innovation openness. Membership is overlapping (local, occupational, religious, political); gradual diffusion from interaction, intermarriage, trade, migration and prestige. Language families emerge as bounded dialect similarity markers, affecting communication effectiveness, not full natural language generation. Naming/ritual/craft styles can derive from culture data for future visuals. Cultural drift occurs on slow cadence with inertia; sudden changes require major shocks or sustained contacts. Cultural differences do not imply inherent intellectual or moral hierarchies.

## 6. Religion, myth and institutions of belief
Belief traditions emerge from shared narratives about observed disasters, revered people, rituals and questions about the unknown, then evolve through transmission and institutions. Represent doctrines as finite propositions about norms, authority, afterlife, sacred places and prescribed rituals; confidence and adoption differ by citizen. Rituals consume actual time/resources and can increase solidarity, provide support or cause conflict; religious institutions collect voluntary contributions or taxes only when authorized. Spiritual beliefs are treated as beliefs, not objective validation by game engine. God powers may be witnessed but interpretations diverge by information and culture. Mechanisms for syncretism, schism, reform, tolerance, persecution and secularization depend on social incentives/law. Avoid pre-scripted religions, fixed ethno-religious alignments and permanent deterministic zealotry.

## 7. Economics: conservation and endogenous production
Resource ledger: food, timber, stone, fibres, metal, energy/fuel and optional luxury items. World stock, inventories and stockpiles must reconcile: opening + produced/extracted/imported - consumed/destroyed/exported = closing, with transfers double-entered. Money is a claim/medium and not a physical food source. Every job has required skills, tool/building/land access, time and input/output recipe; weather/geography and infrastructure affect yields. Household consumption and reserves influence labour supply, migration and bargaining.
Markets: local order matching or bounded price-adjustment with transparent shortages; do not calculate every possible buyer-seller pair. Wealth and income distribution tracked by households, including production ownership/rent/tax/wages, debt obligations with explicit creditor and maturity, defaults and bankruptcy. Trade routes require traversable paths, carrying capacity, security and transport cost; taxes/tariffs alter incentives. Inflation and monetary creation only with a defined currency institution. Black markets, theft and smuggling must use real inventory transfers.
Add 'market close' or aggregate trading cadence. Avoid runaway monopolies without countervailing entry, competition, policy or shocks. All prices and quantities fixed-point integer; enforce arithmetic overflow guards.

## 8. Governance, laws, legitimacy and power
Polities and settlements distinguish de facto controller from de jure authority. Institutional templates: council, hereditary monarchy, elected representatives, oligarchy, military government, decentralized commons; these are configurable starting mechanisms, not forced evolutionary stages. Laws are versioned rules affecting property, taxation, crime definitions, rights, militia/conscription, movement, trade, religion and succession; enacted via defined decision procedures and enforced with imperfect coverage.
Legitimacy is multidimensional: perceived effectiveness, procedural fairness, cultural fit, coercive capacity, elite support, public trust. Policies have actual fiscal costs and enforcement capacity. Corruption is a behaviour opportunity under power asymmetry and weak oversight, not a random percent. Policy debate and elections use interest, information, ideology, trust and coalition formation; citizen votes reflect preferences and incomplete knowledge. Succession resolves by law, claimant support, administrative control and military allegiance; conflicts may remain unresolved, not guaranteed coups.

## 9. Crime, justice, reputation and security
Crimes require motivated actor, opportunity, defined prohibition and a concrete victim/property or public harm. Incentives: deprivation, perceived unfairness, coercion, profit, local enforcement risk, social norms and individual values. Witnesses and evidence are uncertain; allegations are not proof. Judicial process can vary: informal mediation, restorative agreement, fine, confinement, exile; all require physical/institutional infrastructure and staff. Penal outcomes consume resources, influence labour/trust and can provoke grievances. Protective services, community surveillance and trust alter crime rates endogenously. Prevent infinite prison populations or unjustified omniscient prosecutions.

## 10. Politics, factions, collective action and conflict
Faction formation when overlapping grievances/interests and communication channels exist. Membership has commitments, trust, leadership, internal disputes and resource costs. Demonstrations/strikes are coordinated actions with opportunity costs and risk, not dice rolls. Negotiation models offers, concessions and reservation values; commitments are tracked with fulfillment and breach. Rebellions require organized support, resources, coordination, territorial footholds and state response; no instant spawning rebel armies. Conflict outcomes feed population displacement, supply, legitimacy and culture.
Foreign relations track disputes, trade dependence, treaty obligations, credible commitments, reputational trust and perceived threats. War requires mobilization, equipment, supply lines, command and movement; casualties and destruction are conservation-based. Avoid strategic omniscience.

## 11. Migration and geography
Migration decisions consider household safety, work opportunities, kin, culture, known routes, border rules, transport cost and beliefs about destinations. Information on destination is incomplete; migrants can return or relocate again. Movement flows through valid pathfinding and housing capacity. Environmental shocks, resource depletion, trade connections and laws affect migration. Preserve population counts across region transfers; no teleport unless a declared mechanic.

## 12. Technology, education and cumulative knowledge
Knowledge units are finite research/craft techniques with prerequisites, discovery/transfer channels, experimentation costs and institutional support. Individuals accumulate skills through practice and teaching; societies preserve know-how via specialists, apprenticeships, schools and durable records. Innovations can be discovered independently under suitable materials, experience and needs, with deterministic chance/exploration budgets. Adoption requires capital, tools, incentives, access and compatibility; a discovery doesn't upgrade all production instantly. Knowledge can be lost following death, displacement or institutional collapse if no carriers survive. Tech feeds productivity, warfare, health and communication, with tradeoffs and environmental costs.

## 13. Ecology, public health and disasters
Environmental subsystem owns soil fertility, vegetation, biomass, temperature, rainfall, water quantity/flow, pollution and fire only as implemented. Carrying capacity feeds production/settlement feasibility. Distinguish edible resources from decorative trees. Disease model optional: bounded health states (susceptible/exposed/infectious/recovered) with contact graph/seasonal modifiers; no detailed pathogen engineering mechanics. Institutions can respond with care, sanitation, quarantine, relief and prevention at actual cost. Disasters produce observable events and physical consequences. God actions can create shocks, with human interpretations conditioned on witness and belief.

## 14. Institutional and intergenerational path dependence
Every generation inherits modified material conditions and institutional rules, not just genetic traits. Accumulated property, laws, schools, learned techniques, grievances, memorials and stories persist with decay and loss. Historical eras are derived summaries of salient changes (founding, reforms, famine, migrations, war), not randomly assigned labels. Citizen biographies and nation chronicles are generated from event-backed templates; no hallucinated battles or diplomacy.

## 15. Deterministic event-sourced command pipeline
Scheduled module produces Intent {tick, actor_id, intent_type, target, parameters, rationale}; WorldRules validates resources, permissions and current state; Commit performs atomic mutations; EventLog appends stable {tick, seq, type, participants, location, payload} IDs; local perception distributes visible events; minds react; aggregates update. Internal events must not recursively trigger unlimited events in same step: bounded work queue and defer overflow deterministically. Explicit mutation API with invalidation notifications for terrain edits from Brush.paint_segment, powers, construction and simulation routines. Fixed order: environment -> scheduled production/consumption -> commands -> movement/interactions -> health/demography -> events -> institutional aggregations -> snapshots; define exact order when implementing to avoid false causal effects.
Never adopt pure event sourcing of every microscopic state if snapshots and delta logs are cheaper; maintain versioned snapshots plus recent bounded event journal.

## 16. Fidelity and performance strategy
Use three granularity tiers:
- Active/visible neighbourhood: individual tactical AI, pathing, encounters, full spatial queries.
- Offscreen settled region: event-driven individual strategic states, pooled routines and only milestone interactions.
- Faraway/dormant region (future larger worlds): aggregate cohorts/workforce and resources; instantiate agents by stable IDs when focused, maintain conservative mass/resource/accounting and persistent key personalities. At current 96x128, avoid expensive cohort swapping initially; introduce only after profiling and design equivalence tests.
Hot state stored in packed arrays/struct-of-arrays where proven necessary, cold beliefs/social records in capped maps. Stable index and entity generation/version prevent dangling references. Pathfinding cached with terrain revision, bounded nodes per tick. Social links capped (12 active), beliefs capped (16-32), memories capped (12 episodes + 8 summaries), active plan max 4 steps, institutional memberships cap where appropriate. Query spatial buckets, not all pairs.
Schedule emotion/needs often; tactics staggered 10-30 ticks; citizen strategy 300-900; market/society weekly (configured in calendar); culture and tech seasonally or by milestone. CPU work ceilings are in counts (decisions, path nodes, events), not wall-time-dependent branch outcomes. Measure wall-time only for telemetry. Track p50/p95/p99 simulation step time, memory, event drops, save size and citizen throughput on Huawei P30 at 160, 500, 1500 agents.
Keep economy/cognition optional feature flags with deterministic enabled/disabled schemas to allow gradual activation.

## 17. Tuning and falsification
Build scenario fixtures with seeds and scripted interventions; validate conservation of citizens/resources/currency under matching rules, persistent consequences, information boundaries, political legitimacy effects, safe movement after brush edits, stable births/deaths and save replay.
Key tests:
- crop failure -> food stock decreases -> prices rise if market exists -> households substitute/migrate; cannot create food.
- witnessed assault -> victim/witness beliefs diverge; unseen citizen has no direct knowledge; trial/evidence rules apply.
- famine + high tax -> lower trust and organized dissent only where communications/coordination and viable mobilization exist.
- new technique -> selected trained users adopt then diffuse; without artisans/knowledge carriers the technology can disappear.
- migration after fire -> households route to reachable settlement with housing; if blocked they cannot teleport.
- faction leadership loss -> leadership succession and group cohesion follow rules; no automatic instant civil war.
- seed-replay/save-resume -> same event IDs, resource ledgers and mind states.
- 1500-agent soak -> bounded relationships/beliefs, finite event queue, no uncontrolled O(N^2).
- no renderer dependency, six powers and touch brush unchanged.
A simulator may generate surprising outcomes, but the causal explanation must reconstruct events and incentives.

## 18. Development order and realistic scope
Phase 0: deterministic simulation calendar, command/event contract, stable entity IDs, migration, instrumentation; write tests before expanding.
Phase 1: v1-v2 mind system (needs, emotions, limited knowledge, goal selection) genuinely implemented and benchmarked.
Phase 2: physical housing, food, production and inventory conservation; households and occupations.
Phase 3: bounded exchange, local markets and trade paths; genuine income/class stratification.
Phase 4: social belief transmission, values, cultural diffusion, language markers and institutions.
Phase 5: law, enforcement, politics, coalitions, diplomacy and military logistics.
Phase 6: education, innovation, demographic generations, culture evolution and history.
Phase 7: distant-region abstraction and further physics/environment integration as measured needs require.
Do not implement all phases in one PR; each vertical slice must include executable behaviour, tests and a reproducible sample scenario.
Separate branch preserves graphics team ownership of game.gd, world.tscn, project.godot, sprites/atlases and UI. AI module should touch only scripts/ai/**, simulation interfaces when integration approved, and AI tests. main remains unchanged. No GitHub Actions manually or by merging without approval.

## 19. Integration API proposed
- read-only WorldQuery interface: citizen summary; cell terrain; local entity/structure queries; polity/market public summaries.
- IntentSink: submit(citizen_id, intent, tick) -> validated Result(code, effects).
- WorldEventBus: poll_since(sequence) with local visibility/filtering and bounded buffer.
- TerrainChanged {cell list or region, revision, cause} emitted from centralized mutation, including brush bulk operations.
- CitizenLifecycle {birth, moved, injured, died}; persistent ID references.
- AIInspection(id) returns concise state, explanation and provenance; renderer chooses how/if to show.
Version these contracts, never change existing citizen renderer keys unilaterally.

## 20. Required integration gate
Compare and rebase against latest graphics branch before any code integration. Preserve existing deterministic v1 save semantics, terrain brush behaviour, one- and two-finger touch controls, six powers, Android GL renderer. No feature is claimed as implemented merely because it appears here. 
