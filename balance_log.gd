extends Node
## Log balancing otomatis (node BalanceLog di world.tscn).
## Setiap kali game dimainkan, dibuat SATU file CSV baru yang namanya berisi tanggal & jam mulai,
## misalnya  playtest_logs/sesi_2026-10-05_13-20-41_Zhan.csv
##
## Isi file sesi:
##   - 2 baris header (#): sesi, penguji, versi build, seed, param_id, lalu SEMUA angka balancing (PARAM)
##   - AKHIR_HARI : satu baris per hari (snapshot + agregat sepanjang hari: aksi, waktu terancam,
##                  persen waktu teraliri, banjir/kering terparah, putaran kincir, tempo jeda/2x/menu)
##   - PERTAMA    : momen pertama (aksi pertama, bangunan pertama terancam/hancur, target tercapai)
##   - HANCUR     : tiap bangunan hancur + penyebabnya
##   - DEBUG      : pemakaian tombol F1-F3
##   - AKHIR      : hasil permainan;  SURVEI : jawaban survei layar akhir
## playtest_logs/ringkasan_<penguji>.csv : satu baris per sesi (cocok untuk dibandingkan di spreadsheet).
##
## Hanya sesi yang SELESAI (MENANG / KALAH) yang disimpan. Sesi yang ditinggalkan (Main Ulang,
## Menu Utama, tombol X, Stop di editor, crash) otomatis dihapus, termasuk barisnya di ringkasan.
## Semua nama file unik per penguji/sesi, jadi folder ini aman di-commit ke git tanpa konflik.
##
## Lokasi folder:
##   - dijalankan dari editor Godot  -> folder project (isometric-waterways/playtest_logs/)
##   - dari hasil export (.exe)       -> di sebelah file .exe (playtest_logs/)
## Tekan F4 saat bermain untuk membuka foldernya.

@export var enabled: bool = true
## Hapus otomatis log sesi yang tidak selesai (ditinggalkan lewat menu, tombol X, Stop di editor,
## atau crash), supaya folder log hanya berisi sesi MENANG / KALAH.
@export var delete_unfinished: bool = true
## Nama penguji (opsional). Kosong = pakai nama user komputer.
@export var tester_name: String = ""
## Tampilkan survei 2 pertanyaan (tegang/adil 1-5) di layar akhir.
@export var end_survey: bool = true
## Detik (waktu game) antar pengambilan sampel kondisi air.
@export var sample_interval: float = 0.5

const COLUMNS := [
	"jenis", "hari", "detik_game", "jam_nyata", "cuaca", "tingkat_kemarau",
	"poin_total", "poin_hari_ini", "poin_bangunan", "poin_kincir", "poin_bonus", "poin_jembatan",
	"bangunan_total", "hidup", "terancam", "hancur",
	"sekop_terpakai_hari_ini", "sekop_sisa", "kanal_digali", "persen_kanal_berair",
	"stok_bor", "stok_bendungan", "stok_spillway", "stok_kincir",
	"terpasang_bor", "terpasang_bendungan", "terpasang_spillway", "terpasang_kincir", "jembatan",
	# --- agregat sepanjang hari ---
	"aksi_gali", "aksi_ratakan_turun", "aksi_ratakan_naik", "aksi_timbun",
	"pasang_fasilitas", "bongkar_fasilitas", "pasang_jembatan", "lepas_jembatan", "drag",
	"detik_bangunan_terancam", "bangunan_pernah_terancam", "persen_waktu_teraliri",
	"banjir_maks_petak", "persen_sumber_kering_maks", "putaran_kincir_rata",
	"jeda_detik", "cepat2x_detik", "menu_detik", "gagal_spawn",
	"keterangan",
]
const ACTION_KEYS := ["gali", "ratakan_turun", "ratakan_naik", "timbun", "pasang_fasilitas",
	"bongkar_fasilitas", "pasang_jembatan", "lepas_jembatan"]
const COUNT_KEYS := ["gali", "ratakan_turun", "ratakan_naik", "timbun", "pasang_fasilitas",
	"bongkar_fasilitas", "pasang_jembatan", "lepas_jembatan", "drag", "gagal_spawn"]
