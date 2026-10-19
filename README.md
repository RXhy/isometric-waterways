<div align="center">

# WATERWAYS

**Guide the water. Save the city.**


![Gameplay: digging a canal to a thirsty farm](docs/gameplay.gif)

</div>

<!-- Trailer: drag WATERWAYS_Trailer_720p.mp4 into this README in the GitHub web editor and paste the generated link here. -->

---

## About the game

The city grows by itself: every day new houses and farms appear, and every one of them needs water. You are the canal planner. Dig canals from rivers and lakes, reshape the terrain so water can flow downhill, and place facilities before the weather turns. Survive 45 days, earn stars, and don't let too many buildings dry out or drown.

## Features

- **Drag-to-build canals.** Press, drag and release. Paths follow the isometric grid in a straight line with one turn, with a green/white/red preview before anything is spent (inspired by Mini Motorways).
- **Real water simulation.** Water flows to lower ground, spills over canal banks, evaporates and soaks away. Elevation matters: water never climbs on its own.
- **Terrain tools.** Level the ground down or up (4 elevation levels) and fill canals back in, sharing a daily shovel budget.
- **Facilities.** Bridges carry canals across roads, Drill Wells give drought-proof water, Spillways protect against floods, and Water Wheels pump water uphill and generate bonus points.
- **Weather with a forecast.** Sunny, Drought and Heavy Rain. Tomorrow's forecast decides which facility you receive today, so you must read the weather and prepare.
- **A city that grows.** New buildings spawn every day, roads connect automatically, and the playable land expands on days 10, 19, 28 and 37.
- **Stars and consequences.** Score from watered buildings, daily bonuses and working bridges. 1 star at 3500, 2 at 5000, 3 at 8500. Lose if more than 8 buildings are destroyed.
- **Polish.** Animated flowing water, elevation and water-depth overlays, in-game tutorial, pause and settings menu, audio mixer, hide-UI mode (`H`).

## How to play

A building is watered when a wet canal or water source is **directly beside or in front of it** (one of its 4 edge neighbours, not diagonal) and is at the same height or higher. Every building keeps a water reserve: when it runs dry, or floods, it becomes *at risk* and is eventually destroyed.

### Controls

| Input | Action |
|---|---|
| `1` – `7` or click the toolbar | Select tool: Dig, Level, Fill, Bridge, Drill Well, Spillway, Water Wheel |
| Left drag | Use the shovel tools along a path (release to confirm) |
| Right drag (Level) | Raise terrain instead of lowering it |
| `Esc` / right click while dragging | Cancel the drag / open the pause menu |
| Mouse wheel | Zoom toward the cursor |
| Middle-mouse drag, `WASD`, arrow keys | Pan the camera |
| `Space` | Pause |
| `H` | Hide / show the UI |

## Run it

1. Install **Godot 4.6** (standard build, not .NET).
2. Clone this repository and open `project.godot` in Godot.
3. Press **F5**. The game starts at the splash scene and flows into the main menu.

The project targets 1920×1080 fullscreen with a 640×360 pixel-art viewport.

## Tuning without touching code

Gameplay numbers are exposed in the Inspector (`world.tscn` root, plus the Score, Weather and Facilities nodes): day length, number of days, shovel budget, weather schedule and severity, star thresholds, damage quota, stock per forecast and more. `supply_diagonals` switches the watering rule between 4 and 8 neighbours.

## Project structure

| Path | Contents |
|---|---|
| `world.gd`, `world.tscn` | Map, camera, tools, drag preview, land expansion |
| `water_sim.gd` | Water flow, evaporation, wells, spillways, water wheels, tile visuals |
| `weather_manager.gd` | Weather schedule, drought ramp, rain surge, forecast |
| `building_manager.gd`, `building.gd` | Spawning, water reserve, threat and destruction |
| `road_manager.gd`, `facility_manager.gd` | Roads and bridges, facility stock and placement |
| `score_manager.gd` | Points, daily bonus, stars |
| `balance_log.gd` | Automatic playtest logging (`playtest_logs/`) |
| `ui/` | HUD, menus, splash, loading, tutorial, settings |
| `audio/`, `assets/audio/` | Audio manager and sound files |
| `docs/` | Design and asset documents: `mechanic.md`, `art-pipeline.md`, `audio.md`, `ASSET_LIST.md` |
| `CREDITS.md` | Credits and licenses |

For the full rules and formulas see [`docs/mechanic.md`](docs/mechanic.md).

## Credits

Made by team **Ayam Renang** for **MAGE 12** (GameDev, Institut Teknologi Sepuluh Nopember).

- Engine: [Godot](https://godotengine.org)
- UI font: Chakra Petch (SIL Open Font License)
- Third-party audio and art credits are listed in [`CREDITS.md`](CREDITS.md)
