# WATERWAYS — Daftar Audio

Semua audio diputar oleh autoload **`Audio`** (`scenes/audio_manager.tscn` + `audio/audio_manager.gd`). File dan volume diatur di Inspector scene itu. Bus: musik → `Music`, sisanya → `SFX` (slider di menu Pengaturan).

## Audio yang terpasang

| File | Diputar saat | Catatan |
|---|---|---|
| `music/bgm_menu.mp3` | Main menu (loop) | Berhenti pelan (fade) saat masuk game |
| `music/jingle_win.mp3` | Game selesai **menang** (≥ 1 bintang) | Sekali |
| `music/jingle_lose.wav` | Game selesai **kalah** | Sekali |
| `ambience/amb_water.mp3` | Selama main (loop) | Volume mengikuti % **Aliran Air** (tetap terdengar pelan di 0%) |
| `ambience/amb_rain.wav` | Cuaca **hujan** (loop) | Fade in/out saat cuaca berganti |
| `ambience/amb_wind.mp3` | Cerah (pelan) dan **kemarau** (lebih keras, pitch 0,85) | Loop |
| `sfx/ui_click.ogg` | **Setiap tombol** ditekan (menu, kartu alat 1–7, jeda, tutorial) | Otomatis untuk semua Button |
| `sfx/ui_error.wav` | Klik aksi yang tidak bisa (tooltip merah: stok/sekop habis, tile tidak valid) | |
| `sfx/tool_dirt.wav` | Gali (per petak saat animasi), Ratakan (naik pitch tinggi, turun pitch rendah), Timbun (pitch rendah) | Pitch acak ±8%, maks ~14×/detik |
| `sfx/place_wood.wav` | Pasang jembatan & kincir. Bongkar jembatan = pitch tinggi | |
| `sfx/place_stone.wav` | Pasang mesin bor & spillway. Bongkar fasilitas = pitch tinggi | |
| `sfx/bld_warning.wav` | Bangunan baru saja jadi **terancam** | Maks sekali per 1,2 detik |
| `sfx/bld_destroyed.mp3` | Bangunan hancur | |
| `sfx/day_new.wav` | Hari baru dimulai (hari 2 dst.) | |
| `sfx/land_expand.mp3` | Lahan baru terbuka (hari 10, 19, 28, 37) | |

Belum ada (sengaja tidak dipakai): `bgm_game`, `ui_notify`, `road_tile`, `water_splash`, `water_reach`, `weather_change`.

## Cara menambah / mengganti audio
1. Taruh file di `assets/audio/music|ambience|sfx`.
2. Buka `scenes/audio_manager.tscn`, isi slot yang sesuai di Inspector.
3. Untuk bunyi baru: tambah `@export var nama: AudioStream` di `audio/audio_manager.gd`, lalu panggil `Audio.play("nama")` dari kode.

---

## Sumber audio

**Lisensi paling aman: CC0** (bebas dipakai tanpa kredit). **CC-BY** juga boleh asal kredit dicantumkan. **Hindari CC-BY-NC** (non-komersial) dan file tanpa lisensi jelas.

| Sumber | Lisensi | Cocok untuk | Catatan |
|---|---|---|---|
| [Kenney – Audio](https://kenney.nl/assets/category:Audio) | CC0 | UI, klik, impact, jingle | Paket yang relevan: *Interface Sounds*, *UI Audio*, *Impact Sounds*, *RPG Audio*, *Music Jingles*. Satu paket langsung isi banyak file. |
| [Freesound](https://freesound.org) | Campuran (CC0 / CC-BY / CC-BY-NC) | Ambience air, hujan, angin, gali tanah | Filter **License: Creative Commons 0** di hasil pencarian. Butuh akun gratis untuk download. |
| [OpenGameArt](https://opengameart.org/art-search-advanced) | Campuran (CC0 / CC-BY / GPL) | Musik loop game, SFX | Di pencarian, pilih *Art Type* = Music / Sound Effect. Cek lisensi di tiap halaman; contoh paket: [Interface Sounds](https://opengameart.org/content/interface-sounds). |
| [Pixabay Music](https://pixabay.com/music/) & [Sound Effects](https://pixabay.com/sound-effects/) | Pixabay Content License (gratis, tanpa kredit) | Musik menu/gameplay, ambience | Cari "relaxing", "lofi", "nature ambient", "stream". |
| [Incompetech (Kevin MacLeod)](https://incompetech.com/music/royalty-free/music.html) | CC-BY 4.0 | Musik latar | Wajib kredit nama artis + judul lagu. |
| [Sonniss GDC Game Audio Bundle](https://sonniss.com/gameaudiogdc) | Royalty-free, bebas kredit | SFX kualitas tinggi (air, alam, impact) | Ukuran unduhan sangat besar (puluhan GB); ambil seperlunya. |
| [Godot Asset Library](https://godotengine.org/asset-library/asset) | Tergantung aset | Paket SFX siap pakai | Cari "sound" / "sfx". Contoh: *Kenney Interface Sounds*. |

---

## Spesifikasi teknis

- **Format**: `.ogg` untuk musik dan ambience (centang **Loop** di tab Import Godot), `.wav` untuk SFX pendek (< 1 detik).
- **Volume**: musik sekitar -16 LUFS, SFX dengan puncak -1 dB. Musik harus lebih pelan dari SFX supaya umpan balik aksi tetap terdengar.
- **Potong hening** di awal file SFX supaya bunyi langsung terdengar saat diklik.
- **Loop harus mulus**: tidak ada "klik" di titik sambungan (cek di Audacity: Effect → Fade In/Out sangat pendek, atau pilih titik potong di zero crossing).
- Bunyi berulang (gali, jalan, air masuk kanal) nanti diberi pitch acak dan dibatasi maksimal ±3 kali per detik di kode.
- Bus audio `Music` dan `SFX` sudah ada di `default_bus_layout.tres` dan tersambung ke slider volume di menu Pengaturan.

---

## Kredit (wajib diisi untuk submission)

Isi satu baris untuk setiap file yang dipakai:

| File | Judul asli | Pembuat | Sumber (link) | Lisensi |
|---|---|---|---|---|
| `bgm_game.ogg` | | | | |
| `amb_water.ogg` | | | | |
| `ui_click.wav` | | | | |
| … | | | | |
