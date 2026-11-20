# Age I–V Architectural Differentiation

**Repo:** `sebbbbrrrr/God-sandbox`  
**Branch:** `feature/civilisation-architecture-ages-i-v`  
**Status:** Implementation and GL/Android validation required before merge.

## Visual architecture families

Five distinctive early-age styles now have 8 building archetypes each with 2 unique generated variants (80 new packed sprite regions on a 640 × 512 page).

| Local age | New architecture |
| --- | --- |
| I — Early Stone Age | lean-to, hide tent, branch hut, stone shelter, hearth circle, tool area, drying rack, communal canopy |
| II — Agricultural | wattle house, longhouse, granary, mud store, farmstead, tool area, pottery kiln, meeting lodge |
| III — Bronze | mudbrick house, courtyard house, granary, bronze foundry, market court, shrine, tool area, civic hall |
| IV — Iron/Classical | stone villa, courtyard house, tiled workshop, colonnade, market forum, barracks, tool area, bathhouse |
| V — Medieval | half-timber house, stone cottage, guildhall, watermill, market square, fortified tower, tool area, granary |

## Integration
- Earlier random `BUILDINGS` selection allowed medieval buildings at the start of civilisation. Settlement *decorative* architecture is now restricted to an age-appropriate family.
- Age derives from real local adopted capabilities through `construction.catalogue.local_age(world, nation)`; elapsed calendar years do not unlock it.
- Settlement centre artwork, toolmaking workshop, outlying scenery, grounds and props also change across ages.
- Physically constructed primitive shelters and worked timber huts keep primitive silhouettes throughout later history, preserving old buildings rather than magically upgrading them.
- Houses, inventory, citizen AI, terrain edits, saves, construction lifecycle and work animations are unchanged.
- Only affected cached town chunks are marked dirty when a visual age changes.
- Existing 330 regions and the 420 physical object atlas remain untouched; main sprite atlas grows to 410 metadata regions across 2 pages. The age-styled art is a separate second texture.
- At simulated ages VI–XI, the renderer temporarily uses Age V graphics until those eras receive their own art. This is explicitly a visual fallback, not loss of simulation technology.
- Decorative buildings do not unlock functional markets, metallurgy, guilds, barracks, mills or services. These remain governed by real game systems.

## Caveats
The first set consists of original code-generated pixel-art approximations, with eight archetypes per age. The final architectural art library should have deeper building footprints, climatic and geographic materials, place-specific styles, religion/culture variation, persistent renovation, and per-building actual type rules. Those should not be added as purely cosmetic simulation unlocks.

## Validation
`godot --headless --editor --path . --import --quit`
`godot --headless --path . --script res://tests/architecture_eras_test.gd`
`godot --headless --path . --script res://tests/universal_construction_test.gd`
`godot --headless --path . --script res://tests/construction_animation_test.gd`
`godot --headless --path . --script res://tests/physical_sprite_atlas_test.gd`

Run the game, compare early settlement screenshots at matched camera zoom and verify Linux GL and real Android performance before merging.
