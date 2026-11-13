extends "res://survey/survey_page.gd"
## Kuesioner setelah main (Mode Survei), 3 halaman:
##   1. Rating 1-5 pengalaman bermain + pemahaman distribusi air sesudah main
##   2. Tingkat kesulitan, NPS 0-10, dan cek pemahaman mekanik (pilihan ganda)
##   3. Kesan, pesan/saran, bagian paling seru, bagian paling membingungkan
## Disimpan lewat Survey.submit() ke survei.csv.

const RATINGS := [
	["r_seru", "Game ini seru dimainkan."],
	["r_tujuan_jelas", "Aku paham apa tujuan permainannya."],
	["r_kontrol_mudah", "Kontrol (gali, ratakan, timbun, pasang fasilitas) mudah dipakai."],
	["r_arus_terbaca", "Aku bisa melihat ke mana air mengalir dan seberapa deras dari tampilannya."],
	["r_cuaca_adil", "Tantangan cuaca (kemarau & hujan lebat) terasa adil dan bisa diantisipasi."],
	["r_strategi_beragam", "Ada banyak cara/strategi untuk mengalirkan air ke bangunan."],
	["r_visual_audio", "Tampilan visual dan suaranya menarik."],
	["r_ingin_main_lagi", "Aku ingin main game ini lagi."],
]
const KESULITAN := ["Terlalu mudah", "Agak mudah", "Pas", "Agak sulit", "Terlalu sulit"]
## [kunci, pertanyaan, pilihan, indeks jawaban benar]
const QUIZ := [
	["q_spillway", "Apa fungsi Spillway?", [
		"Menggali kanal lebih cepat",
		"Menahan air, hanya kelebihannya yang mengalir (cegah luapan)",
		"Membuat sumber air baru",
		"Mengangkat air ke dataran yang lebih tinggi",
		"Tidak tahu"], 1],
	["q_kemarau", "Apa yang terjadi saat kemarau?", [
		"Semua kanal langsung kering seketika",
		"Bangunan baru berhenti muncul",
		"Sumber air alami menyusut pelan-pelan, makin parah tiap kemarau",
		"Air mengalir lebih deras",
		"Tidak tahu"], 2],
	["q_dataran_tinggi", "Bangunan di tanah yang lebih tinggi tidak kebagian air. Apa solusinya?", [
		"Gali kanal yang lebih panjang",
		"Pasang Spillway di depannya",
		"Pakai Kincir Air untuk memompa air naik, atau Ratakan tanah",
		"Tunggu hujan saja",
		"Tidak tahu"], 2],
]
const TEXTS := [
	["kesan", "Kesan kamu setelah main WATERWAYS", "Ceritakan kesanmu…"],
	["pesan_saran", "Pesan / saran untuk tim", "Apa yang perlu ditambah atau diperbaiki?"],
	["bagian_paling_seru", "Bagian paling seru", "Momen atau fitur yang paling kamu suka"],
	["bagian_paling_membingungkan", "Bagian paling membingungkan", "Bagian yang bikin bingung atau susah"],
]

var page := 0
var answers := {}
var fields := {}

func _ready() -> void:
	if not Survey.can_fill_survey():
		# dibuka tanpa sesi survei aktif: kembali ke menu
		Survey.to_menu.call_deferred()
		return
	build_frame("MODE SURVEI · Kuesioner")
	_show_page(0)

func _show_page(i: int) -> void:
	page = i
	clear_body()
	clear_nav()
	fields.clear()
	sub_lbl.text = "%s  ·  halaman %d / 3" % [Survey.player.get("id", ""), page + 1]
	match page:
		0: _page_rating()
		1: _page_quiz()
		2: _page_text()
	if page > 0:
		add_nav_button("< Kembali", func(): _leave(page - 1, false))
	add_spacer_nav()
	if page < 2:
		add_nav_button("Berikutnya  >", func(): _leave(page + 1, true), true)
	else:
		add_nav_button("Simpan Survei  ✓", _finish, true)

