# God Sandbox — Phase A Audio Foundation

Status: implemented on isolated branch; engine tests and Android device checks are pending.

## Repository audit
Based on the `main` branch audited 20 November 2026: `project.godot` had no AudioServer bus configuration or audio autoload; `scripts/game.gd` owns UI/touch/world interaction, `scripts/simulation.gd` owns fixed-step state, and `scenes/world.tscn` hosts game.gd. The existing Android workflow tests the simulation and exports with Godot 4.5.2 GL Compatibility. More recent parallel branches are **not** automatically merged into this change; integration requires reviewing their scene/event systems.

## Design
- `scripts/audio/audio_manager.gd` is an instance-owned manager, not an autoload. It adds named buses only if missing, routed to Master.
- Events are keyed by string and mapped to category, gain and an initial procedural PCM effect. Eight category buses: Environment, Citizens, Construction, Disasters, Interface, Music, Ambience, Combat.
- The manager emits `event_accepted` or `event_dropped` for instrumentation. Invalid, muted, offscreen, cooldown and over-budget events are rejected.
- Quality voice budgets: battery=10, balanced=20, high=40. No unbounded per-citizen audio generation.
- All audio times are real-time, independent of simulation time multiplier.
- Settings use `user://audio_settings.cfg`, separate from deterministic world snapshots: master gain/mute, category gain and quality.
- Samples are cached by event key, and can be replaced through `register_sample(event_id, AudioStream)`. Procedural PCM is **only a placeholder**. Source asset filenames/licenses are deliberately not invented.
- World-event positions currently use screen-pixel coordinates converted by `game.gd`, appropriate for the prototype's manually transformed world; when moving to a Camera2D setup, route positions in world coordinates and use a proper AudioListener2D instead.
- Sound emitters are intentionally short-lived; emission culls offscreen events and applies event cooldowns. It does not scan every citizen or run in authoritative simulation steps.
- Calls are wired at UI tap and successful power application/terrain modification. Actual jobs, footsteps and building animation frame markers remain future integrations.

## Extend
```gdscript
game_audio.emit_event("construction.hit", world_to_screen(hit_tile), true)
game_audio.register_sample("construction.hit", preload("res://audio/recorded_hammer.ogg"))
game_audio.set_quality("battery")
game_audio.set_category_volume("Construction", 0.6)
game_audio.set_muted(false)
```
For new events, add an entry to `DEFINITIONS` first. Don't dispatch a sound every fixed simulation tick; dispatch on an actual animation hit or completed action. Do not call audio from deterministic simulation models.

## Validation
Run from the project root using Godot 4.5.2:
```sh
godot --headless --editor --path . --import --quit
godot --headless --path . --script res://tests/simulation_test.gd
godot --headless --path . --script res://tests/audio_phase_a_test.gd
godot --headless --path . --quit-after 30
```
Android: use existing export preset and verify startup, power sounds, mute/persistence, headphone/speaker routing, touch latency and audio performance on Huawei P30 at 1x, 2x and 4x. Profile voice cap and frame time before raising limits. This branch does **not** certify an APK or measured FPS.

## Next phase
Add properly licensed field-recorded sounds for realistic environment/construction, stylised UI/god powers, on-screen sound settings, deterministic animation event markers, biome ambience zones, and further gameplay event adapters. Merge or rebase onto the latest integrated civilisation/UI branch only after resolving integration differences.
