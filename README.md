# God Sandbox

Android-first, WorldBox-inspired original 2D simulation sandbox, built in **Godot 4.5.2 + GDScript**.

## Playable foundation
- Seeded 96×128 island terrain, multiple biomes and simple settlements
- 160 initial citizens divided into two nations
- Deterministic fixed-step world simulation, bounded population, native save/load
- Six powers: Raise, Fire, Forest, Bless, Spawn, Ocean
- Touch pan, pinch-zoom, bottom toolbar, pause and simulation speed
- Original project-owned pixel-art assets; no internet permissions, accounts, native plugins or paid runtime services
- Visible 16×16 chunk culling, dirty updates and three zoom detail levels; OpenGL compatibility renderer for older Android GPUs

This is a **prototype**. Advanced economies, social networks, warfare, falling-sand physics, detailed animals and C++ acceleration are future work; none is claimed to be implemented.

## Building
GitHub Actions workflow: `.github/workflows/android.yml` (manual or on push to `main` / `dev/phase1-pixel-art`).
The workflow downloads Godot and its Android export templates, installs Android tools, checks GDScript via headless project import, and exports a **debug-signed APK** as an artifact.

You do not need to install development software locally to download and test the APK on a phone. The workflow runner downloads build dependencies; test APKs are not suitable for Play Store production signing.

## Development
Main scene: `scenes/world.tscn`
Simulation: `scripts/simulation.gd`
UI and inputs: `scripts/game.gd`
Pixel renderer: `scripts/pixel_world_renderer.gd` and `scripts/pixel_chunk.gd`
Assets and complete inventory: `assets/pixel/README.md`
Implementation and measurements: `docs/visual-overhaul.md`
Huawei P30 checklist: `docs/huawei-p30-checklist.md`
Tests: `tests/simulation_test.gd`

Build gates: workflow succeeds → APK launches on Huawei P30 → controls and saves work → sustained FPS/memory measurements. Desktop software-GL measurements are documented; Android device measurements remain outstanding.

## Privacy
This clean repository does not intentionally contain secrets or personal addresses. Avoid committing signing keys, credentials or identifying data. Commit with GitHub's private noreply email.
