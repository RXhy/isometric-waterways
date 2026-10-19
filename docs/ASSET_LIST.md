# Asset List — WATERWAYS (MAGE 12)

Every asset the game needs, based on the placeholders already in the project.

## General rules

- **Style:** pixel art, isometric **32×16** tiles (the tile image is 32×32 including its side walls).
- **Format:** transparent PNG. In Godot, set the import filter to *Nearest* (no blur).
- **How to replace:** as long as the **file name and size stay the same**, just **overwrite the placeholder file**. The new asset shows up in the game with no code changes.
- **Sprite size changed?** That is fine. Adjust its position with `offset` in the matching scene (`scenes/*.tscn`).
- All paths below are relative to the project folder (`res://`).

**Priority:** **Required** = must exist at submission · **Important** = strongly recommended · **Optional** = if time allows

---

## Artist 1 — Environment & UI

### Tiles

| Asset | File | Size | Priority | Notes |
|---|---|---|---|---|
| Ground (dry, near water, yard) | `assets/Tiles/terrain_tiles.png` | 160×128 (5×4 tiles) | Required | Already exists, needs polish. Row 0: dry · rows 1–2: near water · row 3: yard around buildings |
| Dry canal & road | `assets/Tiles/tileset_iso_waterways.png` | 160×32 (5 tiles) | Required | Column 1 = dry canal, column 4 = road |
| Animated water | `assets/water/water_flow.png` | 128×320 (4 frames × 10 rows) | Required | See the row order below |
| Water edge foam | `assets/water/water_edge.png` | 128×128 (4×4 grid) | Required | 15 side combinations, explained below |
| Cliff wall | *(new)* | 32×32 | Optional | Makes elevation differences clearer |

**Row order of `water_flow.png`** (each row has 4 frames going right, each frame 32×32):

| Row | Content | Animation speed |
|---|---|---|
| 0 | Still water (lake, puddle) | 3 fps |
| 1 | Slow current toward upper-left ↖ | 6 fps |
| 2 | Slow current toward upper-right ↗ | 6 fps |
| 3 | Slow current toward lower-left ↙ | 6 fps |
| 4 | Slow current toward lower-right ↘ | 6 fps |
| 5–8 | Fast current, same direction order as rows 1–4 | 12 fps |
| 9 | Shallow water / advancing water front (foamy) | 4 fps |

Animation speed can be changed in `assets/water/water_flow_source.tres` (Inspector → animation speed).

**`water_edge.png` grid:** the tile position is the sum of the bits of the sides that get foam.
Bits: **1** = upper-left side, **2** = upper-right, **4** = lower-right, **8** = lower-left.
Column = value % 4, row = value ÷ 4. Example: foam on upper-left + lower-right = 1 + 4 = 5 → column 1, row 1. The value-0 tile (top-left of the grid) is left empty.

### Map objects

| Asset | File | Size | Priority | Notes |
|---|---|---|---|---|
| Bridge | `assets/placeholder/jembatan.png` | ~25×13 | Required | Currently one direction. Needs **two directions** (↗↙ and ↖↘) |
| Tile cursor | `assets/placeholder/ui/cursor_tile.png` | 32×16 | Important | White highlight outline; the game sets the colour (green = allowed, red = not allowed) |
| Info layer overlay | `assets/placeholder/overlay_tiles.png` | 256×16 (8 tiles) | Optional | Tiles 0–3: elevation · tiles 4–7: water depth (shallow → deep) |

### UI

