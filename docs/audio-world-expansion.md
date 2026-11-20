# God Sandbox — Audio Expansion / Contact Timing, Environment and Civilisations

**Base:** `feature/audio-construction-integrated` (PR #28). This is a stacked integration, **not** an independent merge to `main`.

## Implemented

1. **Audio contact timing.** `construction_audio_bridge.gd` observes successful authoritative building, gathering and delivery changes, queues a bounded audio marker, and `flush_contacts()` plays it only when the exact work animation contact beat (2.1 rad at 4.5 rad/s including per-worker phase offset) is crossed. The same action cannot replay in subsequent visual frames; sound never grants additional labour/materials. At 1× this uses natural real-time animation clock; 2× and 4× preserve accelerated work display, but the mixer itself never pitches up.
2. **Weather.** `world_audio_director.gd` reads **existing** `world_renderer.weather` (visual-only deterministic weather). It plays wind and rain onset cues only on threshold transitions and a storm-entry thunder rumble. It does **not** claim a lightning-strike system exists; no physical weather damage or gameplay RNG is introduced.
3. **Eleven civilisational age categories.** Events `civilisation.early_stone` through `civilisation.far_future` are registered. The director scans nearby living people with real playable occupations and nearby completed buildings; it selects the highest *demonstrated locally active* role era, not the calendar year or a fictional future population. If later occupations aren't implemented/active, future soundscapes correctly remain silent.
4. **Mobile settings.** The existing `GodSandboxHUD` settings popup now includes master volume, mute, and battery/balanced/high playback quality. Signals connect to the persistent `audio_manager.gd` preferences, which never touch game saves.
5. **SFX pack.** Ten original short authored synthetic WAV files are available from PR #28, covering actual work, selected footsteps, UI and powers. Other sounds retain deterministic runtime synthetic fallback. This is **not** the requested professional field-recording library and does not imply one has been licensed.

## Verification and limitations

- Included regression coverage for footstep culling, real extraction transitions, contact beat non-replay, 11 age mappings, resident/building evidence, weather transition deduplication, UI audio preferences through the integrated scene and WAV imports.
- Audio events are generated independently from simulation RNG, inventory and physics; no save-schema changes.
- Individual impact timing is constrained by authority and animation contact, **not** by an authored bespoke sprite-sheet event track. If an authoritative job resolves before a visible work gesture can play, contact may be delayed or omitted.
- Weather ambience currently consists of short onset cues; sustained rain/wind loops, layer crossfades, per-material acoustics, and measured loudness/latency are still pending.
- The 11-stage ambience catalog is fully registered and gates against actual active roles, but many advanced occupations are flagged non-playable in the currently integrated occupation definitions, so the later stages are intentionally silent until technologies are implemented.
- No externally sourced recordings are included. Professional licensed audio still requires a source/redistribution manifest, proof of rights, and subjective mix review.
- The integrated feature branch may need conflict resolution against other concurrent UI, settlement founding, high-resolution art and other systems branches.

## Android validation

The branch-scoped workflow `.github/workflows/audio-construction-android.yml` is configured to fetch Godot 4.5.2, import all audio assets, execute existing UI/construction/road-trade plus Phase A/B/audio sample/construction-contact/world expansion tests, smoke-test the main scene, export a **debug-signed APK**, verify APK ZIP and signature, and upload the resulting artifact.

**No passing execution is certified by these source changes.** Check the GitHub Actions run page for a green build; the GitHub connector's commit-run reader only exposes PR-triggered runs and is not authoritative for push-only workflows. On Huawei P30 manually confirm speaker/headphone sound, muted state after restart, source-dependent footsteps, 1×/2×/4×, no audio while paused, actual weather transitions, battery/performance, and work contact latency. Do not distribute an APK without these checks.

### Further production tasks

Replace synthetic material impacts/ambiences with cleared high-quality recordings, create 3–5 variations per common tool/surface event, implement persistent loop crossfades and audio focus controls, connect additional weather incidents and future-era machinery only when they exist in the simulation, and profile voice count/mobile CPU budget with target hardware.