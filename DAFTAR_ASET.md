# Daftar Aset — WATERWAYS (MAGE 12)

Daftar semua aset yang dibutuhkan game, disusun dari placeholder yang sudah ada di project.

## Aturan umum

- **Gaya:** pixel art, tile isometrik **32×16** (gambar tile 32×32 termasuk dindingnya).
- **Format:** PNG transparan. Di Godot, filter import = *Nearest* (tanpa blur).
- **Cara mengganti:** selama **nama file dan ukurannya sama**, cukup **timpa file placeholder-nya**. Aset baru langsung tampil di game tanpa mengubah kode.
- **Ukuran sprite berubah?** Boleh. Posisinya disesuaikan lewat `offset` di scene masing-masing (`scenes/*.tscn`).
- Semua path di bawah relatif terhadap folder project (`res://`).

**Prioritas:** **Wajib** = harus ada saat submit · **Penting** = sangat disarankan · **Opsional** = kalau waktu cukup

---

## Artist 1 — Lingkungan & UI

### Tile

| Aset | File | Ukuran | Prioritas | Catatan |
|---|---|---|---|---|
| Tanah (kering, dekat air, pelataran) | `assets/Tiles/terrain_tiles.png` | 160×128 (5×4 tile) | Wajib | Sudah ada, tinggal dipoles. Baris 0: kering · baris 1–2: dekat air · baris 3: pelataran sekitar bangunan |
| Kanal kering & jalan | `assets/Tiles/tileset_iso_waterways.png` | 160×32 (5 tile) | Wajib | Kolom 1 = kanal kering, kolom 4 = jalan |
| Air beranimasi | `assets/water/water_flow.png` | 128×320 (4 frame × 10 baris) | Wajib | Lihat urutan baris di bawah |
| Buih tepi air | `assets/water/water_edge.png` | 128×128 (grid 4×4) | Wajib | 15 kombinasi sisi, lihat penjelasan di bawah |
| Dinding tebing | *(baru)* | 32×32 | Opsional | Supaya beda elevasi lebih jelas |

**Urutan baris `water_flow.png`** (tiap baris 4 frame ke kanan, tiap frame 32×32):

| Baris | Isi | Kecepatan animasi |
|---|---|---|
| 0 | Air tenang (danau, genangan) | 3 fps |
| 1 | Arus pelan ke kiri-atas ↖ | 6 fps |
| 2 | Arus pelan ke kanan-atas ↗ | 6 fps |
| 3 | Arus pelan ke kiri-bawah ↙ | 6 fps |
| 4 | Arus pelan ke kanan-bawah ↘ | 6 fps |
| 5–8 | Arus deras, urutan arah sama dengan baris 1–4 | 12 fps |
| 9 | Air dangkal / ujung air yang sedang merambat (berbuih) | 4 fps |

Kecepatan animasi bisa diubah di `assets/water/water_flow_source.tres` (Inspector → animation speed).

**Grid `water_edge.png`:** posisi tile = jumlah bit sisi yang diberi buih.
Bit: **1** = sisi kiri-atas, **2** = kanan-atas, **4** = kanan-bawah, **8** = kiri-bawah.
Kolom = nilai % 4, baris = nilai ÷ 4. Contoh: buih di kiri-atas + kanan-bawah = 1 + 4 = 5 → kolom 1, baris 1. Tile nilai 0 (kiri-atas grid) dibiarkan kosong.

### Objek peta

| Aset | File | Ukuran | Prioritas | Catatan |
|---|---|---|---|---|
| Jembatan | `assets/placeholder/jembatan.png` | ±25×13 | Wajib | Sekarang 1 arah. Butuh **2 arah** (↗↙ dan ↖↘) |
| Kursor petak | `assets/placeholder/ui/cursor_tile.png` | 32×16 | Penting | Garis sorotan putih; warnanya diatur game (hijau = bisa, merah = tidak) |
| Overlay lapisan info | `assets/placeholder/overlay_tiles.png` | 256×16 (8 tile) | Opsional | Tile 0–3: ketinggian · tile 4–7: kedalaman air (dangkal → dalam) |

### UI

