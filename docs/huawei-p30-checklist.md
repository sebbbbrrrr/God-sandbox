# Huawei P30 testing checklist

1. Back up any valuable `world.json` before installing. This is a debug APK. The existing workflow generates a new debug key on each run, so Android may require uninstalling the previous build; uninstalling removes app data. Production signing is unchanged in scope and not set up here.
2. Open the game, confirm textured land, pine forests, water and two settlement capitals. Zoom in to see sharp pixels and roof/wall detail. Pan to coasts and hills.
3. Select Raise, Forest and Ocean in turn. Drag quickly with each brush size, including diagonally across chunk boundaries. Confirm continuous paint, immediate shoreline updates, visible brush preview and no stale trees.
4. With a terrain brush selected, place two fingers, pan and pinch. Lift one finger and move the remaining finger: it must not resume painting. Release both, then paint again.
5. Choose Hand and pan with one finger. Switch between Hand and editing several times. Check that the indicated tile follows the raised surface.
6. Spawn citizens, burn nearby terrain, then bless survivors. Confirm fire damage, restored health, and terrain changes. Watch settlement growth at 4× speed for at least 30 seconds.
7. Pause and resume. Cycle 1×/2×/4×. Background the app, reopen, then force-stop/relaunch. Confirm terrain, populations and terrain elevation persist.
8. Test at widest, medium and closest zoom for 5 minutes each. Record actual FPS, frame spikes, temperature and memory with Android profiling tools if available. Desktop software-GL measurements are not Huawei P30 measurements.

Physical-device launch, GPU/driver compatibility, sustained FPS, thermal behaviour and Android lifecycle saves still need this device check.
