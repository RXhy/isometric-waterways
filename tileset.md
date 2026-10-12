# WATERWAYS — Tileset Air, Kanal, Jalan & Tanah

Dokumen ini menjelaskan cara game memilih tile air, kanal, dan jalan (versi terbaru di branch `feature/core-gameplay`), serta rencana pergantian tekstur tanah ke **v3**.

---

## 1. Sumber tile

| Source ID | File | Isi |
|---|---|---|
| 0 | `assets/Tiles/terrain_tiles_v3.png` | Daratan 5 kolom × 4 baris: baris 0 kering, 1–2 rumput, 3 pelataran |
| 1 | `assets/Tiles/tileset_iso_waterways.png` | Tile lama (dipakai hanya kalau `use_tileset_v2` dimatikan) |
| 2 | `assets/water/water_flow_source.tres` | Air beranimasi lama (dipakai hanya kalau `use_tileset_v2` dimatikan) |
| **3** | **`assets/Tiles/tilesset_water_road.png`** | Air alami, kanal galian, jalan (grid 32 px) |

Source 3 **tidak disimpan di `world.tscn`**. Saat game mulai, `world.gd` → `_build_v2_source()` mendaftarkannya ke TileSet, lengkap dengan 4 varian elevasi (alternative tile 0–3). Offset dan warna tiap elevasi meniru tile tanah. Artist cukup menimpa PNG-nya dengan ukuran dan susunan yang sama.

### Susunan `tilesset_water_road.png`

| Baris | Isi | Kolom |
|---|---|---|
| 0–2 | Air alami, bibir **coklat** (sebelah tanah kering) | 9 bentuk tepi danau |
| 3–5 | Air alami, bibir **hijau** (sebelah rumput) | 9 bentuk |
| 6–8 | Air alami, bibir **hijau gelap** (sebelah rumput gelap) | 9 bentuk |
| 10–12 | Kanal galian **bata** | 11 bentuk sambungan |
| 13–15 | Kanal galian **batu** | 11 bentuk sambungan |
| 17 | Jalan | 11 bentuk sambungan |

Tiap kelompok 3 baris berurutan: **kering → dangkal → penuh**.

---

## 2. Cara memilih tile (`world.gd` → `v2_atlas(petak)`)

Dipanggil oleh `water_sim.gd` setiap kali tampilan petak diperbarui.

### 2.1 Bitmask 4 sisi

Game melihat **4 tetangga sisi** petak (bukan sudut/serong), lalu membuat bitmask:

| Sisi | ↖ kiri-atas | ↗ kanan-atas | ↙ kiri-bawah | ↘ kanan-bawah |
|---|---|---|---|---|
| Bit | 1 | 2 | 4 | 8 |

Mask itu menentukan **kolom** tile. Kondisi air menentukan **baris**.

### 2.2 Air alami (petak WATER dari peta)

- **Mask** = sisi yang berbatasan dengan **daratan** (bukan air/kanal).
- **Kolom** (tabel `LAKE_COL`):

| Daratan di sisi | Kolom | Bentuk |
|---|---|---|
| tidak ada | 8 | tengah danau |
| ↖ | 1 | tepi kiri-atas |
| ↗ | 3 | tepi kanan-atas |
| ↙ | 4 | tepi kiri-bawah |
| ↘ | 6 | tepi kanan-bawah |
| ↖ + ↗ | 2 | sudut atas |
| ↙ + ↘ | 5 | sudut bawah |
| ↖ + ↙ | 0 | sudut kiri |
| ↗ + ↘ | 7 | sudut kanan |
| berseberangan / 3 / 4 sisi | tile terdekat | *tidak ada di sheet* |

- **Kelompok warna bibir**: dari kelas daratan di sebelahnya. Tanah kering → baris 0–2, rumput dekat air → 3–5, rumput gelap → 6–8.
- **Tingkat air**: kedalaman < `wet_threshold` (0,06) → **kering**; < `v2_full_depth` (0,3) → **dangkal**; selebihnya **penuh**. Saat kemarau danau tampak surut.
- Air di luar area simulasi selalu tampil penuh.

### 2.3 Kanal galian (petak CANAL)

- **Mask** = sisi yang bertetangga dengan **kanal atau air**, ditambah **satu sambungan ke bangunan**.
  - Tiap bangunan hanya punya satu kanal "masuk" (`canal_link()`): kanal di sisi bangunan yang paling sedikit sambungannya (utamakan ujung kanal).
- **Kolom** (tabel `LINK_COL`):

| Tersambung ke | Kolom | Bentuk |
|---|---|---|
| ↗ + ↘ | 0 | belokan |
| ↙ + ↘ | 1 | belokan |
| ↖ + ↘ | 2 | lurus ↘ |
| ↗ + ↙ | 3 | lurus ↗ |
| ↖ + ↗ | 4 | belokan |
| ↖ + ↙ | 5 | belokan |
| semua kecuali ↖ | 6 | pertigaan |
| semua kecuali ↙ | 7 | pertigaan |
| semua kecuali ↗ | 8 | pertigaan |
| semua kecuali ↘ | 9 | pertigaan |
| semua | 10 | perempatan |
| 1 sisi / terisolasi | 2 atau 3 | lurus (*tile buntu tidak ada di sheet*) |

