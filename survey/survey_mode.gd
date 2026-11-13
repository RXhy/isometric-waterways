extends Node
## Mode Survei untuk playtest dengan pemain sungguhan (autoload "Survey", lihat project.godot).
##
## Alur:
##   Menu utama -> tombol MODE SURVEI -> isi profil pemain -> kembali ke menu (tutorial opsional)
##   -> Mulai Main (boleh berkali-kali) -> setelah minimal 1 permainan SELESAI (menang/kalah)
##   -> Isi Survei (rating, NPS, cek pemahaman, kesan & pesan) -> tersimpan, siap pemain berikutnya.
##
## Lokasi data (folder induk, lihat _resolve_root):
##   survei.csv      satu baris per pemain: profil, ringkasan semua permainan, rating, kesan & pesan
##   percobaan.csv   satu baris per permainan yang selesai (semua pemain), untuk analisis per percobaan
##   P001_Nama_2026-11-12_10-15-02/      folder per pemain
##       profil.txt, ringkasan.txt
##       percobaan_1/  screenshot otomatis (urut waktu) + salinan log sesi BalanceLog
##
## Permainan yang tidak selesai (Main Ulang di tengah, kembali ke menu, game ditutup) tidak dihitung:
## folder percobaannya dihapus, sama seperti BalanceLog.
## CSV ditulis UTF-8 dengan BOM supaya huruf terbaca benar di Excel; teks berkoma otomatis diberi tanda kutip.

const DEFAULT_ROOT := "C:/COMPE/MAGE 12/FINAL/Survey"
const PROFILE_SCENE := "res://scenes/survey_profile.tscn"
const FORM_SCENE := "res://scenes/survey_form.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const GAME_SCENE := "res://scenes/loading.tscn"
const THEME_PATH := "res://ui/hud_theme.tres"

## Kolom survei.csv (satu baris per pemain).
const SURVEY_COLUMNS := [
	"id_pemain", "nama", "waktu_mulai", "waktu_selesai", "durasi_sesi_menit", "versi_build",
	# profil (diisi sebelum main)
	"umur", "status", "frekuensi_main_game", "pengalaman_game_serupa", "platform_utama",
	"paham_air_sebelum",
	# tutorial
	"tutorial_dibuka_di_menu", "tutorial_dibuka_saat_main", "tutorial_halaman_dilihat", "tutorial_halaman_total",
	# ringkasan permainan (otomatis)
	"jumlah_permainan", "jumlah_menang", "hasil_terbaik", "hari_terjauh", "poin_terbaik", "bintang_terbaik",
	"total_menit_bermain",
	"p1_hasil", "p1_sebab", "p1_hari", "p1_poin", "p1_hancur", "p1_detik_aksi_pertama",
	"p1_detik_bangunan_teraliri_pertama", "p1_menit_nyata_bangunan_teraliri_pertama",
	"terakhir_hasil", "terakhir_sebab", "terakhir_hari", "terakhir_poin",
	"total_gali", "total_ratakan", "total_timbun", "total_pasang_fasilitas", "total_jembatan",
	"total_bangunan_hancur", "kemarau_dialami_maks", "hujan_dialami_maks",
	# rating 1-5 (1 = sangat tidak setuju, 5 = sangat setuju)
	"r_seru", "r_tujuan_jelas", "r_kontrol_mudah", "r_arus_terbaca", "r_cuaca_adil",
	"r_strategi_beragam", "r_visual_audio", "r_ingin_main_lagi",
	"paham_air_sesudah", "selisih_paham_air",
	"kesulitan", "nps", "kategori_nps",
	# cek pemahaman mekanik
	"q_spillway_jawaban", "q_spillway_benar", "q_kemarau_jawaban", "q_kemarau_benar",
	"q_dataran_tinggi_jawaban", "q_dataran_tinggi_benar", "skor_pemahaman_0_3",
	# isian bebas
	"kesan", "pesan_saran", "bagian_paling_seru", "bagian_paling_membingungkan",
	"persetujuan_data", "folder_pemain",
]

