extends Node
## Log balancing otomatis (node BalanceLog di world.tscn).
## Setiap kali game dimainkan, dibuat SATU file CSV baru yang namanya berisi tanggal & jam mulai,
## misalnya  playtest_logs/sesi_2026-10-05_13-20-41_Zhan.csv
## Isi file: satu baris per akhir hari, satu baris tiap bangunan hancur, dan satu baris akhir permainan.
## Selain itu ada playtest_logs/ringkasan_<penguji>.csv: satu baris per sesi (cocok untuk dibandingkan di spreadsheet).
## Semua nama file unik per penguji/sesi, jadi folder ini aman di-commit ke git tanpa konflik.
##
## Lokasi folder:
##   - dijalankan dari editor Godot  -> folder project (isometric-waterways/playtest_logs/)
##   - dari hasil export (.exe)       -> di sebelah file .exe (playtest_logs/)
## Tekan F4 saat bermain untuk membuka foldernya.

@export var enabled: bool = true
## Nama penguji (opsional). Kosong = pakai nama user komputer.
@export var tester_name: String = ""

const COLUMNS := [
	"jenis", "hari", "detik_game", "jam_nyata", "cuaca", "tingkat_kemarau",
	"poin_total", "poin_hari_ini", "poin_bangunan", "poin_kincir", "poin_bonus", "poin_jembatan",
	"bangunan_total", "hidup", "terancam", "hancur",
	"sekop_terpakai_hari_ini", "sekop_sisa", "kanal_digali", "persen_kanal_berair",
	"stok_bor", "stok_bendungan", "stok_spillway", "stok_kincir",
	"pasang_bor", "pasang_bendungan", "pasang_spillway", "pasang_kincir", "jembatan",
	"keterangan",
]

var world
var session_id: String = ""
var tester: String = ""
var file_path: String = ""
var folder: String = ""
var _file: FileAccess
var _ended := false

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
	_file.store_line("# WATERWAYS playtest | sesi %s | penguji %s | seed %d | hari %d x %d detik | target %d poin" \
		% [session_id, tester, world.map_seed, world.target_days, int(world.day_length), world.score.target_points])
	_file.store_csv_line(PackedStringArray(COLUMNS))
	_file.flush()
	print("BalanceLog: ", file_path)

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

# --- Pencatatan ---

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
	return [
		kind, day, "%.1f" % W.elapsed, "%02d:%02d:%02d" % [t.hour, t.minute, t.second],
		W.weather.NAMES[W.weather.current], W.weather.drought_index(day),
		int(S.total), int(S.today),
		int(S.by_source.get("Bangunan teraliri", 0.0)), int(S.by_source.get("Kincir air", 0.0)),
		int(S.by_source.get("Bonus akhir hari", 0.0)), int(S.by_source.get("Jembatan", 0.0)),
		W.buildings.buildings.size(), alive, threat, W.buildings.destroyed_count,
		W.shovel_used, W.shovel, chan, (int(100.0 * wet / chan) if chan > 0 else 0),
		F.stock[0], F.stock[1], F.stock[2], F.stock[3],
		placed[0], placed[1], placed[2], placed[3], W.roads.bridges.size(),
		note,
	]

func _write(row: Array) -> void:
	if not enabled or _file == null:
		return
	var out := PackedStringArray()
	for v in row:
		out.append(str(v))
	_file.store_csv_line(out)
	_file.flush()  # langsung tersimpan walau game ditutup paksa

## Dipanggil world.gd tepat sebelum hari berganti (setelah bonus akhir hari).
func log_day_end(day: int) -> void:
	_write(_row("AKHIR_HARI", day))

## Dipanggil saat bangunan hancur.
func log_destroyed(b) -> void:
	var cause := "kekeringan" if b.water <= 0.0 else "banjir"
	_write(_row("HANCUR", world.current_day(), "%s %s di %s" % [b.TYPE_DATA[b.type]["name"], cause, str(b.cell)]))

## Dipanggil saat permainan selesai (menang/kalah) atau ditinggalkan (Esc / R / tutup game).
func log_end(result: String, reason: String) -> void:
	if not enabled or _ended:
		return
	_ended = true
	var day: int = mini(world.current_day(), world.target_days)
	_write(_row("AKHIR", day, "%s %s" % [result, reason]))
	_file.close()
	_append_summary(result, reason, day)

func _append_summary(result: String, reason: String, day: int) -> void:
	var path := folder.path_join("ringkasan_%s.csv" % _safe(tester))  # satu file per penguji: aman di-commit tanpa konflik
	var is_new := not FileAccess.file_exists(path)
	var f := FileAccess.open(path, FileAccess.READ_WRITE if not is_new else FileAccess.WRITE)
	if f == null:
		return
	if is_new:
		f.store_csv_line(PackedStringArray(["sesi", "penguji", "seed", "hasil", "sebab", "hari", "detik_game",
			"poin", "target", "hancur", "kincir_terpasang", "file_log"]))
	f.seek_end()
	var kincir := 0
	for c in world.facilities.facilities:
		if world.facilities.facilities[c]["kind"] == world.facilities.Kind.KINCIR:
			kincir += 1
	f.store_csv_line(PackedStringArray([session_id, tester, str(world.map_seed), result, reason, str(day),
		"%.1f" % world.elapsed, str(int(world.score.total)), str(world.score.target_points),
		str(world.buildings.destroyed_count), str(kincir), file_path.get_file()]))
	f.close()

## Catatan bebas (misalnya pemakaian tombol debug), supaya data sesi itu bisa ditandai.
func log_note(kind: String, note: String) -> void:
	_write(_row(kind, world.current_day(), note))

func _notification(what: int) -> void:
	# jendela game ditutup sebelum selesai -> tetap dicatat
	if what == NOTIFICATION_WM_CLOSE_REQUEST and world != null and enabled and not _ended:
		log_end("DITINGGALKAN", "game ditutup")
