# WATERWAYS — Water, Canal, Road & Ground Tileset

This document explains how the game picks water, canal and road tiles (latest version on branch `feature/core-gameplay`), and the plan to switch the ground texture to **v3**.

Inspector group names such as "Tileset air & jalan" and "Animasi jalan" are Indonesian in the code; they are kept as-is here, with the English meaning in parentheses.

---

## 1. Tile sources

| Source ID | File | Content |
|---|---|---|
| 0 | `assets/Tiles/terrain_tiles_v3.png` | Land, 5 columns × 4 rows: row 0 dry, rows 1–2 grass, row 3 yard |
| 1 | `assets/Tiles/tileset_iso_waterways.png` | Old tiles (used only when `use_tileset_v2` is turned off) |
| 2 | `assets/water/water_flow_source.tres` | Old animated water (used only when `use_tileset_v2` is turned off) |
| **3** | **`assets/Tiles/tilesset_water_road.png`** | Natural water, dug canal, road (32 px grid) |
| **4** | **`assets/Tiles/waterflow.png`** | Water flow animation (4 frames × 128 rows), drawn on top of water/canal tiles |

Source 3 is **not stored in `world.tscn`**. When the game starts, `world.gd` → `_build_v2_source()` registers it in the TileSet, complete with 4 elevation variants (alternative tiles 0–3). The offset and colour of each elevation copy the ground tiles. An artist only needs to overwrite the PNG with the same size and layout.

### Layout of `tilesset_water_road.png`

| Rows | Content | Columns |
|---|---|---|
| 0–2 | Natural water, **brown** lip (next to dry ground) | 9 lake-edge shapes |
| 3–5 | Natural water, **green** lip (next to grass) | 9 shapes |
| 6–8 | Natural water, **dark green** lip (next to dark grass) | 9 shapes |
| 10–12 | **Brick** dug canal | 11 junction shapes |
| 13–15 | **Stone** dug canal | 11 junction shapes |
| 17 | Road | 11 junction shapes |

Each group of 3 rows is in order: **dry → shallow → full**.

---

## 2. How a tile is chosen (`world.gd` → `v2_atlas(cell)`)

Called by `water_sim.gd` every time a cell's appearance is refreshed.

### 2.1 4-side bitmask

The game looks at the **4 edge neighbours** of the cell (not the corners/diagonals) and builds a bitmask:

| Side | ↖ upper-left | ↗ upper-right | ↙ lower-left | ↘ lower-right |
|---|---|---|---|---|
| Bit | 1 | 2 | 4 | 8 |

The mask decides the tile **column**. The water condition decides the **row**.

### 2.2 Natural water (WATER cells from the map)

- **Mask** = the sides that border **land** (not water/canal).
- **Column** (table `LAKE_COL`):

| Land on side | Column | Shape |
|---|---|---|
| none | 8 | middle of the lake |
| ↖ | 1 | upper-left edge |
| ↗ | 3 | upper-right edge |
| ↙ | 4 | lower-left edge |
| ↘ | 6 | lower-right edge |
| ↖ + ↗ | 2 | top corner |
| ↙ + ↘ | 5 | bottom corner |
| ↖ + ↙ | 0 | left corner |
| ↗ + ↘ | 7 | right corner |
| opposite sides / 3 / 4 sides | nearest tile | *not in the sheet* |

- **Lip colour group**: from the class of the land next to it. Dry ground → rows 0–2, grass near water → 3–5, dark grass → 6–8.
- **Water level**: depth < `wet_threshold` (0.06) → **dry**; < `v2_full_depth` (0.3) → **shallow**; otherwise **full**. During a drought the lake visibly shrinks.
- Water outside the simulation area is always shown full.

### 2.3 Dug canal (CANAL cells)

- **Mask** = the sides adjacent to **a canal or water**, plus **one link to a building**.
  - Each building has only one "entry" canal (`canal_link()`): the canal on the side of the building with the fewest links (preferring canal ends).
- **Column** (table `LINK_COL`):

| Connected to | Column | Shape |
|---|---|---|
| ↗ + ↘ | 0 | bend |
| ↙ + ↘ | 1 | bend |
| ↖ + ↘ | 2 | straight ↘ |
| ↗ + ↙ | 3 | straight ↗ |
| ↖ + ↗ | 4 | bend |
| ↖ + ↙ | 5 | bend |
| all except ↖ | 6 | T-junction |
| all except ↙ | 7 | T-junction |
| all except ↗ | 8 | T-junction |
| all except ↘ | 9 | T-junction |
| all | 10 | crossroads |
| 1 side / isolated | 2 or 3 | straight (*dead-end tile is not in the sheet*) |

- **Row**: `10 + canal_style × 3 + water level` (brick = 0, stone = 1).

### 2.4 Road (ROAD cells)

- **Mask** = the sides adjacent to a road / bridge / road still queued for construction.
- If it is a dead end (≤ 1 link), the sides adjacent to a **building** are added.
- **Column**: the same `LINK_COL` table as canals. **Row**: 17.

### 2.5 Flooded land

Lake-middle tile (column 8), shallow level.

### 2.6 When it is recomputed

- Whenever a cell changes (`set_base` → `water.refresh_cell`): that cell + its 4 neighbours + the cells around neighbouring buildings.
- When a new building appears (`building_manager._spawn`).
- Every 0.1 seconds (`refresh_all`) for water-level changes.

### 2.7 Animation