## Kolom percobaan.csv (satu baris per permainan yang selesai).
const ATTEMPT_COLUMNS := [
	"id_pemain", "nama", "percobaan_ke", "waktu_mulai", "waktu_selesai", "durasi_nyata_menit",
	"hasil", "sebab", "hari", "target_hari", "poin", "target_poin", "bintang", "bangunan_hancur",
	"detik_aksi_pertama", "detik_bangunan_teraliri_pertama", "menit_nyata_bangunan_teraliri_pertama",
	"detik_terancam_pertama", "detik_hancur_pertama", "detik_target_tercapai",
	"kemarau_dialami", "hujan_dialami",
	"gali", "ratakan", "timbun", "pasang_fasilitas", "bongkar_fasilitas", "jembatan", "drag",
	"jeda_detik", "cepat2x_detik", "kincir_terpasang", "seed", "jumlah_screenshot", "folder", "file_log",
]

var root_dir := ""
var active := false
var player := {}
var player_dir := ""
var attempts: Array = []
var tutorial_pages := {}
var tutorial_total := 7
var tutorial_opens_menu := 0
var tutorial_opens_game := 0
var _start_ms := 0

# permainan yang sedang berjalan
var world = null
var cur := {}
var cur_dir := ""
var _shot_n := 0
var _last_day := 0
var _poll := 0.0
var _pending: Array = []      # [detik_game, label] screenshot yang dijadwalkan
var _tasks: Array = []        # task WorkerThreadPool penyimpan PNG

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root_dir = _resolve_root()

## Folder induk data survei. Urutan: env WATERWAYS_SURVEY_DIR, C:/COMPE/MAGE 12/FINAL/Survey (Windows),
## lalu cadangan (folder survey_data di project / folder Survey di sebelah .exe / user://Survey).
func _resolve_root() -> String:
	var cands: Array[String] = []
	var env := OS.get_environment("WATERWAYS_SURVEY_DIR")
	if env != "":
		cands.append(env)
	if OS.get_name() == "Windows":
		cands.append(DEFAULT_ROOT)
	if OS.has_feature("editor"):
		cands.append(ProjectSettings.globalize_path("res://survey_data"))
	else:
		cands.append(OS.get_executable_path().get_base_dir().path_join("Survey"))
	cands.append(ProjectSettings.globalize_path("user://Survey"))
	for c in cands:
		DirAccess.make_dir_recursive_absolute(c)
		if DirAccess.dir_exists_absolute(c):
			# .gdignore: supaya Godot tidak meng-import CSV/PNG survei kalau foldernya di dalam project
			if c.begins_with(ProjectSettings.globalize_path("res://")):
				var g := FileAccess.open(c.path_join(".gdignore"), FileAccess.WRITE)
				if g:
					g.close()
			return c
	return ProjectSettings.globalize_path("user://")

# --- Sesi pemain ---

func begin(profile: Dictionary) -> void:
	player = profile.duplicate()
	player["id"] = _next_id()
	player["mulai"] = _now()
	player_dir = root_dir.path_join("%s_%s_%s" % [player["id"], _safe(player.get("nama", "")), _stamp()])
	DirAccess.make_dir_recursive_absolute(player_dir)
	attempts.clear()
	tutorial_pages.clear()
	tutorial_opens_menu = 0
	tutorial_opens_game = 0
	cur = {}
	world = null
	_start_ms = Time.get_ticks_msec()
	active = true
	_write_text(player_dir.path_join("profil.txt"), _profile_text())
	print("Survey: pemain %s mulai, data di %s" % [player["id"], player_dir])

func finished_count() -> int:
	return attempts.size()

func can_fill_survey() -> bool:
	return active and attempts.size() > 0

## Batalkan sesi pemain tanpa mengisi survei. Folder dipertahankan dengan akhiran _BATAL kalau sudah ada
## permainan selesai (datanya tetap ada di percobaan.csv), dihapus kalau belum ada.
func cancel() -> void:
	if not active:
		return
	_discard_current()
	if attempts.is_empty():
		_remove_dir(player_dir)
	else:
		DirAccess.rename_absolute(player_dir, player_dir + "_BATAL")
	active = false
	player = {}
	attempts.clear()

