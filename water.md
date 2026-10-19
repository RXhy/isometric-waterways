# Water Appearance Guide — WATERWAYS

How to replace and tune the look of the water (flow animation and edge foam) **through tiles**, without touching code.

> The water animation **does not use a shader**. It is all ordinary tile animation in Godot's TileSet.
> The white border along the water's edge is not a render effect either. It is a **separate tile layer** holding foam.

---

## 1. Water animation — atlas source ID 2

### File locations

| File | Content |
|---|---|
| `assets/water/water_flow.png` | Animation image: **10 rows × 4 frames**, each frame **32×32 px** |
| `assets/water/water_flow_source.tres` | Animation settings. This is **source ID 2** in the TileSet of the `World` node (`world.tscn`) |

### Row order

| Row | Content | Default speed |
|---|---|---|
| 0 | Still water (lake, puddle) | 3 fps |
| 1 | Slow current ↖ (upper-left) | 6 fps |
| 2 | Slow current ↗ (upper-right) | 6 fps |
| 3 | Slow current ↙ (lower-left) | 6 fps |
| 4 | Slow current ↘ (lower-right) | 6 fps |
| 5–8 | Fast current, same direction order as rows 1–4 | 12 fps |
| 9 | Shallow water / advancing water front | 4 fps |

The code (`water_sim.gd`) picks a row from the flow direction and strength on each tile. So **do not change the row order or the frame size**, or the current will point the wrong way.

### Replacing the image (easiest way)

1. Redraw `water_flow.png` at the same size: **128×320 px** (4 frames × 10 rows).
2. Overwrite the old file. Godot re-imports it automatically and the game uses the new image right away.

Tips for artists:
- Each 32×32 frame holds a **diamond-shaped top surface** plus an **earth wall** below it, just like the tiles in `assets/Tiles/tileset_iso_waterways.png`.
- The last frame must blend smoothly into the first so the animation loops without a jump.
- The current pattern must connect to the neighbouring tile so a river looks like one continuous stream, not separate squares.

### Setting up the animation in the editor

1. Open `world.tscn` and select the **World** node.
2. In the bottom panel open the **TileSet** tab and pick **source ID 2 (water_flow)** in the left list.
3. Click the tile in the **first column** of the row you want to change. In the Inspector, under **Animation**:
   - **Speed**: animation speed (fps)
   - **Frames Count**: number of frames (currently 4)
   - **Columns**: leave at 0, meaning the frames run to the right
   - **Frame 0..N Duration**: length of each frame (relative)
4. **To add more frames**, for example 6:
   1. Widen the PNG to 6 × 32 = **192 px**.
   2. Set **Frames Count** to 6 on **every** row (0–9).

The speed of all rows can also be set directly in `water_flow_source.tres`.

### Alternative tiles 1–3

Every water tile has alternatives 0–3, one for each **elevation level**:
- `texture_origin`: raises the image by 4 px per level
- `modulate`: brightness per level (0.72 / 0.86 / 1 / 1.14)

Leave these alone unless you really want to change the water colour by height.

---

## 2. White border along the water's edge (edge foam)

### Where it lives

| Part | Location |
|---|---|
| Layer in the game | Node **`World/WaterEdge`** in `world.tscn` |
| Layer in the main menu | Node **`Ground/WaterEdge`** in `scenes/menu_map.tscn` |
| Image | `assets/water/water_edge.png`, a **4×4** grid of 32×32 tiles (128×128 px) |
| TileSet | `assets/water/water_edge_tileset.tres` |

In the game this layer is **filled automatically by code** (`water_sim.gd` → `_refresh_edge`) on every water side that borders land or a dry canal. So the tiles are not painted by hand one by one. What you change is the **image**, the **TileSet**, or the **layer node**.

### Layout of the `water_edge.png` grid

The tile position is the sum of the bits of the sides that get foam:

| Bit | Side |
|---|---|
| 1 | ↖ upper-left |
| 2 | ↗ upper-right |
| 4 | ↘ lower-right |
| 8 | ↙ lower-left |

- **Column** = value % 4, **row** = value ÷ 4.
- Examples:
  - Foam on ↖ only = 1 → column 1, row 0.
  - Foam on ↖ + ↘ = 1 + 4 = 5 → column 1, row 1.
  - Foam on all four sides = 15 → column 3, row 3.
- The value-0 tile (column 0, row 0) is left **empty**.

### Ways to change it

| What you want | How |
|---|---|
| **Change the foam style** | Overwrite `water_edge.png` with a new 128×128 image using the same grid layout. |
| **Fainter foam** | Select the `World/WaterEdge` node, then in the Inspector → **Visibility → Modulate** lower the **A** (alpha) value, for example to 120. |
| **Remove the foam entirely** | Turn off **Visible** on the `World/WaterEdge` node. The code keeps running but the foam is not shown. |
| **Different foam colour per elevation** | Open `water_edge_tileset.tres` (or the TileSet tab while the `WaterEdge` node is selected), pick the tile, then set **modulate** on alternatives 0–3. |

Make the same change in `menu_map.tscn` if you also want the main-menu map to follow. The image and TileSet are shared, so only the node settings (Visible / Modulate) need repeating there.

---

## 3. Bright lines inside the water

White or bright streaks **inside** the water surface are **not** edge foam. They are part of the current drawing in `water_flow.png`:
- **Rows 1–8:** current lines moving along the flow (more and brighter in the fast rows 5–8).
- **Row 9:** foam specks for shallow water / the water front.

To reduce or replace them, redraw the frames in the relevant row.

---

## 4. When each tile appears

These thresholds can be tuned in the Inspector of the **Water** node (`world.tscn`), group **"Tampilan arus"** (the group name is Indonesian in the code; it means "Flow display"):

| Property | Default | Meaning |
|---|---|---|
| `still_flow` | 0.012 | Flow below this value → **still** tile (row 0) |
| `fast_flow` | 0.06 | Flow above this value → **fast** tile (rows 5–8) |
| `shallow_depth` | 0.18 | Water shallower than this (not a natural source) → **shallow** tile (row 9) |
| `visual_interval` | 0.1 | Seconds between tile-choice updates (frame animation still runs every frame) |

---

## 5. Quick summary

| To change | File / node |
|---|---|
| Water animation image | `assets/water/water_flow.png` |
| Speed / number of frames | TileSet of the `World` node → source ID 2, or `assets/water/water_flow_source.tres` |
| Edge foam image | `assets/water/water_edge.png` |
| Fade / hide the foam | Node `World/WaterEdge` → Modulate / Visible |
| Water colour per elevation | Alternative tiles 0–3 in source ID 2 |
| When water is still / slow / fast / shallow | Node `Water` → group "Tampilan arus" (Flow display) |
