# God Sandbox physical item artwork — 420-region expansion

Base: Phase A2 construction animations PR #22 (`06f1d3012beafef57bac83a29e4be49f2a6f8fa1`). This branch is a draft integration track, not merged into main.

The added indexed PNG contains **420 deterministic, original 32×32 procedural pixel-art regions** on one 512×864 page. This is an initial functional sprite library, not 420 hand-drawn illustration commissions. Every one of the original 100 catalogue items has a unique stable artwork key, plus action frames, stage components, transport/storage states and effects.

## Region allocation
- materials: 85
- tools: 75
- citizens: 90
- construction: 60
- workstations: 35
- storage: 30
- household: 25
- effects: 20

## Art and runtime
- `assets/pixel/physical_atlas.png`: indexed, binary-alpha, 420 packed regions. Palette and source artwork are produced directly in this implementation.
- `data/visuals/physical_sprite_manifest.json`: stable ids, rects, categories and catalogue mappings.
- `scripts/visuals/physical_sprite_atlas.gd`: shared texture and rectangle renderer; no per-item nodes or per-frame texture generation.
- Existing inventory/item UI is retained and references new regions in preference to the old 9×9 fallback motifs.
- A read-only overlay uses actual inventory quantities and existing task cargo. No gameplay simulation or world save schema changes.

## Explicit limitations
These compact procedural pixel pieces establish visual coverage, but do not constitute high-resolution bespoke authored art or every animation described in the full programme. Directional animated body frame sequences and stage-specific draw layers require further in-game integration. No claim of complete eleven-era coverage, physical object collision, or physics-based debris.

## Validation
Run `godot --headless --editor --path . --import --quit`, then
`godot --headless --path . --script res://tests/physical_sprite_atlas_test.gd`
and the existing construction, item inventory and renderer regression suites. Check GL screens and Android debug export before merge.