func start_game() -> void:
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(GAME_SCENE)

func open_form() -> void:
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(FORM_SCENE)

func open_profile() -> void:
	get_tree().change_scene_to_file(PROFILE_SCENE)

func to_menu() -> void:
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(MENU_SCENE)

# --- Tutorial (dipanggil ui/tutorial.gd) ---

func note_tutorial_open() -> void:
	if not active:
		return
	if _in_game():
		tutorial_opens_game += 1
	else:
		tutorial_opens_menu += 1

func note_tutorial_page(i: int, total: int) -> void:
	if not active:
		return
	tutorial_pages[i] = true
	tutorial_total = total

func _in_game() -> bool:
	return world != null and is_instance_valid(world) and world.is_inside_tree()

# --- Permainan (dipanggil world.gd) ---

func on_world_ready(w) -> void:
	if not active or w.demo_mode:
		return
	_discard_current()
	world = w
	var n := attempts.size() + 1
	cur = {"ke": n, "mulai": _now(), "mulai_ms": Time.get_ticks_msec(), "selesai": false,
		"teraliri": -1.0, "teraliri_ms": -1, "hancur_pertama": false, "kemarau": {}, "hujan": {}}
	cur_dir = player_dir.path_join("percobaan_%d" % n)
	_remove_dir(cur_dir)  # sisa percobaan tak selesai dengan nomor yang sama
	DirAccess.make_dir_recursive_absolute(cur_dir)
	_shot_n = 0
	_last_day = 0
	_poll = 0.0
	_pending.clear()
	w.tree_exiting.connect(_on_world_exit.bind(w), CONNECT_ONE_SHOT)

func _on_world_exit(w) -> void:
	if w != world:
		return
	_discard_current()
	world = null

## Percobaan yang belum selesai dibuang (tidak dihitung).
func _discard_current() -> void:
	if cur.is_empty():
		return
	if not cur.get("selesai", false):
		_wait_tasks()
		_remove_dir(cur_dir)
		print("Survey: permainan belum selesai, tidak dihitung")
	cur = {}
	cur_dir = ""

func _process(delta: float) -> void:
	_reap_tasks()
	if cur.is_empty() or cur.get("selesai", false) or not _in_game() or world.game_over:
		return
	var W = world
	var WM = W.weather
	var day: int = W.current_day()
	if day != _last_day and day <= W.target_days:
		if _last_day > 0:
			_shot("awal_hari%02d" % day)  # kondisi peta saat hari berganti (= akhir hari sebelumnya)
		else:
			_pending.append([W.elapsed + 2.0, "awal_permainan"])
		_last_day = day
		if WM.current == WM.Weather.KEMARAU:
			cur["kemarau"][day] = true
			_pending.append([W.elapsed + maxf(2.0, WM.drought_ramp_time), "kemarau_hari%02d" % day])
		elif WM.current == WM.Weather.HUJAN:
			cur["hujan"][day] = true
			_pending.append([W.elapsed + 10.0, "hujan_hari%02d" % day])
	for p in _pending.duplicate():
		if W.elapsed >= p[0]:
			_pending.erase(p)
			_shot(p[1])
	_poll += delta
	if _poll < 0.5:
		return
	_poll = 0.0
	# bangunan pertama yang teraliri lewat kanal (hujan tidak dihitung)
	if cur["teraliri"] < 0.0 and WM.current != WM.Weather.HUJAN:
		for c in W.buildings.buildings:
			var b = W.buildings.buildings[c]
			if b.state != b.State.HANCUR and W.is_cell_supplied(c):
				cur["teraliri"] = W.elapsed
				cur["teraliri_ms"] = Time.get_ticks_msec() - cur["mulai_ms"]
				_pending.append([W.elapsed + 1.0, "pertama_bangunan_teraliri"])
				break
	if not cur["hancur_pertama"] and W.buildings.destroyed_count > 0:
		cur["hancur_pertama"] = true
		_pending.append([W.elapsed + 0.5, "pertama_bangunan_hancur"])

