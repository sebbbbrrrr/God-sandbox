# God Sandbox: Physical Construction — first vertical slice

Branch: feature/citizen-material-construction
Base: design/citizen-ai-foundation

## Implemented
- Settlements with housing demand request a single real house project, up to twelve homes per nation.
- Assigned gatherers locate nearby finite FOREST timber and MOUNTAIN stone. They walk to an accessible harvest cell, extract one unit, then walk back to the capital depot to deposit it.
- One builder per active project withdraws three timber and one stone from stockpiles, carries them to the worksite, and contributes six scheduled units of construction work. Only then is a persistent house (capacity six) created.
- Houses display through the existing TOWN terrain rendering as a compatibility fallback until a separate graphics integration provides house sprites and scaffolding.
- God powers and terrain painting can remove an actual house or worksite. Depleted nodes reset when the user actively repaints a terrain cell.
- Jobs, cargo, resource depletion, stockpiles, active construction and completed houses are included in the current version-four world snapshot, without changing AI save-codec identifiers.
- Existing version-one through version-four save files with no construction data can still be restored.
- The old timed town-cell creation and automatic spawning are removed from this development branch. A human must perform work to build a house, and the game no longer creates citizens without a demographic mechanic.
- Immediate hazards override construction jobs; the existing pathfinding and mobile simulation scheduling remain in use.
- Work is intentionally restricted to four gatherers per nation plus a reserved builder. Resource searches are limited to a twelve-cell region around the capital.

## Not yet implemented
- Visual construction stages, hauling equipment, scaffold sprites, assigned house occupants and working workplaces.
- Food, farming, hunger, craft recipes, money, trade, employment contracts or job experience.
- Simulated calendar, actual age/life stages, reproduction, inheritance, skills and technological evolution.
- Large-scale resource ecology or regeneration. Timber/stone nodes contain fixed finite quantities and can only be renewed by terrain-changing powers.
- The current citizen AI still uses its existing simulated age counter. It should not be interpreted as elapsed years.

## Regression test
Run from a Godot 4.5.2 workspace:

    godot --headless --path . --script res://tests/construction_test.gd

The fixture creates a small deterministic settlement with finite timber and stone, runs two parallel simulations, checks a completed house was genuinely constructed, verifies extracted materials equal stored + in-transit + used materials, tests save/restore continuation and destruction by ash. The existing citizen-AI and simulation regression suites must also pass.

## Next vertical slices
1. Integrate house/worksite sprites and citizen carrying/building animations with the pixel-art renderer.
2. Assign citizens to houses; add food collection, farming, households and daily survival.
3. Add a deterministic simulation calendar, proper life stages, family relationships and reproduction/death (separate from the legacy age counter).
4. Expand to professions, skill learning, production buildings and tool-making.
5. Connect innovation/education, culture, generations and civilisation history with actual material constraints.

## Integration gate
Do not merge this into main or the pixel-art branch before rebase/integration review, Godot headless test execution, an Android debug build and Huawei P30 gameplay/performance checks. This branch modifies scripts/simulation.gd, scripts/ai/citizen_ai.gd and a new AI construction module; graphics code, UI, project settings and Android workflows remain unchanged.
