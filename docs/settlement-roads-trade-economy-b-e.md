# God Sandbox — Autonomous settlement planning, roadworks and regional trade (B–E foundation)

**Branch:** `feature/settlement-roads-trade-economy-b-e`  
**Base:** Phase A2 work-animation branch, PR #22, which builds on autonomous construction PR #20. **Do not merge to main without resolving the stacked branches and testing the combined Android APK.**

## Implemented and verified

- `scripts/civilisation/strategic_planner.gd` ranks eligible building sites by access, clustering, production resources, coastline and building purpose. This is a site-ranking component, **not a complete zoning or town-government system**. Existing placement checks still enforce terrain, footprints, collisions and access.
- `scripts/civilisation/road_trade_economy.gd` creates an actual walkable, bounded, reproducible connection plan between the existing two capitals. Road sites are incomplete until a living, eligible citizen physically travels to them and performs labour. Road construction does not create goods or modify terrain materials. Planned early trails require clearing/compaction labour, not invented stone expenditure.
- Completed roads have authoritative per-cell records and are rendered using the existing pixel path assets. Road records affect A* path costs; the renderer's older decorative settlement paths remain separate.
- The planner adds bounded local spurs from completed housing toward the growing physical route.
- Trades require a *completed connected road*, a real carrying citizen, appropriate stock in both depots and a reciprocal commodity. The merchant physically withdraws an item from their own depot, follows actual road waypoints to the other capital, executes an atomic two-commodity barter at the foreign depot, then carries the payment back home. A failed barter returns the originally carried item. The original inventory authority continues enforcing proximity, carry weight, reservations, serial-instance integrity and `minted = holdings + consumed + destroyed`.
- Local reference quotes respond to holdings and outstanding construction shortages. These **are reference prices only**, not a monetary system, traded coin balance, or fully endogenous market-clearing prices.
- The existing citizen work overlay draws road clearing/levelling and merchant cargo/loading gestures; actual movement and labour drive the visuals. No animations mint work or stock.
- Both ordinary JSON snapshots and compressed world saves persist roads, road sites, assignments, route, trade jobs, quotations and capped trade history. Old saves without this optional state remain loadable.
- Runtime is bounded: two roadworkers maximum, 320 queued road segments, 320 route points, capped logs, one connection scan at a time with retries. Existing per-citizen A* budgets remain in force.

## Explicit scope boundaries

The *existing engine supports only two capital/depot authorities*. Although basic inter-capital barter and site ranking are implemented, this is **not** full multi-settlement commerce. A realistic 11-era autonomous economy still requires:

1. Arbitrarily many villages, settlement identities, per-settlement custody, independent local civic governance and outpost founding.
2. Typed road upgrades, physical maintenance and materials, bridges, ports, shipping, rail and later-era transport technology gates.
3. Production buildings (farmhouses, mills, marketplaces, warehouses, factories), inventories and occupation-specific factory tasks with quality/consumption.
4. Genuine supply contracts, household budgets, work wages, pricing, currency, taxes, banking, markets, politics and long-distance resource scarcity.
5. Local historical/cultural/legal variation tied to actual institutions and learned technology rather than automatic year unlocks.

In particular, the occupation catalogue includes merchant, market clerk and road engineer as **future-disabled role definitions**. The new road crew and trader tasks are implemented worker activities but do not yet unlock those listed professions, advanced skills, wages or guild systems.

Roads currently use the existing `path_join_` atlas family and use labour-only primitive trails. They are not bridges. Roads improve path selection but do not accelerate the authoritative tile movement tick. The regional economy does **not** autonomously research the eleven ages. It cannot create cross-island trade if the capitals have no land connection.

## Validation

The branch runs `.github/workflows/settlement-road-trade-qa.yml` on its own pushes:
- Godot **4.5.2** full project editor import / script parser verification.
- `tests/regional_economy_test.gd` — 35 checks (actual work, completed roads, physical resource acquisition, tamper-proof barter, conservation, persistence and terrain destruction).
- `tests/universal_construction_test.gd`
- `tests/construction_test.gd`
- `tests/unified_integration_test.gd`

**All four tests and the script import passed on GitHub Actions as of 20 November 2026.** Android APK runtime, P30 device battery/FPS, extended multi-hour simulations, 500–1,500 citizen performance and full production release checks require separate validation. Keep the branch a draft PR until those checks are satisfied.

## Manual demonstration

Use the normal God Sandbox scene or the existing construction demonstration. In a world where two capitals share an unblocked land path, the plan starts automatically, assigns physical roadwork to available adults and persists connected trails. After the road is complete, if capital A has at least four units of one commodity and capital B has at most one, and capital B has at least four of the reciprocal commodity while A has at most one, eligible merchants may exchange 1-for-1 units across the route.

For the deterministic test fixture:

```sh
godot --headless --editor --path . --import --quit
godot --headless --path . --script res://tests/regional_economy_test.gd
godot --headless --path . --script res://tests/universal_construction_test.gd
godot --headless --path . --script res://tests/construction_test.gd
godot --headless --path . --script res://tests/unified_integration_test.gd
```

This slice intentionally preserves the existing two-nation simulation, physical inventory, construction cost flow, household priorities, civilian cognition and Android GL Compatibility renderer.
