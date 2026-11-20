# Integrated audio and autonomous construction — God Sandbox

## Scope and provenance
Development branch `feature/audio-construction-integrated`, based on `feature/settlement-roads-trade-economy-b-e` (which stacks on the real-time work animation branch). Ported the Phase A audio manager and Phase B read-only living-world adapter from `feature/audio-phase-b-living-world` without replacing the advanced simulation, construction ledger, renderer, UI or save schema.

**Scene inspected:** `scenes/world.tscn` uses `scripts/unified_game.gd` (derived from `scripts/game.gd`). This is why audio is instantiated in `unified_game.gd`; older prototype `game.gd` is deliberately untouched.

## What is wired
- Actual citizen coordinate changes, with material-tagged footsteps; up to three events per observed tick at 1× and one at higher speed. A step produces no sound if the citizen did not move. This uses the authoritative citizen positions, not an assumed walking animation.
- Camera-local biome ambience chosen from real simulation terrain, with no per-tile sound objects.
- Actual construction site progress deltas (including stage transitions) are read from authoritative `site.progress`; a nearby assigned `build` job must exist to trigger construction impact sound.
- Gathering source→depot transition must have positive material quantity to produce a woodcutting/mining effect.
- Material pickup and delivery are inferred from real job phase/cargo changes, not particles. Repair/demolition effects are bound to decreasing remaining labour for retained jobs.
- Construction *timbre* is selected from the currently presented stage variant via `citizen_work_visuals.gd`. This is an approximate category match; pixel-perfect contact-frame syncing still needs explicit animation timeline events.
- God powers and HUD tool/pause/speed changes emit distinct interface/action effects.
- On pause, gameplay/ambience polling stops; UI effects remain functional. At 2×/4×, voice caps and event cooldowns apply in wall-clock time, never pitch-shift.

## Boundaries
- Real rain/thunder/wind event hooks remain reserved in `living_world_audio.gd`; the separate weather branch was not merged.
- Ten original 16 kHz mono WAV foley samples are now committed in `assets/audio/foley/` and automatically imported for selected live events. They are purpose-generated, shaped-noise samples (not recordings); remaining event IDs retain the procedural fallback. They should undergo creative listening/mastering review before shipping.
- The audio observer does not create citizens, materials, jobs, labour, transactions, or world edits. Volume/preferences are saved separately in `user://audio_settings.cfg`.
- Only actions with a visible event marker or an observable authoritative state delta generate work audio; one-tick jobs which are created and removed within the same observation window may not sound. Missing sounds are preferable to invented work.
- Dynamic mixing/ambience blending and fully animated tool-contact event markers are future sound polish tasks.
- The branch has not been merged with the newest UI, settlement founding, physical object atlas or era-art branches. Integration with these requires an explicit merge/rebase and conflict review.

## Validation
The dedicated GitHub Actions workflow `.github/workflows/audio-construction-android.yml` on this branch is configured for Godot 4.5.2 headless import, prior game/UI/economy tests, Phase A/B audio regression tests, autonomous construction regressions, scene smoke test, signed debug export, APK signature verification, ZIP structure verification and artifact upload.

**Do not claim passing tests, an exported APK, or Huawei P30 playback until a successful workflow run and phone test establish them.**

Suggested device acceptance: 1×, 2×, 4× and pause/resume with ≥500 citizens, construction resource extraction and delivery, stage advances, touch pan/zoom, headphone/speaker switching, silent setting persistence; profile dropped voices, frame time and memory.

## Original sound asset pass
The committed short WAV library covers chopping, mining, sawing, digging, building, material delivery, grass/stone footsteps, UI selection and the fire god power. Each is a discrete original generated asset with no third-party licensing dependency. Dedicated `tests/audio_sample_test.gd` validates import and playback resource types. The importer must run before these tests. All unlisted events retain fallback. This is an implementation foundation, **not** a claim of professional recorded ambience or complete sonic polish.

## Current CI blocker
At the last check, the GitHub connector returned **zero workflow runs and zero statuses** for this branch head. No Godot executable or Android SDK was available in the execution container. Consequently there is no verifiable passing Godot build or debug APK to link. Run `.github/workflows/audio-construction-android.yml` on the branch (or push a new commit if Actions triggers are enabled); use the exported `GodSandbox-Integrated-Audio-Android-debug` artifact only after the workflow succeeds. Device speaker/headphone and latency testing must then occur on Huawei P30.
