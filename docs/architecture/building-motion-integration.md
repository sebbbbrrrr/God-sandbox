# Authored frame sheet milestone — November 21, 2026

This revision adds 37 committed original-pixel construction PNG sheets in
`assets/pixel/construction_frames/`, encoded as `.png.b64` files for explicit
Android export. **32 cumulative frames per building, 1,184 frames total**.
Every building has its own manually authored roof boundary, foundation
boundary, post coordinates, brick/plank spacing and roof-course geometry in
`data/architecture/hand_authored_piece_layouts.json`.

The frames are rasterized from the original approved sprite atlas—not redrawn
as low-resolution stand-ins. Frames progressively reveal individual
brick/plank-sized source-pixel patches. The final (31st indexed) frame is
pixel-identical to each building's original asset. These are artist-directed
geometry masks and baked frame images, **not 1,184 independently repainted
pictures**, nor literal one-for-one material-unit animation.

### Actual game integration
- `architectural_build_overlay.gd` now decodes each sheet lazily with
  `Marshalls.base64_to_raw` + `Image.load_png_from_buffer`, caches the
  `ImageTexture`, and draws the correct frame in world-space based on real
  saved construction stage/labour.
- The 32-step presentation only catches up to real paid labour, never advances
  ahead of it. When a visible project finishes, the last queued frames finish
  playing while the static completed-building draw is temporarily suppressed.
  The underlying gameplay building completes immediately; its simulation logic
  never waits for presentation. The overlay remains bounded and freezes when
  the simulation is paused. Anchors match the permanent sprite depth cell.
- The older generic construction visuals and operation effects are suppressed
  when the actual pixel-world renderer is active, preventing duplicate houses
  and machinery.
- Android export includes `assets/pixel/construction_frames/*.png.b64`.
- The contract test validates the 37 files, PNG decoding, dimensions, initial
  and completed frames, and **every final pixel** against the original atlas.
- `tools/author_construction_frames.py --verify` is a separate reproducible
  Pillow-based verification path. The corresponding authoring command (without
  --verify) rebuilds the sheets using the manually authored construction
  geometry.

### Testing and release limitations
The 37 sheets were successfully created and committed and three (branch
shelter, adobe house, bronze forge) were visually inspected, but the runtime
has **not** been built or executed inside Godot here. Headless tests, GL
Compatibility screenshots, Android debug APK/signature verification and
Huawei P30 tests remain **not run**. Keep PR #39 as a draft until those are
completed. Any claim of proven device rendering or consistent 30/60 FPS would
be premature.

The existing catalogue has 37 definitions across Ages I–III, not Ages IV–XI.
The tooling is extensible, but later-age assets/animations remain separate work.
A future high-fidelity upgrade can isolate roof beams, rafters, each actual
individual brick and door ornaments with bespoke painted intermediate pixels;
the current frames are unique source-faithful section reveals.

---

# Architectural construction & operational motion — integrated pixel-world pass

Base: PR #38 / `feature/architecture-batch-b-bronze`. Branch: `feature/building-assembly-and-operational-animation`, PR #39.

## Implemented (November 21, 2026)
- **37/37 current catalogue building IDs** (15 Age I, 13 Age II, 9 Age III) have explicit material-family-aware construction profiles at `data/architecture/construction_motion_manifest.json`. All 37 unique final sprite keys resolve to existing atlas rectangles; no existing original pixel art is replaced.
- World-space `architectural_build_overlay.gd` is now attached to **the actual PixelWorldRenderer**. It renders partial source rectangles **from each building's own original atlas sprite**: foundation, walls, roofing. Brick/plank-sized source rectangles appear in rows as saved `stage`/`stage_work` advance. Survey stakes and paused-site tint remain.
- Three-stage legacy projects and six-stage authored projects map to separate assembly phases. Progress does **not** advance from render time; saves and real workers remain authoritative.
- When real `operate` jobs are at the facility: grain-grinding and water-lift wheels turn; weaving, cordage and yards reciprocate; charcoal, kiln and bronze metallurgy show embers. Active water-lift effect follows its paid-service expiry state.
- One screen-culled CanvasItem, nearest-neighbour textures, bounded 40 visible construction sites/48 operational effects and 12 Hz overlay repaint; no per-brick nodes or repeated image regeneration.
- Added a Godot headless **contract test** covering every current catalogue sprite and stage progress. The new test is committed but not yet executed.
- Production, costs, worker priority, AI and persistence formats remain unchanged. This is a rendering-only feature.

## Precise limitations (not yet completed)
- **Not one bespoke hand-authored sprite-frame series per building.** The source pixel silhouette is authentically reused, but its source rectangle is partitioned geometrically by coarse material family. Real material item counts are *not* equal to pixels/sections revealed. Material availability controls real stage advancement, not every separate visual rectangle.
- **No Age IV–XI buildings exist in the current 37-definition catalogue.** They cannot be described as implemented. The same rendering architecture can receive their sprites and profiles when added.
- Operating machinery is composited above intact artwork. Mechanism pivot coordinates and silhouettes need individual art-direction and P30 visual checks.
- Existing `construction_visuals.gd` and `building_state_visuals.gd` support other/legacy game draw paths. The pixel-world renderer uses the newly wired overlay; do not assume older static effects are drawn there.
- No actual Godot parse/test run, screenshot verification, Android export, signing or real Huawei P30 profiling was possible during this connector-only task. The branch stays draft.
- Screen-culling priority is traversal order rather than nearest-first when >40 sites are visible. A lower budget could be used after real-device profiling.
- Rotating grain-grinding gear is a mechanical illustration, not a historically exact power-driven windmill. There is no windmill asset among the 37 current definitions.

## Validation requirements
1. Run `godot --headless --path . --script res://tests/building_motion_contract_test.gd`.
2. Run existing architecture suites and GL Compatibility render captures.
3. Compare staged captures at 0/25/50/75/100% for all 37 building sprites; inspect pivot and segment reveal order (especially tiny roofs).
4. Save/load mid-build and confirm identical visible construction state.
5. Check all idle/working/abandoned/damaged states and no phony output or animation during paused gameplay.
6. Export local Android arm64 debug APK, validate signature, test Huawei P30 across zoom, accelerated simulation and many simultaneous sites.

## Next art production milestones
A. Create authored transparent sprite layers (foundations, each individual post/brick/plank, external cladding, roof tiles, doors/windows, mechanism parts) for each approved building, with source-alpha provenance and unique anchor alignment.
B. Map visual subparts to actual per-stage material ledger units and material delivery progress while avoiding invented work.
C. Author correct operating animations for remaining building functions and future mills, pumps and industry.
D. Extend the architecture catalogue to Ages IV–XI and regional variants, with no old atlas regressions.
