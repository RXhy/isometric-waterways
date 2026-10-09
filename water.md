# Panduan Tampilan Air — WATERWAYS

Cara mengganti dan mengatur tampilan air (animasi arus dan buih tepi) **lewat tile**, tanpa menyentuh kode.

> Animasi air **tidak memakai shader**. Semuanya animasi tile biasa di TileSet Godot.
> Border putih di pinggir air juga bukan efek render, melainkan **layer tile terpisah** berisi buih.

---

## 1. Animasi air — atlas source ID 2

### Letak file

| File | Isi |
|---|---|
| `assets/water/water_flow.png` | Gambar animasi: **10 baris × 4 frame**, tiap frame **32×32 px** |
| `assets/water/water_flow_source.tres` | Pengaturan animasi. Ini **source ID 2** di TileSet node `World` (`world.tscn`) |

### Urutan baris

| Baris | Isi | Kecepatan default |
|---|---|---|
| 0 | Air tenang (danau, genangan) | 3 fps |
| 1 | Arus pelan ↖ (kiri-atas) | 6 fps |
| 2 | Arus pelan ↗ (kanan-atas) | 6 fps |
| 3 | Arus pelan ↙ (kiri-bawah) | 6 fps |
| 4 | Arus pelan ↘ (kanan-bawah) | 6 fps |
| 5–8 | Arus deras, urutan arah sama dengan baris 1–4 | 12 fps |
| 9 | Air dangkal / ujung air yang sedang merambat | 4 fps |

Kode (`water_sim.gd`) memilih baris berdasarkan arah dan kekuatan aliran di tiap petak. Karena itu **urutan baris dan ukuran frame jangan diubah**. Kalau berubah, arah arus yang tampil akan salah.

### Cara mengganti gambar (paling mudah)

1. Gambar ulang `water_flow.png` dengan ukuran sama, yaitu **128×320 px** (4 frame × 10 baris).
2. Timpa file lamanya. Godot otomatis meng-import ulang, dan game langsung memakai gambar baru.

Tips untuk artist:
- Setiap frame 32×32 berisi **permukaan atas berbentuk belah ketupat** ditambah **dinding tanah** di bawahnya, sama seperti tile di `assets/Tiles/tileset_iso_waterways.png`.
- Frame terakhir harus menyambung mulus ke frame pertama supaya animasinya berulang tanpa patah.
- Pola arus harus menyambung ke tile sebelahnya, supaya sungai terlihat satu aliran utuh, bukan kotak-kotak.

### Cara mengatur animasi di editor

1. Buka `world.tscn`, lalu pilih node **World**.
2. Di panel bawah, buka tab **TileSet** dan pilih source **ID 2 (water_flow)** di daftar kiri.
3. Klik tile di **kolom pertama** baris yang mau diubah. Di Inspector, bagian **Animation**:
   - **Speed**: kecepatan animasi (fps)
   - **Frames Count**: jumlah frame (sekarang 4)
   - **Columns**: biarkan 0, artinya frame berjejer ke kanan
   - **Frame 0..N Duration**: lama tiap frame (relatif)
4. **Menambah jumlah frame**, misalnya jadi 6:
   1. Lebarkan PNG menjadi 6 × 32 = **192 px**.
   2. Ubah **Frames Count** menjadi 6 di **setiap** baris (0–9).

Kecepatan semua baris juga bisa diatur langsung di file `water_flow_source.tres`.

### Alternative tile 1–3

Setiap tile air punya alternative 0–3, satu untuk tiap **tingkat elevasi**:
- `texture_origin`: menaikkan gambar 4 px per tingkat
- `modulate`: kecerahan per tingkat (0,72 / 0,86 / 1 / 1,14)

Biarkan saja, kecuali memang mau mengubah warna air per ketinggian.

---

## 2. Border putih di pinggir air (buih tepi)

### Letak

| Bagian | Lokasi |
|---|---|
| Layer di game | Node **`World/WaterEdge`** di `world.tscn` |
| Layer di main menu | Node **`Ground/WaterEdge`** di `scenes/menu_map.tscn` |
| Gambar | `assets/water/water_edge.png`, grid **4×4** tile 32×32 (128×128 px) |
| TileSet | `assets/water/water_edge_tileset.tres` |