## Dipanggil world.end_game() setelah BalanceLog menutup log-nya.
func on_game_end(w, won: bool, reason: String) -> void:
	if not active or cur.is_empty() or w != world or cur.get("selesai", false):
		return
	_shot("akhir_peta")
	var BL = w.balance_log
	var T: Dictionary = BL.total_counts if BL.enabled else {}
	var kincir := 0
	for c in w.facilities.facilities:
		if w.facilities.facilities[c]["kind"] == w.facilities.Kind.KINCIR:
			kincir += 1
	var log_name := ""
	if BL.enabled and BL.file_path != "" and FileAccess.file_exists(BL.file_path):
		log_name = BL.file_path.get_file()
		DirAccess.copy_absolute(BL.file_path, cur_dir.path_join("log_" + log_name))
	var dur_min: float = (Time.get_ticks_msec() - cur["mulai_ms"]) / 60000.0
	cur.merge({
		"selesai": true,
		"selesai_waktu": _now(),
		"durasi_menit": dur_min,
		"hasil": "MENANG" if won else "KALAH",
		"sebab": reason,
		"hari": mini(w.current_day(), w.target_days),
		"target_hari": w.target_days,
		"poin": int(w.score.total),
		"target_poin": w.score.target_points,
		"bintang": w.score.stars() if won else 0,
		"hancur": w.buildings.destroyed_count,
		"aksi_pertama": BL.first_action if BL.enabled else -1.0,
		"terancam_pertama": BL.first_threat if BL.enabled else -1.0,
		"hancur_detik": BL.first_destroy if BL.enabled else -1.0,
		"target_tercapai": BL.target_reached if BL.enabled else -1.0,
		"gali": T.get("gali", 0),
		"ratakan": T.get("ratakan_turun", 0) + T.get("ratakan_naik", 0),
		"timbun": T.get("timbun", 0),
		"pasang": T.get("pasang_fasilitas", 0),
		"bongkar": T.get("bongkar_fasilitas", 0),
		"jembatan": T.get("pasang_jembatan", 0),
		"drag": T.get("drag", 0),
		"jeda": BL._tot_pause if BL.enabled else 0.0,
		"cepat": BL._tot_fast if BL.enabled else 0.0,
		"kincir": kincir,
		"seed": w.map_seed,
		"file_log": log_name,
		"versi": BL.version if BL.enabled else "",
	}, true)
	attempts.append(cur)
	var done: Dictionary = cur
	var dir := cur_dir
	# layar akhir (panel menang/kalah) diambil sesaat setelah muncul
	get_tree().create_timer(1.2, true, false, true).timeout.connect(func():
		_shot_to(dir, "layar_akhir")
		done["screenshot"] = _count_png(dir)
		_append_attempt_row(done)
		_write_text(player_dir.path_join("ringkasan.txt"), _summary_text()))
	_add_end_buttons(w)

# --- Tombol survei di layar akhir ---

func _add_end_buttons(w) -> void:
	var ov: Control = w.hud.end_overlay
	var old := ov.get_node_or_null("SurveyBar")
	if old:
		old.queue_free()
	var bar := PanelContainer.new()
	bar.name = "SurveyBar"
	bar.theme = make_theme()
	bar.add_theme_stylebox_override("panel", _box(Color("062F48"), Color("FFC23A"), 1, 6))
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_bottom = -6
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	bar.add_child(h)
	var l := Label.new()
	l.text = "MODE SURVEI · %s · permainan ke-%d selesai" % [player.get("id", ""), attempts.size()]
	l.add_theme_color_override("font_color", Color("FFC23A"))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	var again := Button.new()
	again.text = "Main Lagi"
	again.pressed.connect(func(): w._restart())
	h.add_child(again)
	var fill := Button.new()
	fill.text = "Selesai & Isi Survei  >"
	fill.add_theme_stylebox_override("normal", _box(Color("FFC23A"), Color("FFC23A"), 0, 4))
	fill.add_theme_stylebox_override("hover", _box(Color("FFD46B"), Color("FFD46B"), 0, 4))
	fill.add_theme_color_override("font_color", Color("062F48"))
	fill.add_theme_color_override("font_hover_color", Color("062F48"))
	fill.pressed.connect(open_form)
	h.add_child(fill)
	ov.add_child(bar)

