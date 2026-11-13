extends "res://survey/survey_page.gd"
## Layar profil pemain sebelum main (Mode Survei). Setelah disimpan, kembali ke menu utama
## dengan panel Mode Survei aktif (pemain boleh membuka tutorial dulu, lalu Mulai Main).

const UMUR := ["< 15 tahun", "15–17 tahun", "18–21 tahun", "22–25 tahun", "26–30 tahun", "> 30 tahun"]
const STATUS := ["Pelajar SMP", "Pelajar SMA/SMK", "Mahasiswa", "Bekerja", "Lainnya"]
const FREKUENSI := ["Hampir tidak pernah", "Sebulan sekali", "Seminggu sekali",
	"Beberapa kali seminggu", "Setiap hari"]
const SERUPA := ["Belum pernah", "Pernah 1–2 kali", "Cukup sering", "Sangat sering"]
const PLATFORM := ["HP", "PC / Laptop", "Konsol", "Campuran"]

var f_nama: LineEdit
var f_umur: OptionButton
var f_status: OptionButton
var f_frek: OptionButton
var f_serupa: OptionButton
var f_platform: OptionButton
var f_paham: HBoxContainer
var f_setuju: CheckBox

func _ready() -> void:
	build_frame("MODE SURVEI · Profil Pemain")
	sub_lbl.text = "1 / 1  ·  ±1 menit"
	add_note("Halo! Terima kasih sudah mau mencoba WATERWAYS. Isi profil singkat ini, lalu main. Kuesioner diisi setelah selesai main.")
	f_nama = LineEdit.new()
	f_nama.placeholder_text = "Nama atau nama panggilan"
	f_nama.max_length = 40
	add_row("Nama / nama panggilan *", f_nama)
	f_umur = make_option(UMUR)
	add_row("Umur *", f_umur)
	f_status = make_option(STATUS)
	add_row("Status *", f_status)
	f_frek = make_option(FREKUENSI)
	add_row("Seberapa sering kamu main game? *", f_frek)
	f_serupa = make_option(SERUPA)
	add_row("Pernah main game strategi/simulasi (mis. Mini Motorways)? *", f_serupa)
	f_platform = make_option(PLATFORM)
	add_row("Biasanya main game di *", f_platform)
	f_paham = make_choice(["1", "2", "3", "4", "5"], [1, 2, 3, 4, 5])
	add_row("Paham pentingnya mengatur distribusi air? (1 = tidak, 5 = sangat) *", f_paham)
	f_setuju = make_check("Saya setuju data permainan, screenshot otomatis, dan jawaban saya dipakai untuk penelitian & presentasi lomba MAGE 12 (nama tidak dipublikasikan).")
	f_setuju.custom_minimum_size = Vector2(560, 0)
	body.add_child(f_setuju)
	add_nav_button("< Batal", func(): Survey.to_menu())
	add_spacer_nav()
	add_nav_button("Simpan & Lanjut  >", _submit, true)
	f_nama.grab_focus()

func _submit() -> void:
	show_error("")
	var nama := f_nama.text.strip_edges()
	var missing: Array[String] = []
	if nama == "":
		missing.append("nama")
	if option_value(f_umur) == "":
		missing.append("umur")
	if option_value(f_status) == "":
		missing.append("status")
	if option_value(f_frek) == "":
		missing.append("frekuensi main game")
	if option_value(f_serupa) == "":
		missing.append("pengalaman game serupa")
	if option_value(f_platform) == "":
		missing.append("platform")
	if chosen(f_paham) == "":
		missing.append("pemahaman distribusi air")
	if not missing.is_empty():
		show_error("Belum diisi: " + ", ".join(missing) + ".")
		return
	if not f_setuju.button_pressed:
		show_error("Centang persetujuan penggunaan data dulu ya.")
		return
	Survey.begin({
		"nama": nama,
		"umur": option_value(f_umur),
		"status": option_value(f_status),
		"frekuensi_main_game": option_value(f_frek),
		"pengalaman_game_serupa": option_value(f_serupa),
		"platform_utama": option_value(f_platform),
		"paham_air_sebelum": chosen(f_paham),
		"persetujuan_data": "ya",
	})
	Survey.to_menu()