- **Baris**: `10 + canal_style × 3 + tingkat air` (bata = 0, batu = 1).

### 2.4 Jalan (petak ROAD)

- **Mask** = sisi yang bertetangga dengan jalan / jembatan / jalan yang masih antre dibangun.
- Kalau ujung buntu (≤ 1 sambungan), ditambah sisi yang bertetangga dengan **bangunan**.
- **Kolom**: tabel `LINK_COL` yang sama dengan kanal. **Baris**: 17.

### 2.5 Daratan banjir

Tile tengah danau (kolom 8), tingkat dangkal.

### 2.6 Kapan dihitung ulang

- Setiap petak berubah (`set_base` → `water.refresh_cell`): petak itu + 4 tetangganya + petak di sekeliling bangunan tetangga.
- Saat bangunan baru muncul (`building_manager._spawn`).
- Tiap 0,1 detik (`refresh_all`) untuk perubahan tingkat air.

### 2.7 Animasi

- **Jalan baru**: petak muncul satu per satu dari jalan lama menuju bangunan (Roads → grup *Animasi jalan*).
- **Gali**: setelah klik/drag, sekop langsung dipotong, lalu kanal "jatuh" ke tempatnya petak demi petak mengikuti urutan drag (Node2D → `dig_step_delay`, `dig_drop_time`, `dig_drop_height`).
- Sprite animasi ikut y-sort layer `World`, jadi tertutup tanah di depannya persis seperti tile aslinya.

### 2.8 Pengaturan di Inspector (Node2D → grup *Tileset air & jalan*)

| Properti | Default | Fungsi |
|---|---|---|
| `use_tileset_v2` | aktif | Matikan untuk kembali ke tile lama + air beranimasi |
| `water_road_texture` | `tilesset_water_road.png` | Tekstur sheet |
| `canal_style` | 0 | 0 bata, 1 batu |
| `v2_full_depth` | 0,3 | Batas kedalaman tile "penuh" |
| `v2_top_shift` | 0 | Geser vertikal tile air/jalan terhadap tile tanah (0 = sejajar, lihat §3) |
| `v2_canal_sort_boost` | 0 | 0 = kanal rata dengan tanah |

---

## 3. Tekstur tanah v3 (sudah dipakai)

| File | Permukaan atas mulai di baris | Tebal sisi blok |
|---|---|---|
| `terrain_tiles.png` (lama) | 13 | 3 px |
| `terrain_tiles_v2.png` | 13 | 3 px |
| **`terrain_tiles_v3.png`** (dipakai) | **6** | **10 px** |
| `tilesset_water_road.png` | 6 | 10 px |

Tanah v3 dan tileset air/jalan punya geometri yang sama, jadi keduanya sejajar tanpa geseran.

Yang diubah saat pindah ke v3:
1. `world.tscn`: source 0 memakai `terrain_tiles_v3.png`. Nilai tiap alternative tile (= tingkat elevasi):

| Alternative | Elevasi | `texture_origin` Y | Modulate (slider **I** dari #ffffff; Godot menghitung di ruang linear: warna = srgb(linear × 2^I)) |
|---|---|---|---|
| 0 | Garis pantai | -2 | I = -1,5 → #a0a0a0 (0,629) |
| 1 | Dataran rendah | 2 | I = -1 → #bcbcbc (0,735) |
| 2 | Dataran menengah | 6 | I = -0,5 → #dbdbdb (0,858) |
| 3 | Dataran tinggi | 10 | I = 0 → #ffffff |

   Tile air, kanal, dan jalan (source 3) **menyalin otomatis** nilai ini dari tile tanah saat game mulai (`_build_v2_source`), jadi selalu sama dan teksturnya menyambung. Kalau nilai di atas diubah di editor, tile air/jalan ikut berubah.
2. `world.gd`: `v2_top_shift` = **0**.
3. `tools/build_menu_map.gd` → `V2_TOP_SHIFT = 0`, lalu `scenes/menu_map.tscn` dibuat ulang (otomatis ikut v3 dari TileSet `world.tscn`).

Kalau artist mengganti gambar tanah, timpa `terrain_tiles_v3.png` dengan ukuran dan susunan yang sama (5 × 4 tile, 32 × 32, permukaan atas di baris 6).

## 4. Tile yang belum ada (permintaan ke artist)

- Kanal & jalan **buntu** (1 sambungan) dan **terisolasi** (0 sambungan).
- Tepi danau **dua sisi berseberangan** (sungai selebar 1 petak), **tiga sisi**, dan **sudut dalam**.
- Fungsi kanal **batu** (baris 13–15) belum ditentukan, misalnya untuk kanal di dataran tinggi atau yang tersambung ke Spillway.

Kalau tile baru ditambahkan, cukup beri tahu posisinya di sheet, lalu tabel `LAKE_COL` / `LINK_COL` di `world.gd` diperbarui.