Di game, layer ini **diisi otomatis oleh kode** (`water_sim.gd` → `_refresh_edge`) di setiap sisi air yang berbatasan dengan daratan atau kanal kering. Jadi tile-nya tidak dicat manual satu per satu. Yang diubah adalah **gambar**, **TileSet**, atau **node layer**-nya.

### Susunan grid `water_edge.png`

Posisi tile = jumlah bit sisi yang diberi buih:

| Bit | Sisi |
|---|---|
| 1 | ↖ kiri-atas |
| 2 | ↗ kanan-atas |
| 4 | ↘ kanan-bawah |
| 8 | ↙ kiri-bawah |

- **Kolom** = nilai % 4, **baris** = nilai ÷ 4.
- Contoh:
  - Buih hanya di ↖ = 1 → kolom 1, baris 0.
  - Buih di ↖ + ↘ = 1 + 4 = 5 → kolom 1, baris 1.
  - Buih di keempat sisi = 15 → kolom 3, baris 3.
- Tile nilai 0 (kolom 0, baris 0) dibiarkan **kosong**.

### Pilihan cara mengubah

| Mau apa | Caranya |
|---|---|
| **Ganti gaya buih** | Timpa `water_edge.png` dengan gambar baru berukuran 128×128 dan susunan grid yang sama. |
| **Buih lebih samar** | Pilih node `World/WaterEdge`, lalu di Inspector → **Visibility → Modulate** turunkan nilai **A** (alpha), misalnya ke 120. |
| **Hilangkan buih sama sekali** | Matikan **Visible** pada node `World/WaterEdge`. Kode tetap jalan, tapi buihnya tidak terlihat. |
| **Warna buih beda per elevasi** | Buka `water_edge_tileset.tres` (atau tab TileSet saat node `WaterEdge` dipilih), pilih tile-nya, lalu atur **modulate** di alternative 0–3. |

Lakukan perubahan yang sama di `menu_map.tscn` kalau peta main menu juga mau ikut berubah. Gambar dan TileSet-nya sudah dipakai bersama, jadi hanya pengaturan node (Visible / Modulate) yang perlu diulang di sana.

---

## 3. Garis terang di dalam air

Coretan putih atau terang **di dalam** permukaan air **bukan** buih tepi. Itu bagian dari gambar arus di `water_flow.png`:
- **Baris 1–8:** garis arus yang bergerak searah aliran (lebih banyak dan lebih terang di baris deras 5–8).
- **Baris 9:** bintik buih untuk air dangkal / ujung air.

Untuk mengurangi atau menggantinya, gambar ulang frame di baris yang bersangkutan.

---

## 4. Kapan tile mana yang muncul

Ambang ini bisa diatur di Inspector node **Water** (`world.tscn`), grup **"Tampilan arus"**:

| Properti | Default | Arti |
|---|---|---|
| `still_flow` | 0,012 | Aliran di bawah angka ini → tile **tenang** (baris 0) |
| `fast_flow` | 0,06 | Aliran di atas angka ini → tile **deras** (baris 5–8) |
| `shallow_depth` | 0,18 | Air lebih dangkal dari ini (bukan sumber alami) → tile **dangkal** (baris 9) |
| `visual_interval` | 0,1 | Detik antar pembaruan pilihan tile (animasi frame tetap jalan tiap frame) |

---

## 5. Ringkasan cepat

| Ingin mengubah | File / node |
|---|---|
| Gambar animasi air | `assets/water/water_flow.png` |
| Kecepatan / jumlah frame | TileSet node `World` → source ID 2, atau `assets/water/water_flow_source.tres` |
| Gambar buih tepi | `assets/water/water_edge.png` |
| Samarkan / matikan buih | Node `World/WaterEdge` → Modulate / Visible |
| Warna air per elevasi | Alternative tile 0–3 di source ID 2 |
| Kapan tenang / pelan / deras / dangkal | Node `Water` → grup "Tampilan arus" |
