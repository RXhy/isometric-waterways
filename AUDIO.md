# WATERWAYS — Audio List

All audio is played by the **`Audio`** autoload (`scenes/audio_manager.tscn` + `audio/audio_manager.gd`). Files and volumes are set in that scene's Inspector. Buses: music goes to `Music`, everything else to `SFX` (sliders in the Settings menu).

## Installed audio

| File | Plays when | Notes |
|---|---|---|
| `music/bgm_menu.mp3` | Main menu (looped) | Fades out when entering the game |
| `music/jingle_win.mp3` | Game ends in a **win** (≥ 1 star) | Once |
| `music/jingle_lose.wav` | Game ends in a **loss** | Once |
| `ambience/amb_water.mp3` | During play (looped) | Volume follows the **Water Flow** % (still faintly audible at 0%) |
| `ambience/amb_rain.wav` | **Rain** weather (looped) | Fades in/out when the weather changes |
| `ambience/amb_wind.mp3` | Sunny (quiet) and **drought** (louder, pitch 0.85) | Looped |
| `sfx/ui_click.ogg` | **Every button** press (menus, tool cards 1–7, pause, tutorial) | Automatic for all Buttons |
| `sfx/ui_error.wav` | Clicking an action that is not allowed (red tooltip: no stock or shovel uses, invalid tile) | |
| `sfx/tool_dirt.wav` | Dig (per tile during the animation), Level (higher pitch when raising, lower when lowering), Fill (low pitch) | Random pitch ±8%, max ~14 per second |
| `sfx/place_wood.wav` | Placing a bridge or water wheel. Removing a bridge = higher pitch | |
| `sfx/place_stone.wav` | Placing a drill well or spillway. Removing a facility = higher pitch | |
| `sfx/bld_warning.wav` | A building has just become **at risk** | At most once per 1.2 seconds |
| `sfx/bld_destroyed.mp3` | A building is destroyed | |
| `sfx/day_new.wav` | A new day starts (day 2 onward) | |
| `sfx/land_expand.mp3` | New land unlocked (days 10, 19, 28, 37) | |

Intentionally unused: `bgm_game`, `ui_notify`, `road_tile`, `water_splash`, `water_reach`, `weather_change`.

## Adding or replacing audio
1. Put the file in `assets/audio/music|ambience|sfx`.
2. Open `scenes/audio_manager.tscn` and fill the matching slot in the Inspector.
3. For a new sound: add `@export var name: AudioStream` in `audio/audio_manager.gd`, then call `Audio.play("name")` from code.

---

## Audio sources

**Safest license: CC0** (free to use, no credit needed). **CC-BY** is also fine as long as credit is given. **Avoid CC-BY-NC** (non-commercial) and files with unclear licenses.

| Source | License | Good for | Notes |
|---|---|---|---|
| [Kenney – Audio](https://kenney.nl/assets/category:Audio) | CC0 | UI, clicks, impacts, jingles | Relevant packs: *Interface Sounds*, *UI Audio*, *Impact Sounds*, *RPG Audio*, *Music Jingles*. One pack gives many files. |
| [Freesound](https://freesound.org) | Mixed (CC0 / CC-BY / CC-BY-NC) | Water, rain and wind ambience, digging | Filter by **License: Creative Commons 0** in the search results. A free account is needed to download. |
| [OpenGameArt](https://opengameart.org/art-search-advanced) | Mixed (CC0 / CC-BY / GPL) | Looping game music, SFX | Set *Art Type* = Music / Sound Effect. Check the license on each page; example pack: [Interface Sounds](https://opengameart.org/content/interface-sounds). |
| [Pixabay Music](https://pixabay.com/music/) & [Sound Effects](https://pixabay.com/sound-effects/) | Pixabay Content License (free, no credit) | Menu/gameplay music, ambience | Search "relaxing", "lofi", "nature ambient", "stream". |

---

## Technical specifications

- **Format**: `.ogg` for music and ambience (tick **Loop** in Godot's Import tab), `.wav` for short SFX (< 1 second).
- **Loudness**: music around -16 LUFS, SFX peaking at -1 dB. Music must be quieter than SFX so action feedback stays audible.
- **Trim leading silence** from SFX files so the sound plays right on click.
- **Loops must be seamless**: no click at the join (check in Audacity: a very short Fade In/Out, or cut at a zero crossing).
- Repeated sounds (digging, roads, water entering a canal) get a random pitch and are limited in code (about ±3 per second).
- The `Music` and `SFX` buses exist in `default_bus_layout.tres` and are tied to the volume sliders in the Settings menu.

---