const SUMMARY_COLUMNS := [
	"sesi", "penguji", "versi", "param_id", "seed", "hasil", "sebab", "hari", "detik_game",
	"poin", "target", "hancur", "kincir_terpasang",
	"detik_aksi_pertama", "hari_terancam_pertama", "detik_terancam_pertama", "detik_hancur_pertama",
	"detik_target_tercapai",
	"total_gali", "total_ratakan", "total_timbun", "total_pasang_fasilitas", "total_drag",
	"jeda_total_detik", "cepat2x_total_detik", "menu_total_detik", "gagal_spawn_total",
	"survei_tegang", "survei_adil", "saran", "file_log",
]

var world
var session_id: String = ""
var tester: String = ""
var version: String = ""
var params_text: String = ""
var param_id: String = ""
var file_path: String = ""
var folder: String = ""
var _file: FileAccess
var _ended := false

# agregat per hari (direset tiap akhir hari) dan total per sesi
var day_counts := {}
var total_counts := {}
var _threat_s := 0.0          # detik-bangunan berstatus terancam
var _alive_s := 0.0           # detik-bangunan hidup (penyebut persen teraliri)
var _supplied_s := 0.0        # detik-bangunan teraliri
var _ever_threat := {}        # petak bangunan yang pernah terancam hari ini
var _flood_max := 0
var _dry_max := 0.0
var _kincir_sum := 0.0
var _kincir_n := 0
var _pause_s := 0.0
var _fast_s := 0.0
var _menu_s := 0.0
var _tot_pause := 0.0
var _tot_fast := 0.0
var _tot_menu := 0.0
var _sample_t := 0.0
var _last_us := 0
# momen pertama (detik game, -1 = belum terjadi)
var first_action := -1.0
var first_threat := -1.0
var first_threat_day := -1
var first_destroy := -1.0
var target_reached := -1.0
var _summary_row := []

func setup(w) -> void:
	world = w
	if not enabled or world.demo_mode:
		enabled = false
		return
	tester = tester_name.strip_edges()
	if tester == "":
		tester = OS.get_environment("USERNAME")
	if tester == "":
		tester = OS.get_environment("USER")
	if tester == "":
		tester = "anon"
	var t := Time.get_datetime_dict_from_system()
	session_id = "%04d-%02d-%02d_%02d-%02d-%02d" % [t.year, t.month, t.day, t.hour, t.minute, t.second]
	folder = _log_folder()
	DirAccess.make_dir_recursive_absolute(folder)
	if delete_unfinished:
		_cleanup_unfinished()
	# .gdignore: supaya Godot tidak mencoba meng-import CSV log sebagai file terjemahan
	if not FileAccess.file_exists(folder.path_join(".gdignore")):
		var g := FileAccess.open(folder.path_join(".gdignore"), FileAccess.WRITE)
		if g:
			g.close()
	file_path = folder.path_join("sesi_%s_%s.csv" % [session_id, _safe(tester)])
	_file = FileAccess.open(file_path, FileAccess.WRITE)
	if _file == null:
		push_warning("BalanceLog: tidak bisa menulis %s" % file_path)
		enabled = false
		return
	for k in COUNT_KEYS:
		day_counts[k] = 0
		total_counts[k] = 0
	version = _build_version()
	params_text = _params_snapshot()
	param_id = "%08x" % (params_text.hash() & 0xffffffff)
	_file.store_line("# WATERWAYS playtest | sesi %s | penguji %s | versi %s | seed %d | param_id %s" \
		% [session_id, tester, version, world.map_seed, param_id])
	_file.store_line("# PARAM | " + params_text)
	_file.store_csv_line(PackedStringArray(COLUMNS))
	_file.flush()
	_last_us = Time.get_ticks_usec()
	print("BalanceLog: ", file_path)

# --- Versi & parameter ---

## Hash commit git (7 karakter) saat dijalankan dari project, atau versi project kalau hasil export.
func _build_version() -> String:
	var git := ProjectSettings.globalize_path("res://.git")
	if OS.has_feature("editor") and DirAccess.dir_exists_absolute(git):
		var head := FileAccess.get_file_as_string(git.path_join("HEAD")).strip_edges()
		var branch := ""
		var sha := head
		if head.begins_with("ref: "):
			var ref := head.substr(5)
			branch = ref.get_file()
			sha = FileAccess.get_file_as_string(git.path_join(ref)).strip_edges()
			if sha == "":
				var packed := FileAccess.get_file_as_string(git.path_join("packed-refs"))
				for line in packed.split("\n"):
					if line.ends_with(" " + ref):
						sha = line.split(" ")[0]
		if sha.length() >= 7:
			return "%s@%s" % [branch, sha.substr(0, 7)] if branch != "" else sha.substr(0, 7)
	var v: String = str(ProjectSettings.get_setting("application/config/version", ""))
	return v if v != "" else "export"