| Asset | File | Size | Priority | Notes |
|---|---|---|---|---|
| HUD panel | `assets/placeholder/ui/panel.png` | 24×24 | Required | 9-slice, 5 px margin |
| Tool card — normal | `assets/placeholder/ui/card.png` | 24×24 | Required | 9-slice, 5 px margin |
| Tool card — hover | `assets/placeholder/ui/card_hover.png` | 24×24 | Required | 9-slice, 5 px margin |
| Tool card — selected | `assets/placeholder/ui/card_selected.png` | 24×24 | Required | 9-slice, 5 px margin |
| Stock badge | `assets/placeholder/ui/badge.png` | 10×10 | Required | 9-slice, 3 px margin |
| Progress bar (background & fill) | `assets/placeholder/ui/bar_bg.png`, `bar_fill.png` | 12×12 | Required | 9-slice |
| Building water-timer ring | `assets/placeholder/ui/ring_under.png`, `ring_progress.png` | 18×18 | Required | Draw in white/grey; the game sets the colour (blue/orange/red) |
| Control icons (7) | `assets/placeholder/ui/ic_pause.png`, `ic_play.png`, `ic_fast.png`, `ic_layers.png`, `ic_star.png`, `ic_ruin.png`, `ic_arrow.png` | 16×16 | Required | Pause, play, fast, layers, points, destroyed buildings, forecast arrow |
| Tool icons (5) | `assets/placeholder/icons/jembatan.png`, `bor.png`, `bendungan.png`, `spillway.png`, `kincir.png` | 48×48 | Required | Match the style of the icons in `assets/Icon/` |
| Main menu panel | `assets/placeholder/ui/menu_panel.png`, `menu_dialog.png` | 24×24 | Important | 9-slice |
| Main menu decoration | `assets/placeholder/ui/menu_divider.png` (8×2), `menu_marker.png` (24×6) | — | Important | Divider line & selected-item marker |
| **WATERWAYS logo** | *(new)* | ~200×60 | Required | For the main menu, thumbnail and video |

### Promotion

| Asset | Priority | Notes |
|---|---|---|
| Submission thumbnail / poster | Important | Logo + screenshot of the final build (Oct 15–16) |

---

## Artist 2 — Buildings, Characters, VFX, Audio, Video

### Buildings & facilities

| Asset | File | Current size | Priority | Notes |
|---|---|---|---|---|
| House | `assets/placeholder/rumah.png` | 24×31 | Required | The bottom point of the sprite = centre of the tile |
| Farm | `assets/placeholder/ladang.png` | 24×16 | Required | Flat, covers the tile |
| Ruins | `assets/placeholder/reruntuhan.png` | 24×15 | Required | Destroyed version of a house/farm |
| Drill rig | `assets/placeholder/sumur_bor.png` | 20×30 | Required | |
| Dam | `assets/placeholder/bendungan.png` | 24×23 | Required | Must look like it can span a canal |
| Spillway | `assets/placeholder/spillway.png` | 24×18 | Required | Drain channel at the water's edge |
| **Water Wheel (animated)** | `assets/placeholder/kincir.png` | 112×30 (4 frames × 28×30) | Required | 4–6 frames is fine. If the frame count changes, adjust the SpriteFrames in `scenes/kincir.tscn` (node Wheel, animation "putar") |

### Characters & tutorial

| Asset | Size | Priority | Notes |
|---|---|---|---|
| Engineer character portrait | ~64×64 | Important | 2–3 expressions: neutral, happy, worried |
| Dialogue box | 24×24 (9-slice) | Important | Artist 1 can do this if Artist 2 is full |

### VFX

| Asset | File | Priority | Notes |
|---|---|---|---|
| Raindrop | `assets/placeholder/hujan.png` (1×6) | Important | Particle; can be a bit bigger |
| Warning icon above buildings | `assets/placeholder/peringatan.png` (9×9) | Important | Shown when a building is at risk |
| Drought effect | *(new)* | Optional | Currently just a screen tint; could add dust/cracks |

### Audio (freely licensed)

| Type | Content | Priority |
|---|---|---|
| Music | 1 menu track + 1–2 gameplay tracks (looping) | Required |
| Tool SFX | Dig, fill, level, place facility, place bridge | Required |
| Game SFX | UI click, new building appears, building at risk, building destroyed, new day, win, lose | Required |
| Ambience | Flowing water, rain, drought wind, water wheel turning | Important |

**Record the source and license of every audio file.** The credits list must be included at submission.

### Video & documents

| Asset | Priority | Notes |
|---|---|---|
| Gameplay footage + trailer/demo | Required | From the final build (Oct 15–17) |
| Asset credits & license list | Required | Oct 16 |

---

## Already final (no need to redo)

- Tool icons: `assets/Icon/gali.png`, `ratakan.png`, `timbun.png`
- Weather icons: `assets/Icon/cerah.png`, `kemarau.png`, `rain.png`, `berawan.png`
- `assets/Tiles/terrain_tiles.png` (may be polished)

## Related deadlines (from the team timeline)

| Date | Target |
|---|---|
| Oct 10 | All features exist (placeholders still allowed) |
| Oct 13 | **All final assets delivered** |
| Oct 14 | Feature freeze |
| Oct 17 | Final build & video |
| Oct 18 | Submit (1-day buffer before the official Oct 19 deadline) |
