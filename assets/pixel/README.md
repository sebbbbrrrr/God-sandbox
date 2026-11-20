# Pixel asset collection

231 named regions in one 1024×1024 runtime atlas plus three 512×512 authoring atlases. Terrain regions are exactly 32×32 logical pixels. Sprite regions have trimmed binary alpha and a shared top-left light. All runtime textures use nearest filtering, no mipmaps and no VRAM compression.

| File | Contents |
| --- | --- |
| `sprite_atlas.png` | Unified runtime texture, avoiding texture switches across terrain, cliffs and props |
| `terrain.png` | 37 terrain variants: meadow, forest floor, dirt, ash, settlement earth, deep/shallow water, rock, mountain, sand |
| `objects.png` | Five pines; bushes, flowers, grasses, logs, stumps, rocks; hut, cottage, workshop, hall; both orientations of wood/stone bridges; fences, well, barrels, woodpile, sign; two citizens; cliff faces, corners and ledges; effects |
| `transitions.png` | Cardinal biome masks, shoreline masks, diagonal shore corners, rounded coastal cuts, three path shapes and contact shadows |
| `atlas.json` | Exact named regions consumed by `PixelAtlas` |

The source sheet is original image-generated artwork commissioned for this project. The packer (`tools/build_pixel_assets.py`) crops cells, applies binary pixel alpha, nearest sampling, restrained palette tints and deterministic transition geometry. `tools/source/source_sheet.png` preserves the selected source for reproducible packing. It is excluded from game exports. No third-party art was downloaded.

The bridges, extra settlement props and some effects are reusable assets; bridge placement and bridge simulation are not implemented. There are no debug placeholder textures. Terrain textures are opaque by design; object and overlay atlases have transparent backgrounds.

## Exact region inventory

### terrain

`meadow_0`, `meadow_1`, `meadow_2`, `meadow_3`, `forest_0`, `forest_1`, `forest_2`, `forest_3`, `dirt_0`, `dirt_1`, `dirt_2`, `dirt_3`, `ash_0`, `ash_1`, `ash_2`, `ash_3`, `earth_0`, `water_0`, `water_1`, `water_2`, `water_3`, `shallow_0`, `shallow_1`, `shallow_2`, `shallow_3`, `rock_0`, `rock_1`, `rock_2`, `rock_3`, `mountain_0`, `mountain_1`, `mountain_2`, `mountain_3`, `sand_0`, `sand_1`, `sand_2`, `sand_3`

### objects

`pine_0`, `pine_1`, `pine_2`, `pine_3`, `pine_4`, `bush`, `flower_bush`, `stump`, `rock_small`, `rock_medium`, `rock_tall`, `log`, `grass`, `flowers_white`, `flowers_gold`, `moss_rock`, `hut`, `cottage`, `workshop`, `town_hall`, `bridge_wood_h`, `bridge_wood_v`, `bridge_stone_h`, `bridge_stone_v`, `fence_h`, `fence_v`, `well`, `barrels`, `woodpile`, `sign`, `citizen_gold`, `citizen_rose`, `cliff_0`, `cliff_1`, `cliff_2`, `cliff_3`, `cliff_4`, `cliff_5`, `cliff_6`, `cliff_7`, `fire`, `blessing`, `ripple`, `reeds`, `grass_2`, `fern`, `ledge`, `cliff_corner`, `cliff_inner`, `cliff_outer`

### transitions

`meadow_edge_1`, `meadow_edge_2`, `meadow_edge_3`, `meadow_edge_4`, `meadow_edge_5`, `meadow_edge_6`, `meadow_edge_7`, `meadow_edge_8`, `meadow_edge_9`, `meadow_edge_10`, `meadow_edge_11`, `meadow_edge_12`, `meadow_edge_13`, `meadow_edge_14`, `meadow_edge_15`, `forest_edge_1`, `forest_edge_2`, `forest_edge_3`, `forest_edge_4`, `forest_edge_5`, `forest_edge_6`, `forest_edge_7`, `forest_edge_8`, `forest_edge_9`, `forest_edge_10`, `forest_edge_11`, `forest_edge_12`, `forest_edge_13`, `forest_edge_14`, `forest_edge_15`, `dirt_edge_1`, `dirt_edge_2`, `dirt_edge_3`, `dirt_edge_4`, `dirt_edge_5`, `dirt_edge_6`, `dirt_edge_7`, `dirt_edge_8`, `dirt_edge_9`, `dirt_edge_10`, `dirt_edge_11`, `dirt_edge_12`, `dirt_edge_13`, `dirt_edge_14`, `dirt_edge_15`, `ash_edge_1`, `ash_edge_2`, `ash_edge_3`, `ash_edge_4`, `ash_edge_5`, `ash_edge_6`, `ash_edge_7`, `ash_edge_8`, `ash_edge_9`, `ash_edge_10`, `ash_edge_11`, `ash_edge_12`, `ash_edge_13`, `ash_edge_14`, `ash_edge_15`, `earth_edge_1`, `earth_edge_2`, `earth_edge_3`, `earth_edge_4`, `earth_edge_5`, `earth_edge_6`, `earth_edge_7`, `earth_edge_8`, `earth_edge_9`, `earth_edge_10`, `earth_edge_11`, `earth_edge_12`, `earth_edge_13`, `earth_edge_14`, `earth_edge_15`, `rock_edge_1`, `rock_edge_2`, `rock_edge_3`, `rock_edge_4`, `rock_edge_5`, `rock_edge_6`, `rock_edge_7`, `rock_edge_8`, `rock_edge_9`, `rock_edge_10`, `rock_edge_11`, `rock_edge_12`, `rock_edge_13`, `rock_edge_14`, `rock_edge_15`, `shore_edge_1`, `shore_edge_2`, `shore_edge_3`, `shore_edge_4`, `shore_edge_5`, `shore_edge_6`, `shore_edge_7`, `shore_edge_8`, `shore_edge_9`, `shore_edge_10`, `shore_edge_11`, `shore_edge_12`, `shore_edge_13`, `shore_edge_14`, `shore_edge_15`, `shallow_edge_1`, `shallow_edge_2`, `shallow_edge_3`, `shallow_edge_4`, `shallow_edge_5`, `shallow_edge_6`, `shallow_edge_7`, `shallow_edge_8`, `shallow_edge_9`, `shallow_edge_10`, `shallow_edge_11`, `shallow_edge_12`, `shallow_edge_13`, `shallow_edge_14`, `shallow_edge_15`, `shore_corner_0`, `shore_corner_1`, `shore_corner_2`, `shore_corner_3`, `coast_cut_1`, `coast_cut_2`, `coast_cut_3`, `coast_cut_4`, `coast_cut_5`, `coast_cut_6`, `coast_cut_7`, `coast_cut_8`, `coast_cut_9`, `coast_cut_10`, `coast_cut_11`, `coast_cut_12`, `coast_cut_13`, `coast_cut_14`, `coast_cut_15`, `path_h`, `path_v`, `path_cross`, `contact_shadow`, `cliff_east`