## Semua angka balancing yang berlaku di sesi ini, sebagai satu baris "nama=nilai; ...".
func _params_snapshot() -> String:
	var W = world
	var F = W.facilities
	var WM = W.weather
	var WS = W.water
	var B = W.buildings
	var sched := ""
	for d in range(1, W.target_days + 1):
		sched += ["C", "K", "H"][WM.weather_for(d)]
	var probe = B.building_scene.instantiate()
	var p := {
		"day_length": W.day_length, "target_days": W.target_days, "damage_quota": W.damage_quota,
		"shovel_per_day": W.shovel_per_day, "max_drag_length": W.max_drag_length,
		"target_points": W.score.target_points, "star2_points": W.score.star2_points, "star3_points": W.score.star3_points, "supplied_per_second": W.score.supplied_per_second,
		"day_bonus_per_building": W.score.day_bonus_per_building, "day_bonus_min_supplied": W.score.day_bonus_min_supplied, "bridge_bonus_per_day": W.score.bridge_bonus_per_day,
		"start_stock": F.start_stock, "stock_per_forecast": F.stock_per_forecast,
		"kincir_full_flux": F.kincir_full_flux, "kincir_points_per_second": F.kincir_points_per_second,
		"bridges_start": W.roads.bridges_start, "bridges_per_day": W.roads.bridges_per_day,
		"buildings_first_day": B.buildings_first_day, "spawn_rate_start": B.spawn_rate_start, "spawn_rate_end": B.spawn_rate_end, "expansion_steps": W.expansion_steps, "expand_every_days": W.expand_every_days,
		"farm_chance": B.farm_chance, "min_building_spacing": B.min_building_spacing,
		"min_water_distance": B.min_water_distance, "max_water_distance_start": B.max_water_distance_start,
		"max_water_distance_end": B.max_water_distance_end,
		"max_water_rumah": probe.TYPE_DATA[probe.Type.RUMAH]["max_water"],
		"max_water_ladang": probe.TYPE_DATA[probe.Type.LADANG]["max_water"],
		"flood_limit": probe.flood_limit,
		"schedule": sched, "rain_surge": WM.rain_surge,
		"drought_severity_start": WM.drought_severity_start, "drought_severity_step": WM.drought_severity_step,
		"drought_severity_max": WM.drought_severity_max, "drought_ramp_time": WM.drought_ramp_time,
		"drought_small_body": WM.drought_small_body, "drought_small_mult": WM.drought_small_mult,
		"flow_k": WS.flow_k, "channel_depth": WS.channel_depth, "source_rate": WS.source_rate,
		"canal_evaporation": WS.canal_evaporation, "land_absorb": WS.land_absorb,
		"spillway_crest": WS.spillway_crest, "wet_threshold": WS.wet_threshold, "flood_threshold": WS.flood_threshold,
	}
	probe.free()
	var parts := PackedStringArray()
	for k in p:
		parts.append("%s=%s" % [k, str(p[k])])
	return "; ".join(parts)

# --- File & folder ---

## Hapus file sesi lama yang tidak selesai: tanpa baris AKHIR (game ditutup paksa / Stop di editor /
## crash) atau berakhir DITINGGALKAN. Baris DITINGGALKAN di file ringkasan juga dibuang.
func _cleanup_unfinished() -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for f in dir.get_files():
		if not f.ends_with(".csv"):
			continue
		var path := folder.path_join(f)
		var text := FileAccess.get_file_as_string(path)
		if f.begins_with("sesi_"):
			var finished: bool = "\nAKHIR," in text or text.begins_with("AKHIR,")
			if not finished or "DITINGGALKAN" in text:
				DirAccess.remove_absolute(path)
				print("BalanceLog: log tidak selesai dihapus: ", f)
		elif f.begins_with("ringkasan_") and ",DITINGGALKAN," in text:
			var kept: PackedStringArray = []
			for line in text.split("\n"):
				if not ",DITINGGALKAN," in line:
					kept.append(line)
			var w := FileAccess.open(path, FileAccess.WRITE)
			if w:
				w.store_string("\n".join(kept))
				w.close()