# --- Menyimpan hasil kuesioner ---

## answers: semua isian kuesioner (lihat survey_form.gd). Menulis survei.csv + ringkasan.txt.
func submit(answers: Dictionary) -> String:
	_wait_tasks()
	var row := {}
	for k in SURVEY_COLUMNS:
		row[k] = ""
	row["id_pemain"] = player.get("id", "")
	row["nama"] = player.get("nama", "")
	row["waktu_mulai"] = player.get("mulai", "")
	row["waktu_selesai"] = _now()
	row["durasi_sesi_menit"] = "%.1f" % ((Time.get_ticks_msec() - _start_ms) / 60000.0)
	for k in ["umur", "status", "frekuensi_main_game", "pengalaman_game_serupa", "platform_utama",
			"paham_air_sebelum", "persetujuan_data"]:
		row[k] = str(player.get(k, ""))
	row["tutorial_dibuka_di_menu"] = tutorial_opens_menu
	row["tutorial_dibuka_saat_main"] = tutorial_opens_game
	row["tutorial_halaman_dilihat"] = tutorial_pages.size()
	row["tutorial_halaman_total"] = tutorial_total
	# ringkasan permainan
	var wins := 0
	var best: Dictionary = {}
	var mins := 0.0
	var sums := {"gali": 0, "ratakan": 0, "timbun": 0, "pasang": 0, "jembatan": 0, "hancur": 0}
	var kem := 0
	var huj := 0
	for a in attempts:
		if a["hasil"] == "MENANG":
			wins += 1
		if best.is_empty() or _rank(a) > _rank(best):
			best = a
		mins += a["durasi_menit"]
		for k in sums:
			sums[k] += int(a[k])
		kem = maxi(kem, a["kemarau"].size())
		huj = maxi(huj, a["hujan"].size())
	row["jumlah_permainan"] = attempts.size()
	row["jumlah_menang"] = wins
	row["total_menit_bermain"] = "%.1f" % mins
	if not best.is_empty():
		row["hasil_terbaik"] = best["hasil"]
		row["hari_terjauh"] = _max_of("hari")
		row["poin_terbaik"] = _max_of("poin")
		row["bintang_terbaik"] = _max_of("bintang")
	if not attempts.is_empty():
		var p1: Dictionary = attempts[0]
		row["p1_hasil"] = p1["hasil"]
		row["p1_sebab"] = p1["sebab"]
		row["p1_hari"] = p1["hari"]
		row["p1_poin"] = p1["poin"]
		row["p1_hancur"] = p1["hancur"]
		row["p1_detik_aksi_pertama"] = _sec(p1["aksi_pertama"])
		row["p1_detik_bangunan_teraliri_pertama"] = _sec(p1["teraliri"])
		row["p1_menit_nyata_bangunan_teraliri_pertama"] = ("%.2f" % (p1["teraliri_ms"] / 60000.0)) if p1["teraliri_ms"] >= 0 else ""
		var last: Dictionary = attempts[-1]
		row["terakhir_hasil"] = last["hasil"]
		row["terakhir_sebab"] = last["sebab"]
		row["terakhir_hari"] = last["hari"]
		row["terakhir_poin"] = last["poin"]
		row["versi_build"] = last.get("versi", "")
	row["total_gali"] = sums["gali"]
	row["total_ratakan"] = sums["ratakan"]
	row["total_timbun"] = sums["timbun"]
	row["total_pasang_fasilitas"] = sums["pasang"]
	row["total_jembatan"] = sums["jembatan"]
	row["total_bangunan_hancur"] = sums["hancur"]
	row["kemarau_dialami_maks"] = kem
	row["hujan_dialami_maks"] = huj
	# jawaban kuesioner
	for k in answers:
		if row.has(k):
			row[k] = _clean(str(answers[k]))
	if str(answers.get("paham_air_sesudah", "")) != "" and str(player.get("paham_air_sebelum", "")) != "":
		row["selisih_paham_air"] = int(answers["paham_air_sesudah"]) - int(player["paham_air_sebelum"])
	if str(answers.get("nps", "")) != "":
		var n := int(answers["nps"])
		row["kategori_nps"] = "promoter" if n >= 9 else ("passive" if n >= 7 else "detractor")
	var score := 0
	for k in ["q_spillway_benar", "q_kemarau_benar", "q_dataran_tinggi_benar"]:
		score += int(answers.get(k, 0))
	row["skor_pemahaman_0_3"] = score
	row["folder_pemain"] = player_dir.get_file()
	var vals: Array = []
	for k in SURVEY_COLUMNS:
		vals.append(row[k])
	_append_csv(root_dir.path_join("survei.csv"), SURVEY_COLUMNS, vals)
	_write_text(player_dir.path_join("ringkasan.txt"), _summary_text(row))
	var id: String = player.get("id", "")
	active = false
	player = {}
	attempts.clear()
	print("Survey: survei %s tersimpan" % id)
	return id

