# Phase B readiness

The universal shelter-construction vertical slice is integrated into the real simulator and verified by the Phase A test suite. Review the draft branch before merging.

| Status | Scope |
|---|---|
| Implemented and headless tested | Requests, autonomous shelter demand, finite gathering, protected reservations, partial physical hauling, site inventories, stages/labour, dwelling beds, footprints, save/load/migration, interruption, repairs, abandonment, paid conversion, demolition and salvage. |
| Implemented; visual/device review pending | Crisp stage overlays in the unified frontend, definition-selected completed sprites, arm64 debug Android export. |
| Data-only / temporary | Two building examples rather than an era catalogue; existing final sprites; temporary construction motifs; storage and detailed structural metadata; geographic/cultural tags without automatic context generation. |
| Deferred | Full city planning/economy, eleven-age architectural content, arbitrary settlement/depot networks, authored construction animations, autonomous cache retrieval, interior collision/pathfinding and destruction physics. |
| Integration risks | Two nation/depot identities; one worker/site; 128 active sites and 64 work commitments; bounded recent history; legacy tool-yard construction remains a D3 adapter. Large-population accelerated simulation and APK replacement/save upgrade still need Huawei P30 measurement. |

Before Phase B: review preservation of old saves and terrain editing on device; measure 1×/2×/4× with 100/500 citizens; resolve the citizen-dispatch bottleneck; define the first shared workplace/storage examples and multi-settlement identity adapter. Keep new content on top of the shared request, custody, stage and lifecycle services.

Commands, audit details, schema semantics and limitations: [Architecture and validation](universal-construction-phase-a.md). Exact measurements: [benchmark JSON](construction-phase-a-benchmark.json), [regression results](construction-phase-a-validation.json), [Android export](construction-phase-a-android.json).