## Buang log sesi ini (dipakai saat game ditutup sebelum selesai).
func discard() -> void:
	if not enabled or _ended:
		return
	_ended = true
	if _file:
		_file.close()
	DirAccess.remove_absolute(file_path)
	print("BalanceLog: sesi ditutup sebelum selesai, log dihapus: ", file_path.get_file())

func _log_folder() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://playtest_logs")
	return OS.get_executable_path().get_base_dir().path_join("playtest_logs")

func _safe(s: String) -> String:
	var out := ""
	for ch in s:
		out += ch if (ch.is_valid_identifier() or ch.is_valid_int() or ch == "-") else "_"
	return out

func open_folder() -> void:
	if folder != "":
		OS.shell_open(folder)

# --- Pencatatan dari sistem lain ---

## Hitung satu aksi/kejadian (dipanggil world.gd, building_manager.gd).
func count(key: String, n: int = 1) -> void:
	if not enabled or _ended:
		return
	day_counts[key] = day_counts.get(key, 0) + n
	total_counts[key] = total_counts.get(key, 0) + n
	if key in ACTION_KEYS and first_action < 0.0:
		first_action = world.elapsed
		_write(_row("PERTAMA", world.current_day(), "aksi pertama pemain (%s)" % key))

## Pengambilan sampel tiap frame: waktu terancam/teraliri, tempo, kondisi air.
func _process(delta: float) -> void:
	if not enabled or _ended or world == null:
		return
	var now := Time.get_ticks_usec()
	var real_dt := (now - _last_us) / 1000000.0
	_last_us = now
	if world.game_over:
		return
	# tempo pemain (waktu nyata)
	if world.hud.pause_menu.visible:
		_menu_s += real_dt
		_tot_menu += real_dt
	elif Engine.time_scale == 0.0:
		_pause_s += real_dt
		_tot_pause += real_dt
	elif Engine.time_scale > 1.5:
		_fast_s += real_dt
		_tot_fast += real_dt
	if delta <= 0.0:
		return
	# bangunan (waktu game)
	var rain: bool = world.weather.current == world.weather.Weather.HUJAN
	for c in world.buildings.buildings:
		var b = world.buildings.buildings[c]
		if b.state == b.State.HANCUR:
			continue
		_alive_s += delta
		if rain or world.is_cell_supplied(c):
			_supplied_s += delta
		if b.state == b.State.TERANCAM:
			_threat_s += delta
			_ever_threat[c] = true
			if first_threat < 0.0:
				first_threat = world.elapsed
				first_threat_day = world.current_day()
				_write(_row("PERTAMA", first_threat_day, "bangunan pertama terancam di %s" % str(c)))
	if target_reached < 0.0 and world.score.reached():
		target_reached = world.elapsed
		_write(_row("PERTAMA", world.current_day(), "target poin tercapai"))
	# kondisi air
	_sample_t += delta
	if _sample_t >= sample_interval:
		_sample_t = 0.0
		_sample_water()

func _sample_water() -> void:
	var WS = world.water
	var flooded := 0
	for c in WS.cells:
		if WS.is_flooded(c):
			flooded += 1
	_flood_max = maxi(_flood_max, flooded)
	var nat := 0
	var dry := 0
	for c in WS.body_of:
		nat += 1
		if not WS.is_wet(c):
			dry += 1
	if nat > 0:
		_dry_max = maxf(_dry_max, float(dry) / nat)
	var F = world.facilities
	for c in F.facilities:
		if F.facilities[c]["kind"] == F.Kind.KINCIR:
			_kincir_sum += F.kincir_power(c)
			_kincir_n += 1