- **New road**: cells appear one by one from the old road toward the building (Roads → group *Animasi jalan*, "Road animation").
- **Dig**: after a click/drag the shovel use is deducted immediately, then the canal "drops" into place cell by cell following the drag order (Node2D → `dig_step_delay`, `dig_drop_time`, `dig_drop_height`).
- The animation sprites follow the y-sort of the `World` layer, so they are covered by ground in front of them exactly like real tiles.

### 2.8 Inspector settings (Node2D → group *Tileset air & jalan*, "Water & road tileset")

| Property | Default | Purpose |
|---|---|---|
| `use_tileset_v2` | on | Turn off to go back to the old tiles + animated water |
| `water_road_texture` | `tilesset_water_road.png` | Sheet texture |
| `canal_style` | 0 | 0 brick, 1 stone |
| `v2_full_depth` | 0.3 | Depth limit for the "full" tile |
| `v2_top_shift` | 0 | Vertical shift of water/road tiles relative to ground tiles (0 = aligned, see §3) |
| `v2_canal_sort_boost` | 0 | 0 = canal level with the ground |

---

## 2.9 Water flow animation (`waterflow.png`)

Sheet of 128 × 4096 px: **4 columns = 4 animation frames**, **128 rows = shapes**. Built at runtime by `world.gd` → `_build_flow_source()` as source 4, then drawn on the `WaterFlow` layer (child of `World`, follows y-sort) right above the water/canal tile. Alternatives 0–3 (elevation) copy the `texture_origin` and modulate of the ground tile, the same as source 3.

| Rows (1–128) | Content | Used when |
|---|---|---|
| 1–9 / 10–18 | Natural water, still, 3/4 / full, 9 shapes (column order `LAKE_COL`) | Standing water |
| 19–29 / 30–40 | Canal, still, 3/4 / full, 11 shapes (column order `LINK_COL`) | Standing water |
| 41 | Empty | — |
| 42–61 / 62–81 | Natural water, straight flow, 3/4 / full: 5 shapes (columns 1, 3, 4, 6, 8) × 4 directions | Water flowing along a straight edge / lake middle |
| 82–85 / 86–89 | Straight canal 3/4 / full: upper-left, lower-right (column 2), upper-right, lower-left (column 3) | Water flowing in a straight canal |
| 90–97 | Natural water corner swirl (columns 0, 2, 5, 7), alternating 3/4 then full | Water flowing at a corner |
| 98–105 | Canal bend swirl (columns 0, 1, 4, 5) | Water flowing at a bend |
| 106–113 | Canal T-junction swirl (columns 6–9) | Water flowing at a T-junction |
| 114–115 | Canal crossroads swirl (column 10) | Water flowing at a crossroads |
| 116–128 | Reserved (empty) | — |

The order of the 4 directions in each shape: **upper-left, lower-right, upper-right, lower-left**.

Selection rules (`world.gd` → `flow_row()`):
- Water level **dry** → no animation. **Shallow** → 3/4 rows. **Full** → full rows.
- The direction and "flowing or not" come from `water_sim.flow_dir()` (net flow above `still_flow`). Water outside the play area is always still.
- A straight canal picks a direction along its axis (an ↖↘ canal only uses upper-left/lower-right).

Settings (Node2D → group *Tileset air & jalan*): `show_water_flow` (on/off), `waterflow_texture`, `waterflow_fps` (4), `waterflow_random_start` (false = all cells in sync, so the flow lines connect between cells).

## 3. Ground texture v3 (already in use)

| File | Top surface starts at row | Block side thickness |
|---|---|---|
| `terrain_tiles.png` (old) | 13 | 3 px |
| `terrain_tiles_v2.png` | 13 | 3 px |
| **`terrain_tiles_v3.png`** (in use) | **6** | **10 px** |
| `tilesset_water_road.png` | 6 | 10 px |

Ground v3 and the water/road tileset have the same geometry, so they line up with no shift.

What changed when moving to v3:
1. `world.tscn`: source 0 uses `terrain_tiles_v3.png`. The value of each alternative tile (= elevation level):

| Alternative | Elevation | `texture_origin` Y | Modulate (slider **I** from #ffffff; Godot computes in linear space: colour = srgb(linear × 2^I)) |
|---|---|---|---|
| 0 | Shoreline | -2 | I = -1.5 → #a0a0a0 (0.629) |
| 1 | Low plain | 2 | I = -1 → #bcbcbc (0.735) |
| 2 | Mid plain | 6 | I = -0.5 → #dbdbdb (0.858) |
| 3 | High plain | 10 | I = 0 → #ffffff |

   Water, canal and road tiles (source 3) **copy these values automatically** from the ground tiles when the game starts (`_build_v2_source`), so they always match and the textures join up. If the values above are changed in the editor, the water/road tiles follow.
2. `world.gd`: `v2_top_shift` = **0**.
3. `tools/build_menu_map.gd` → `V2_TOP_SHIFT = 0`, then `scenes/menu_map.tscn` is regenerated (it picks up v3 automatically from the TileSet of `world.tscn`).

If an artist replaces the ground image, overwrite `terrain_tiles_v3.png` with the same size and layout (5 × 4 tiles, 32 × 32, top surface at row 6).

## 4. Tiles that don't exist yet (requests to the artist)

- **Dead-end** canals & roads (1 link) and **isolated** ones (0 links).
- Lake edges with **two opposite sides** (a 1-cell-wide river), **three sides**, and **inner corners**.
- The purpose of the **stone** canal (rows 13–15) is not decided yet, for example for canals on high plains or ones connected to a Spillway.

When new tiles are added, just tell us their position in the sheet, then the `LAKE_COL` / `LINK_COL` tables in `world.gd` get updated.
