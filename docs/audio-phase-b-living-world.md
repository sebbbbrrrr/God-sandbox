# God Sandbox Audio — Phase B: Living World

Branch: `feature/audio-phase-b-living-world`, stacked on Phase A (`feature/audio-phase-a-foundation`). Draft only; do not merge independently into main.

## Live integration available on this branch
- `scripts/audio/living_world_audio.gd` is a read-only observer. It compares citizen positions after authoritative world steps; only a *real position change* leads to a footstep event. Does not touch simulation RNG, save format, AI, pathfinding or inventories.
- Footstep timbres use terrain: sand/beach, grass/meadow/forest, stone/ash/mountain, wood-like town. These are material suggestions for the current prototype; wooden towns are not asserted as every settlement's actual material.
- Max 3 audible footsteps per observed tick at 1×, max 1 at accelerated simulation speed. Audio engine separately enforces voice caps and cooldowns. Offscreen citizens generate no sound.
- Camera-local 5×5 low-cost biome sampling chooses one ambient event at most every 7.5 seconds. Forest, ocean, settlement and wilderness textures use procedural placeholder PCM; not sustained seamless loops or sourced environmental recordings.
- Existing UI and god-power audio retained.

## Construction integration adapter (NOT live on current prototype)
When integrating with the advanced construction branch's animation system, call:
```gdscript
living_audio.on_work_marker(game_audio, "hammer", worker_id, actual_hit_marker,
    world_screen_position)
```
Marker must be monotonically increasing **per worker** and emitted by a real authoritative work action or a validated animation contact frame; never every `_draw` call. Supported names: chop/fell, mine/quarry, saw, dig/excavate, deliver/unload, build/hammer/masonry/roof, repair and demolish. No job material is created by audio; no arbitrary historical era is assumed. The advanced branch may require action names to be mapped to these exact labels. No claim of live construction synchronization before the stacked audio code is ported there.

## Weather integration adapter (NOT live on current prototype)
Actual weather event/transition marker:
```gdscript
living_audio.on_weather_event(game_audio, "thunder", "strike:" + str(strike_id),
    world_screen_position)
```
Rain, wind and thunder definitions exist but no real climate state exists in the audited main prototype. No synthetic thunder is emitted without a real event.

## Tests and Android QA
Run Godot 4.5.2 headless import, simulation, Phase A and Phase B tests, main scene smoke test, Android debug export. CI workflow includes tests on PR.
Measure on Huawei P30 with headphones/speaker: at 1×/2×/4× and paused, pan/zoom, 1500 citizens; verify sound not rushing at accelerated time and check frame time, allocations, RAM, latency and no duplicate or offscreen events. No measured performance or verified Android build yet.

## Pending production work
- Merge/rebase Phase A and B onto the current construction/era/modern UI branches after ownership review.
- Emit real work contact markers from advanced construction job pipeline; inspect actions, unload timing and interruption rules.
- Connect actual rainfall, wind and lightning states from a weather model when merged.
- Replace placeholder procedural sounds with properly licensed, named recordings (asset manifest with source, attribution, redistribution status, sample peak and duration); define seamless ambient loops with a low-number persistent soundscape mixer.
- In-game audio settings panel, sample mixing quality controls and accessibility options.