func _row(kind: String, day: int, note: String = "") -> Array:
	var W = world
	var S = W.score
	var F = W.facilities
	var alive := 0
	var threat := 0
	for c in W.buildings.buildings:
		var b = W.buildings.buildings[c]
		if b.state == b.State.HIDUP:
			alive += 1
		elif b.state == b.State.TERANCAM:
			threat += 1
	var placed := [0, 0, 0, 0]
	for c in F.facilities:
		placed[F.facilities[c]["kind"]] += 1
	var chan := 0
	var wet := 0
	for c in W.dug:
		chan += 1
		if W.water.is_wet(c):
			wet += 1
	var t := Time.get_time_dict_from_system()
	var row := [
		kind, day, "%.1f" % W.elapsed, "%02d:%02d:%02d" % [t.hour, t.minute, t.second],
		W.weather.NAMES[W.weather.current], W.weather.drought_index(day),
		int(S.total), int(S.today),
		int(S.by_source.get("Bangunan teraliri", 0.0)), int(S.by_source.get("Kincir air", 0.0)),
		int(S.by_source.get("Bonus akhir hari", 0.0)), int(S.by_source.get("Jembatan", 0.0)),
		W.buildings.buildings.size(), alive, threat, W.buildings.destroyed_count,
		W.shovel_used, W.shovel, chan, (int(100.0 * wet / chan) if chan > 0 else 0),
		F.stock[0], F.stock[1], F.stock[2], F.stock[3],
		placed[0], placed[1], placed[2], placed[3], W.roads.bridges.size(),
	]
	for k in ["gali", "ratakan_turun", "ratakan_naik", "timbun", "pasang_fasilitas",
			"bongkar_fasilitas", "pasang_jembatan", "lepas_jembatan", "drag"]:
		row.append(day_counts.get(k, 0))
	row.append_array([
		"%.1f" % _threat_s, _ever_threat.size(),
		(int(100.0 * _supplied_s / _alive_s) if _alive_s > 0.0 else 100),
		_flood_max, int(_dry_max * 100.0),
		("%.2f" % (_kincir_sum / _kincir_n) if _kincir_n > 0 else "0"),
		"%.1f" % _pause_s, "%.1f" % _fast_s, "%.1f" % _menu_s,
		day_counts.get("gagal_spawn", 0),
		note,
	])
	return row

func _write(row: Array) -> void:
	if not enabled or _file == null or _ended:
		return
	var out := PackedStringArray()
	for v in row:
		out.append(str(v))
	_file.store_csv_line(out)
	_file.flush()  # langsung tersimpan walau game ditutup paksa

func _reset_day() -> void:
	for k in COUNT_KEYS:
		day_counts[k] = 0
	_threat_s = 0.0
	_alive_s = 0.0
	_supplied_s = 0.0
	_ever_threat.clear()
	_flood_max = 0
	_dry_max = 0.0
	_kincir_sum = 0.0
	_kincir_n = 0
	_pause_s = 0.0
	_fast_s = 0.0
	_menu_s = 0.0

## Dipanggil world.gd tepat sebelum hari berganti (setelah bonus akhir hari).
func log_day_end(day: int) -> void:
	_write(_row("AKHIR_HARI", day))
	_reset_day()

## Dipanggil saat bangunan hancur.
func log_destroyed(b) -> void:
	var cause := "kekeringan" if b.water <= 0.0 else "banjir"
	if first_destroy < 0.0 and enabled and not _ended:
		first_destroy = world.elapsed
		_write(_row("PERTAMA", world.current_day(), "bangunan pertama hancur"))
	_write(_row("HANCUR", world.current_day(), "%s %s di %s" % [b.TYPE_DATA[b.type]["name"], cause, str(b.cell)]))

## Catatan bebas (misalnya pemakaian tombol debug), supaya data sesi itu bisa ditandai.
func log_note(kind: String, note: String) -> void:
	_write(_row(kind, world.current_day(), note))