func _rank(a: Dictionary) -> float:
	return (1000000.0 if a["hasil"] == "MENANG" else 0.0) + a["bintang"] * 100000.0 + a["hari"] * 1000.0 + a["poin"] * 0.001

func _max_of(k: String) -> int:
	var m := 0
	for a in attempts:
		m = maxi(m, int(a[k]))
	return m

func _append_attempt_row(a: Dictionary) -> void:
	var vals := [player.get("id", ""), player.get("nama", ""), a["ke"], a["mulai"], a["selesai_waktu"],
		"%.1f" % a["durasi_menit"], a["hasil"], a["sebab"], a["hari"], a["target_hari"], a["poin"], a["target_poin"],
		a["bintang"], a["hancur"], _sec(a["aksi_pertama"]), _sec(a["teraliri"]),
		("%.2f" % (a["teraliri_ms"] / 60000.0)) if a["teraliri_ms"] >= 0 else "",
		_sec(a["terancam_pertama"]), _sec(a["hancur_detik"]), _sec(a["target_tercapai"]),
		a["kemarau"].size(), a["hujan"].size(),
		a["gali"], a["ratakan"], a["timbun"], a["pasang"], a["bongkar"], a["jembatan"], a["drag"],
		"%.1f" % a["jeda"], "%.1f" % a["cepat"], a["kincir"], a["seed"], a.get("screenshot", 0),
		player_dir.get_file() + "/percobaan_%d" % a["ke"], a["file_log"]]
	_append_csv(root_dir.path_join("percobaan.csv"), ATTEMPT_COLUMNS, vals)

# --- Screenshot ---

func _shot(label: String) -> void:
	_shot_to(cur_dir, label)

func _shot_to(dir: String, label: String) -> void:
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return
	var tex := get_viewport().get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		return
	_shot_n += 1
	var path := dir.path_join("%02d_%s.png" % [_shot_n, label])
	_tasks.append(WorkerThreadPool.add_task(func(): img.save_png(path), false, "survey screenshot"))

func _reap_tasks() -> void:
	for t in _tasks.duplicate():
		if WorkerThreadPool.is_task_completed(t):
			WorkerThreadPool.wait_for_task_completion(t)
			_tasks.erase(t)

func _wait_tasks() -> void:
	for t in _tasks:
		WorkerThreadPool.wait_for_task_completion(t)
	_tasks.clear()

func _count_png(dir: String) -> int:
	_wait_tasks()
	var n := 0
	var d := DirAccess.open(dir)
	if d:
		for f in d.get_files():
			if f.ends_with(".png"):
				n += 1
	return n

# --- File ---