func _page_rating() -> void:
	add_note("Seberapa setuju kamu dengan pernyataan berikut?  1 = sangat tidak setuju · 3 = netral · 5 = sangat setuju")
	for r in RATINGS:
		var c := make_choice(["1", "2", "3", "4", "5"], [1, 2, 3, 4, 5], str(answers.get(r[0], "")), 24)
		fields[r[0]] = c
		add_row(r[1], c, 360)
	add_section("Setelah bermain")
	var p := make_choice(["1", "2", "3", "4", "5"], [1, 2, 3, 4, 5], str(answers.get("paham_air_sesudah", "")), 24)
	fields["paham_air_sesudah"] = p
	add_row("Seberapa paham kamu soal pentingnya mengatur distribusi air? (1 = tidak paham, 5 = sangat paham)", p, 360)

func _page_quiz() -> void:
	var k := make_choice(KESULITAN, KESULITAN, str(answers.get("kesulitan", "")), 0)
	fields["kesulitan"] = k
	add_row("Tingkat kesulitan game ini", k, 150)
	var labels := []
	for n in 11:
		labels.append(str(n))
	var nps := make_choice(labels, labels, str(answers.get("nps", "")), 20)
	fields["nps"] = nps
	add_row("Seberapa mungkin kamu merekomendasikan WATERWAYS ke teman? (0 = tidak mungkin, 10 = pasti)", nps, 150)
	add_section("Cek pemahaman (jawab sebisanya, tidak apa-apa kalau tidak tahu)")
	for q in QUIZ:
		var o := make_option(q[2], str(answers.get(q[0] + "_jawaban", "")))
		o.fit_to_longest_item = false
		o.clip_text = true
		o.custom_minimum_size = Vector2(260, 0)
		fields[q[0]] = o
		add_row(q[1], o, 200)

func _page_text() -> void:
	add_note("Tulis bebas, boleh singkat. Kolom kesan wajib diisi, yang lain opsional.")
	for t in TEXTS:
		var e := make_text(t[2], str(answers.get(t[0], "")), 36)
		fields[t[0]] = e
		add_row(t[1] + (" *" if t[0] == "kesan" else ""), e, 150)

## Simpan isian halaman ini. validate = cek wajib isi sebelum maju.
func _collect() -> Array[String]:
	var missing: Array[String] = []
	match page:
		0:
			for r in RATINGS:
				answers[r[0]] = chosen(fields[r[0]])
				if answers[r[0]] == "":
					missing.append("\"%s\"" % r[1])
			answers["paham_air_sesudah"] = chosen(fields["paham_air_sesudah"])
			if answers["paham_air_sesudah"] == "":
				missing.append("pemahaman distribusi air")
		1:
			answers["kesulitan"] = chosen(fields["kesulitan"])
			answers["nps"] = chosen(fields["nps"])
			if answers["kesulitan"] == "":
				missing.append("tingkat kesulitan")
			if answers["nps"] == "":
				missing.append("rekomendasi (0-10)")
			for q in QUIZ:
				var v := option_value(fields[q[0]])
				answers[q[0] + "_jawaban"] = v
				answers[q[0] + "_benar"] = 1 if v == q[2][q[3]] else 0
				if v == "":
					missing.append("pertanyaan \"%s\"" % q[1])
		2:
			for t in TEXTS:
				answers[t[0]] = (fields[t[0]] as TextEdit).text.strip_edges()
			if answers["kesan"] == "":
				missing.append("kesan")
	return missing

func _leave(to: int, validate: bool) -> void:
	show_error("")
	var missing := _collect()
	if validate and not missing.is_empty():
		show_error("Belum diisi: " + ", ".join(missing.slice(0, 3)) + ("…" if missing.size() > 3 else "."))
		return
	_show_page(to)

func _finish() -> void:
	var missing := _collect()
	if not missing.is_empty():
		show_error("Belum diisi: " + ", ".join(missing) + ".")
		return
	var nama: String = Survey.player.get("nama", "")
	var id := Survey.submit(answers)
	_thanks(nama, id)

func _thanks(nama: String, id: String) -> void:
	clear_body()
	clear_nav()
	sub_lbl.text = ""
	title_lbl.text = "Terima kasih, %s!" % nama
	add_note("Jawabanmu sudah tersimpan sebagai %s. Masukanmu sangat membantu tim Ayam Renang menyempurnakan WATERWAYS." % id, Survey.C_CREAM)
	add_note("Data: %s" % Survey.root_dir.path_join("survei.csv"), Color(1, 1, 1, 0.45))
	add_spacer_nav()
	add_nav_button("Kembali ke Menu", func(): Survey.to_menu())
	add_nav_button("Pemain Berikutnya  >", func(): Survey.open_profile(), true)