## Dipanggil saat permainan selesai (menang/kalah) atau ditinggalkan lewat menu.
func log_end(result: String, reason: String) -> void:
	if not enabled or _ended:
		return
	if result == "DITINGGALKAN" and delete_unfinished:
		discard()  # hanya sesi MENANG / KALAH yang disimpan
		return
	var day: int = mini(world.current_day(), world.target_days)
	if result == "MENANG" and target_reached < 0.0:
		target_reached = world.elapsed
	_write(_row("AKHIR", day, "%s %s" % [result, reason]))
	_ended = true
	_file.close()
	var kincir := 0
	for c in world.facilities.facilities:
		if world.facilities.facilities[c]["kind"] == world.facilities.Kind.KINCIR:
			kincir += 1
	var T := total_counts
	_summary_row = [session_id, tester, version, param_id, str(world.map_seed), result, reason, str(day),
		"%.1f" % world.elapsed, str(int(world.score.total)), str(world.score.target_points),
		str(world.buildings.destroyed_count), str(kincir),
		_t(first_action), str(first_threat_day if first_threat_day > 0 else ""), _t(first_threat), _t(first_destroy),
		_t(target_reached),
		str(T.get("gali", 0)), str(T.get("ratakan_turun", 0) + T.get("ratakan_naik", 0)), str(T.get("timbun", 0)),
		str(T.get("pasang_fasilitas", 0)), str(T.get("drag", 0)),
		"%.1f" % _tot_pause, "%.1f" % _tot_fast, "%.1f" % _tot_menu, str(T.get("gagal_spawn", 0)),
		"", "", "", file_path.get_file()]
	_append_summary()
	if end_survey and result != "DITINGGALKAN":
		var s = world.hud.get_node_or_null("Overlay/EndSurvey")
		if s:
			s.show()
			if not s.answered.is_connected(log_survey):
				s.answered.connect(log_survey)

func _t(v: float) -> String:
	return "%.1f" % v if v >= 0.0 else ""

func _summary_path() -> String:
	return folder.path_join("ringkasan_%s.csv" % _safe(tester))  # satu file per penguji: aman di-commit tanpa konflik

func _append_summary() -> void:
	var path := _summary_path()
	var header := ",".join(PackedStringArray(SUMMARY_COLUMNS))
	if FileAccess.file_exists(path):
		var first := FileAccess.get_file_as_string(path).split("\n")[0].strip_edges()
		if first != header:
			# format ringkasan lama: simpan dengan nama lain, mulai file baru
			var old := path.get_basename() + "_format_lama_%s.csv" % session_id
			DirAccess.rename_absolute(path, old)
	var is_new := not FileAccess.file_exists(path)
	var f := FileAccess.open(path, FileAccess.READ_WRITE if not is_new else FileAccess.WRITE)
	if f == null:
		return
	if is_new:
		f.store_csv_line(PackedStringArray(SUMMARY_COLUMNS))
	f.seek_end()
	f.store_csv_line(PackedStringArray(_summary_row))
	f.close()

## Jawaban survei layar akhir: ditambahkan ke file sesi (baris SURVEI) dan ke baris ringkasan sesi ini.
func log_survey(tegang: int, adil: int, saran: String = "") -> void:
	saran = saran.replace("\r", " ").replace("\n", " / ").strip_edges()
	var f := FileAccess.open(file_path, FileAccess.READ_WRITE)
	if f:
		f.seek_end()
		var r := PackedStringArray()
		r.resize(COLUMNS.size())
		r[0] = "SURVEI"
		r[COLUMNS.size() - 1] = "tegang=%s adil=%s saran=%s" % [_n(tegang), _n(adil), saran]
		f.store_csv_line(r)
		f.close()
	# perbarui baris sesi ini di ringkasan (dibaca & ditulis ulang sebagai CSV, aman untuk koma di saran)
	var path := _summary_path()
	var src := FileAccess.open(path, FileAccess.READ)
	if src == null:
		return
	var rows: Array[PackedStringArray] = []
	while not src.eof_reached():
		var line := src.get_csv_line()
		if line.size() > 1:
			rows.append(line)
	src.close()
	var ti := SUMMARY_COLUMNS.find("survei_tegang")
	for i in rows.size():
		var row := rows[i]
		if row.size() == SUMMARY_COLUMNS.size() and row[0] == session_id:
			row[ti] = _n(tegang)
			row[ti + 1] = _n(adil)
			row[ti + 2] = saran
			rows[i] = row
	var out := FileAccess.open(path, FileAccess.WRITE)
	if out:
		for row in rows:
			out.store_csv_line(row)
		out.close()

func _n(v: int) -> String:
	return str(v) if v > 0 else ""

func _notification(what: int) -> void:
	# jendela game ditutup sebelum selesai -> log sesi ini dibuang (atau dicatat kalau fitur hapus dimatikan)
	if what == NOTIFICATION_WM_CLOSE_REQUEST and world != null and enabled and not _ended:
		if delete_unfinished:
			discard()  # ditutup sebelum selesai: log dibuang
		else:
			log_end("DITINGGALKAN", "game ditutup")