## Tambah satu baris ke CSV (UTF-8 + BOM). Kalau header file lama berbeda, file lama diganti namanya.
func _append_csv(path: String, header: Array, values: Array) -> void:
	var head := PackedStringArray()
	for h in header:
		head.append(str(h))
	if FileAccess.file_exists(path):
		var f0 := FileAccess.open(path, FileAccess.READ)
		var first := f0.get_line().trim_prefix("\uFEFF").strip_edges() if f0 else ""
		if f0:
			f0.close()
		if first != ",".join(head):
			DirAccess.rename_absolute(path, path.get_basename() + "_format_lama_%s.csv" % _stamp())
	var is_new := not FileAccess.file_exists(path)
	var f := FileAccess.open(path, FileAccess.WRITE if is_new else FileAccess.READ_WRITE)
	if f == null:
		push_warning("Survey: tidak bisa menulis %s (file sedang dibuka di Excel?)" % path)
		_append_csv_fallback(path, head, values)
		return
	if is_new:
		f.store_string("\uFEFF")
		f.store_csv_line(head)
	f.seek_end()
	var row := PackedStringArray()
	for v in values:
		row.append(_clean(str(v)))
	f.store_csv_line(row)
	f.close()

## File CSV terkunci (misalnya sedang dibuka di Excel): tulis ke file cadangan supaya data tidak hilang.
func _append_csv_fallback(path: String, head: PackedStringArray, values: Array) -> void:
	var alt := path.get_basename() + "_cadangan_%s.csv" % _stamp()
	var f := FileAccess.open(alt, FileAccess.WRITE)
	if f == null:
		return
	f.store_string("\uFEFF")
	f.store_csv_line(head)
	var row := PackedStringArray()
	for v in values:
		row.append(_clean(str(v)))
	f.store_csv_line(row)
	f.close()

func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()

func _remove_dir(dir: String) -> void:
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return
	var d := DirAccess.open(dir)
	if d:
		for f in d.get_files():
			DirAccess.remove_absolute(dir.path_join(f))
		for sub in d.get_directories():
			_remove_dir(dir.path_join(sub))
	DirAccess.remove_absolute(dir)

func _next_id() -> String:
	var mx := 0
	var d := DirAccess.open(root_dir)
	if d:
		for n in d.get_directories():
			if n.length() >= 4 and n[0] == "P" and n.substr(1, 3).is_valid_int():
				mx = maxi(mx, n.substr(1, 3).to_int())
	var csv := root_dir.path_join("survei.csv")
	if FileAccess.file_exists(csv):
		var f := FileAccess.open(csv, FileAccess.READ)
		while f and not f.eof_reached():
			var line := f.get_csv_line()
			if line.size() > 0:
				var id := line[0].trim_prefix("\uFEFF")
				if id.length() >= 4 and id[0] == "P" and id.substr(1, 3).is_valid_int():
					mx = maxi(mx, id.substr(1, 3).to_int())
	return "P%03d" % (mx + 1)

func _profile_text() -> String:
	var lines := PackedStringArray([
		"WATERWAYS — Profil pemain (Mode Survei)",
		"ID            : %s" % player.get("id", ""),
		"Nama          : %s" % player.get("nama", ""),
		"Mulai         : %s" % player.get("mulai", ""),
		"Umur          : %s" % player.get("umur", ""),
		"Status        : %s" % player.get("status", ""),
		"Main game     : %s" % player.get("frekuensi_main_game", ""),
		"Game serupa   : %s" % player.get("pengalaman_game_serupa", ""),
		"Platform      : %s" % player.get("platform_utama", ""),
		"Paham air (sebelum main, 1-5): %s" % player.get("paham_air_sebelum", ""),
		"Persetujuan data: %s" % player.get("persetujuan_data", ""),
	])
	return "\n".join(lines) + "\n"

