class_name MenuChoice
extends RefCounted
## Daftar varian layout main menu + varian yang sedang dipakai.
## Dipilih di layar debug scenes/debug/menu_picker.tscn saat game baru dijalankan,
## lalu dipakai juga saat kembali ke menu dari dalam game (menu in-game / layar akhir).
## Varian default (dipakai langsung di build release tanpa layar pilihan): DEFAULT_INDEX.

const VARIANTS := [
	{"key": "A", "name": "A - Panel gelap + logo", "desc": "Logo WATERWAYS, panel gelap di kiri, peta penuh layar (main UI.jpeg)",
		"path": "res://scenes/main_menu.tscn", "thumb": "res://assets/placeholder/ui/debug/menu_opsi_a.png"},
	{"key": "B", "name": "B - Diorama tengah", "desc": "Judul di atas, pulau di tengah, bar menu di bawah",
		"path": "res://scenes/main_menu_b.tscn", "thumb": "res://assets/placeholder/ui/debug/menu_opsi_b.png"},
	{"key": "C", "name": "C - Kartu mengambang", "desc": "Judul kiri atas, kartu menu kecil di kiri bawah",
		"path": "res://scenes/main_menu_c.tscn", "thumb": "res://assets/placeholder/ui/debug/menu_opsi_c.png"},
]
const DEFAULT_INDEX := 0

static var current_index: int = -1

## Scene main menu yang aktif (varian terpilih, atau default).
static func scene_path() -> String:
	var i := current_index
	if i < 0:
		i = saved_index()
	return VARIANTS[clampi(i, 0, VARIANTS.size() - 1)]["path"]

## Varian yang tersimpan dari pilihan terakhir (atau default).
static func saved_index() -> int:
	var v = GameSettings.get_value("menu_variant")
	return int(v) if v != null and int(v) >= 0 else DEFAULT_INDEX

static func choose(i: int) -> void:
	current_index = clampi(i, 0, VARIANTS.size() - 1)
	GameSettings.set_value("menu_variant", current_index)