| Aset | File | Ukuran | Prioritas | Catatan |
|---|---|---|---|---|
| Panel HUD | `assets/placeholder/ui/panel.png` | 24×24 | Wajib | 9-slice, margin 5 px |
| Kartu alat — normal | `assets/placeholder/ui/card.png` | 24×24 | Wajib | 9-slice, margin 5 px |
| Kartu alat — hover | `assets/placeholder/ui/card_hover.png` | 24×24 | Wajib | 9-slice, margin 5 px |
| Kartu alat — terpilih | `assets/placeholder/ui/card_selected.png` | 24×24 | Wajib | 9-slice, margin 5 px |
| Lencana stok | `assets/placeholder/ui/badge.png` | 10×10 | Wajib | 9-slice, margin 3 px |
| Progress bar (latar & isi) | `assets/placeholder/ui/bar_bg.png`, `bar_fill.png` | 12×12 | Wajib | 9-slice |
| Cincin timer air bangunan | `assets/placeholder/ui/ring_under.png`, `ring_progress.png` | 18×18 | Wajib | Gambar putih/abu; warna (biru/jingga/merah) diatur game |
| Ikon kontrol (7) | `assets/placeholder/ui/ic_pause.png`, `ic_play.png`, `ic_fast.png`, `ic_layers.png`, `ic_star.png`, `ic_ruin.png`, `ic_arrow.png` | 16×16 | Wajib | Jeda, main, cepat, lapisan, poin, bangunan hancur, panah prakiraan |
| Ikon alat (5) | `assets/placeholder/icons/jembatan.png`, `bor.png`, `bendungan.png`, `spillway.png`, `kincir.png` | 48×48 | Wajib | Gaya disamakan dengan ikon di `assets/Icon/` |
| Panel menu utama | `assets/placeholder/ui/menu_panel.png`, `menu_dialog.png` | 24×24 | Penting | 9-slice |
| Dekorasi menu utama | `assets/placeholder/ui/menu_divider.png` (8×2), `menu_marker.png` (24×6) | — | Penting | Garis pemisah & penanda item terpilih |
| **Logo WATERWAYS** | *(baru)* | ±200×60 | Wajib | Untuk menu utama, thumbnail, dan video |

### Promosi

| Aset | Prioritas | Catatan |
|---|---|---|
| Thumbnail / poster submission | Penting | Logo + screenshot build final (15–16 Okt) |

---

## Artist 2 — Bangunan, Karakter, VFX, Audio, Video

### Bangunan & fasilitas

| Aset | File | Ukuran sekarang | Prioritas | Catatan |
|---|---|---|---|---|
| Rumah | `assets/placeholder/rumah.png` | 24×31 | Wajib | Titik bawah sprite = tengah petak |
| Ladang | `assets/placeholder/ladang.png` | 24×16 | Wajib | Datar, menutupi petak |
| Reruntuhan | `assets/placeholder/reruntuhan.png` | 24×15 | Wajib | Versi hancur rumah/ladang |
| Mesin Bor | `assets/placeholder/sumur_bor.png` | 20×30 | Wajib | |
| Bendungan | `assets/placeholder/bendungan.png` | 24×23 | Wajib | Harus terlihat bisa melintang di kanal |
| Spillway | `assets/placeholder/spillway.png` | 24×18 | Wajib | Saluran pembuang di tepi air |
| **Kincir Air (animasi)** | `assets/placeholder/kincir.png` | 112×30 (4 frame × 28×30) | Wajib | Boleh 4–6 frame. Kalau jumlah frame berubah, sesuaikan SpriteFrames di `scenes/kincir.tscn` (node Wheel, animasi "putar") |

### Karakter & tutorial

| Aset | Ukuran | Prioritas | Catatan |
|---|---|---|---|
| Potret karakter engineer | ±64×64 | Penting | 2–3 ekspresi: netral, senang, khawatir |
| Kotak dialog | 24×24 (9-slice) | Penting | Bisa dikerjakan Artist 1 kalau Artist 2 penuh |

### VFX

| Aset | File | Prioritas | Catatan |
|---|---|---|---|
| Tetes hujan | `assets/placeholder/hujan.png` (1×6) | Penting | Partikel; boleh sedikit lebih besar |
| Ikon peringatan di atas bangunan | `assets/placeholder/peringatan.png` (9×9) | Penting | Muncul saat bangunan terancam |
| Efek kemarau | *(baru)* | Opsional | Sekarang hanya tint layar; bisa ditambah debu/retakan |

### Audio (berlisensi bebas)

| Jenis | Isi | Prioritas |
|---|---|---|
| Musik | 1 lagu menu + 1–2 lagu gameplay (loop) | Wajib |
| SFX alat | Gali, timbun, ratakan, pasang fasilitas, pasang jembatan | Wajib |
| SFX game | Klik UI, bangunan baru muncul, bangunan terancam, bangunan hancur, hari baru, menang, kalah | Wajib |
| Ambience | Aliran air, hujan, angin kemarau, putaran kincir | Penting |

**Catat sumber dan lisensi setiap file audio.** Daftar kredit wajib dilampirkan saat submission.

### Video & dokumen

| Aset | Prioritas | Catatan |
|---|---|---|
| Rekaman gameplay + trailer/demo | Wajib | Dari build final (15–17 Okt) |
| Daftar kredit & lisensi aset | Wajib | 16 Okt |

---

## Sudah final (tidak perlu dibuat ulang)

- Ikon alat: `assets/Icon/gali.png`, `ratakan.png`, `timbun.png`
- Ikon cuaca: `assets/Icon/cerah.png`, `kemarau.png`, `rain.png`, `berawan.png`
- `assets/Tiles/terrain_tiles.png` (boleh dipoles)

## Tenggat terkait (dari timeline tim)

| Tanggal | Target |
|---|---|
| 10 Okt | Semua fitur sudah ada (placeholder masih boleh) |
| 13 Okt | **Semua aset final masuk** |
| 14 Okt | Feature freeze |
| 17 Okt | Build & video final |
| 18 Okt | Submit (cadangan 1 hari sebelum deadline resmi 19 Okt) |