func _summary_text(survey_row: Dictionary = {}) -> String:
	var s := _profile_text() + "\nPermainan selesai: %d\n" % attempts.size()
	for a in attempts:
		s += "  #%d  %s (%s)  hari %d/%d  poin %d/%d  bintang %d  hancur %d  %.1f menit  aksi pertama %s  teraliri pertama %s\n" % [
			a["ke"], a["hasil"], a["sebab"], a["hari"], a["target_hari"], a["poin"], a["target_poin"],
			a["bintang"], a["hancur"], a["durasi_menit"], _sec_txt(a["aksi_pertama"]), _sec_txt(a["teraliri"])]
	if not survey_row.is_empty():
		s += "\nKuesioner:\n"
		for k in SURVEY_COLUMNS:
			if k.begins_with("r_") or k.begins_with("q_") or k in ["paham_air_sesudah", "selisih_paham_air",
					"kesulitan", "nps", "kategori_nps", "skor_pemahaman_0_3", "kesan", "pesan_saran",
					"bagian_paling_seru", "bagian_paling_membingungkan", "durasi_sesi_menit"]:
				s += "  %s: %s\n" % [k, str(survey_row[k])]
	return s

# --- Util ---

func _sec(v: float) -> String:
	return "%.1f" % v if v >= 0.0 else ""

func _sec_txt(v: float) -> String:
	return "detik ke-%.0f" % v if v >= 0.0 else "-"

func _clean(s: String) -> String:
	return s.replace("\r", " ").replace("\n", " / ").replace("\t", " ").strip_edges()

func _safe(s: String) -> String:
	var out := ""
	for ch in s.strip_edges():
		out += ch if (ch.is_valid_identifier() or ch.is_valid_int() or ch == "-") else "_"
	out = out.substr(0, 24)
	return out if out != "" else "anon"

func _now() -> String:
	return Time.get_datetime_string_from_system(false, true)

func _stamp() -> String:
	var t := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d_%02d-%02d-%02d" % [t.year, t.month, t.day, t.hour, t.minute, t.second]

# --- Tampilan bersama (dipakai layar profil, kuesioner, menu) ---

const C_BG := Color("062F48")
const C_PANEL := Color("094466")
const C_CREAM := Color("EEEBE4")
const C_YELLOW := Color("FFC23A")
const C_BROWN := Color("9D6448")
const C_RED := Color("E0483E")

func make_theme() -> Theme:
	var base: Theme = load(THEME_PATH)
	var t: Theme = base.duplicate() if base else Theme.new()
	t.set_stylebox("normal", "Button", _box(Color("0B5580"), Color(1, 1, 1, 0.25), 1, 3))
	t.set_stylebox("hover", "Button", _box(Color("1A6A99"), Color(1, 1, 1, 0.5), 1, 3))
	t.set_stylebox("pressed", "Button", _box(C_YELLOW, C_YELLOW, 1, 3))
	t.set_stylebox("hover_pressed", "Button", _box(Color("FFD46B"), Color("FFD46B"), 1, 3))
	t.set_stylebox("disabled", "Button", _box(Color(0.2, 0.25, 0.3, 0.6), Color(1, 1, 1, 0.1), 1, 3))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_pressed_color", "Button", C_BG)
	t.set_color("font_hover_pressed_color", "Button", C_BG)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.35))
	for cls in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", cls, _box(Color("04263A"), Color(1, 1, 1, 0.3), 1, 3))
		t.set_stylebox("focus", cls, _box(Color("04263A"), C_YELLOW, 1, 3))
		t.set_color("font_color", cls, C_CREAM)
		t.set_color("font_placeholder_color", cls, Color(1, 1, 1, 0.35))
	t.set_stylebox("normal", "OptionButton", _box(Color("0B5580"), Color(1, 1, 1, 0.25), 1, 3))
	t.set_stylebox("hover", "OptionButton", _box(Color("1A6A99"), Color(1, 1, 1, 0.5), 1, 3))
	t.set_stylebox("pressed", "OptionButton", _box(Color("1A6A99"), C_YELLOW, 1, 3))
	t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	t.set_color("font_pressed_color", "OptionButton", C_CREAM)
	return t

func _box(bg: Color, border: Color, bw: int, pad: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(3)
	s.content_margin_left = pad + 2
	s.content_margin_right = pad + 2
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	return s
