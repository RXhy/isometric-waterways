extends Node2D

@onready var world: TileMapLayer = $World
@onready var camera: Camera2D = $Camera2D
@onready var buildings = $Buildings
@onready var roads = $Roads
@onready var facilities = $Facilities
@onready var weather = $Weather
@onready var water = $Water
@onready var fx_kemarau: CanvasItem = $WeatherFX/Kemarau
@onready var fx_hujan: CanvasItem = $WeatherFX/Hujan
@onready var score = $Score
@onready var overlay_layer = $InfoLayer
@onready var cursor: Sprite2D = $Cursor
@onready var hud = $HUD
@onready var water_edge: TileMapLayer = $World/WaterEdge
@onready var balance_log = $BalanceLog
@onready var drag_preview: TileMapLayer = $DragPreview

## Warna sorotan petak di bawah kursor
@export var cursor_ok: Color = Color(0.45, 1.0, 0.5, 0.9)
@export var cursor_bad: Color = Color(1.0, 0.4, 0.35, 0.9)
@export var cursor_info: Color = Color(1, 1, 1, 0.7)

var hover_cell: Vector2i
var hover_valid: bool = false

enum TileState {
	DIRT = 0,
	CANAL = 1,
	GRASS = 2,
	WATER = 3,
	ROAD = 4
}

const MAP_SIZE: int = 250
const AREA_SIZE: int = 25
const MAX_ORIGIN_TRIES: int = 50

var grid_data: Dictionary = {}

var active_area: Rect2i  ## semua petak yang terlihat di layar: air disimulasikan & bisa dipakai alat di sini
var spawn_area: Rect2i   ## area inti 25x25 (pusat kamera); bangunan baru hanya muncul di sini
var elevation: Dictionary = {}  # Vector2i -> 0..3
var dug: Dictionary = {}        # set petak hasil galian (kanal); air di dalamnya diatur WaterSim
var land_variant: Dictionary = {}  # petak daratan -> koordinat atlas varian yang dipakai
var land_class: Dictionary = {}    # petak daratan -> LandClass (kering / dekat air / pelataran)
var land_dist: Dictionary = {}     # petak dekat air -> jarak ke air (1..radius)

# --- Tileset: dua sumber atlas ---
# Sumber 0 = assets/Tiles/terrain_tiles_v3.png (5 kolom x 4 baris), semuanya daratan:
#   baris 0   = daratan kering yang jauh dari air
#   baris 1-2 = tanah dekat air (rumput terang/gelap, semak, pohon)
#   baris 3   = pelataran di sekitar bangunan yang dekat air
#   Kelas daratan dihitung ulang tiap detik oleh WaterSim dari jarak ke air.
# Sumber 1 = assets/Tiles/tileset_iso_waterways.png: parit kanal, air, dan jalan.
const SRC_TERRAIN := 0
const SRC_WATER_ROAD := 1
const SRC_WATER_FLOW := 2  ## assets/water/water_flow_source.tres: air beranimasi (tenang, arus 4 arah pelan/deras, dangkal)
const SRC_V2 := 3          ## assets/Tiles/tilesset_water_road.png (dibuat saat runtime, lihat _build_v2_source)
const SRC_FLOW := 4        ## assets/Tiles/waterflow.png (dibuat saat runtime, lihat _build_flow_source)
const ATLAS_CANAL_DRY := Vector2i(1, 0)   ## (sumber 1) parit kanal / dasar sungai kering
const ATLAS_WATER := Vector2i(3, 0)       ## (sumber 1) air: sumber alami, kanal berair, banjir
const ATLAS_ROAD := Vector2i(4, 0)        ## (sumber 1) jalan
enum LandClass { DRY, NEAR, COURTYARD }
const DRY_WEIGHTS := [45, 20, 20, 10, 5]      ## baris 0: polos, retak, kasar, bintik, pohon mati
const NEAR_WEIGHTS := [40, 20, 20, 12, 8]     ## baris 1-2: polos, bertekstur, semak/bunga, pohon
const COURTYARD_COLS := [0, 1, 4]             ## baris 3 yang dipakai (kolam batu kolom 2-3 tidak, agar tak dikira air)
const COURTYARD_WEIGHTS := [40, 30, 30]

# --- Aturan permainan (bisa diubah di Inspector node Node2D) ---
@export var day_length: float = 30.0  ## detik per hari (bangunan baru muncul tiap awal hari)
@export var target_days: int = 45     ## lama permainan (hari). Di akhir hari terakhir poin dinilai jadi bintang (lihat node Score)
@export var damage_quota: int = 8     ## kalah kalau bangunan hancur MELEBIHI angka ini (~20% dari ~40 bangunan selama 45 hari)
@export var supply_diagonals: bool = false  ## false = air harus tepat di DEPAN/SAMPING bangunan (4 sisi). true = sudut/serong juga dihitung (8 arah)
@export var dig_per_day: int = 15      ## jatah Gali per hari; sisa tidak terbawa ke besok
@export var level_per_day: int = 15    ## jatah Ratakan per hari
@export var fill_per_day: int = 10     ## jatah Timbun kanal per hari
var shovel_per_day: int:  # total (untuk log)
	get: return dig_per_day + level_per_day + fill_per_day
@export var demo_mode: bool = false  ## latar menu utama: HUD disembunyikan, input mati, tidak bisa kalah
## Seed peta & kejadian acak. 0 = acak tiap main (seed yang terpakai dicatat di log playtest).
## Isi dengan seed dari log untuk mengulang peta/kondisi yang sama saat membandingkan balancing.
@export var map_seed: int = 0

@export_group("Kamera")
## Zoom dengan scroll mouse (ke arah kursor). Nilai relatif terhadap zoom awal (1 = pas area inti).
## Batas zoom out juga menentukan luas area main: semua yang terlihat saat zoom out penuh
## ikut disimulasikan, jadi jangan terlalu kecil (berat untuk simulasi air).
@export_range(0.4, 1.0, 0.05) var zoom_out_limit: float = 0.75
@export_range(1.0, 4.0, 0.1) var zoom_in_limit: float = 2.5
@export var zoom_step: float = 1.15        ## pengali zoom tiap satu putaran scroll
@export var zoom_smooth: float = 12.0      ## kehalusan animasi zoom (makin besar makin cepat)
@export var pan_speed: float = 360.0       ## kecepatan geser kamera WASD / panah (px layar per detik)

@export_group("Tileset air & jalan")
## Pakai tileset baru assets/Tiles/tilesset_water_road.png (11 kolom x 32 px):
##   baris 0-8  : air alami (danau/sungai) 9 bentuk tepi; 3 kelompok warna bibir (kering / rumput / rumput gelap),
##                tiap kelompok 3 baris = kering, dangkal, penuh
##   baris 10-15: kanal galian 11 bentuk sambungan (lurus, belokan, T, perempatan); 10-12 bata, 13-15 batu,
##                tiap gaya 3 baris = kering, dangkal, penuh
##   baris 17   : jalan 11 bentuk sambungan (urutan sama dengan kanal)
## Matikan untuk kembali ke tile lama (air beranimasi + buih tepi).
@export var use_tileset_v2: bool = true
@export var water_road_texture: Texture2D
## Gaya kanal galian: 0 = bata coklat (baris 10-12), 1 = batu abu-abu (baris 13-15).
@export_range(0, 1) var canal_style: int = 0
## Kedalaman air minimal agar tile tampil "penuh" (di bawahnya "dangkal"; di bawah wet_threshold "kering").
@export var v2_full_depth: float = 0.3
## Geser vertikal tile air/jalan terhadap tile daratan (px). 0 = sejajar (tanah v3 & tileset air/jalan
## sama-sama bertepi atas di baris 6, sisi blok 10 px).
@export var v2_top_shift: int = 0
## 0 = kanal rata dengan tanah seperti air alami & jalan (parit, dinding depan tertutup tanah).
## Nilai > 0 menggambar kanal setelah baris di depannya (dinding depan ikut terlihat, kesan menonjol).
@export var v2_canal_sort_boost: int = 0
## Animasi gali: kanal muncul petak demi petak mengikuti urutan drag (seperti jalan).
@export var dig_step_delay: float = 0.05
@export var dig_drop_time: float = 0.2
@export var dig_drop_height: float = 8.0
## Animasi arus air (assets/Tiles/waterflow.png, 4 frame x 128 baris): kilau/arus digambar di atas
## tile air & kanal. Tenang kalau air diam, berarah kalau mengalir lurus, pusaran di belokan/simpangan.
@export var show_water_flow: bool = true
@export var waterflow_texture: Texture2D
@export var waterflow_fps: float = 4.0          ## kecepatan animasi arus (frame per detik); kecil = lebih pelan & tenang
@export var waterflow_random_start: bool = false ## true = tiap petak mulai di frame acak (tidak serempak)

@export_group("Lahan & ekspansi")
## Pusat area main di peta. (-1, -1) = acak tiap main: dipilih yang berisi air dan jauh dari tepi peta,
## jadi kamera selalu bisa menaruh area main tepat di tengah layar.
@export var area_center: Vector2i = Vector2i(-1, -1)
## Lahan yang bisa dipakai di awal = bagian tengah layar yang tidak tertutup UI.
## Lahan lalu melebar bertahap sampai seluruh bingkai zoom out (dikurangi tepi UI).
## Lahan aktif berbentuk belah ketupat (isometrik), mengikuti grid peta.
## Seberapa besar tepi UI (atas/bawah) yang dihindari ujung belah ketupat: 1 = tidak menyentuh UI sama
## sekali, 0.5 = ujung atas/bawah boleh sedikit masuk ke area UI (lebih luas).
@export_range(0.0, 1.0, 0.05) var diamond_ui_respect: float = 0.5
@export var expansion_steps: int = 4        ## berapa kali lahan melebar
@export var expand_every_days: int = 9      ## lahan melebar tiap sekian hari (default: hari 10, 19, 28, 37)
## Porsi layar yang tertutup UI (atas = bar poin, bawah = tab hari + toolbar). Lahan & bangunan tidak di sini.
@export_range(0.0, 0.4, 0.01) var ui_margin_top: float = 0.12
@export_range(0.0, 0.4, 0.01) var ui_margin_bottom: float = 0.13
@export_range(0.0, 0.4, 0.01) var ui_margin_side: float = 0.05
@export var locked_shade: Color = Color(0.12, 0.08, 0.05, 0.5)  ## warna gelap lahan yang belum terbuka
@export var border_color: Color = Color(1.0, 0.95, 0.8, 0.9)    ## garis batas lahan aktif

## Main menu yang dituju saat keluar dari game.
const MENU_SCENE := "res://scenes/main_menu.tscn"

var elapsed: float = 0.0
var game_over: bool = false
var last_day: int = 0
var shovel_left := {0: 0, 1: 0, 2: 0}  ## sisa jatah hari ini per alat (Tool.GALI/RATAKAN/TIMBUN)
## Sisa jatah untuk alat yang sedang dipilih.
var shovel: int:
	get: return shovel_left.get(current_tool, 0)
	set(v):
		if shovel_left.has(current_tool):
			shovel_left[current_tool] = v
var shovel_used: int = 0  ## aksi sekop yang sudah dipakai hari ini (untuk log)

const NEIGHBORS_8 := [
	TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE,
	TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE,
	TileSet.CELL_NEIGHBOR_TOP_CORNER, TileSet.CELL_NEIGHBOR_RIGHT_CORNER,
	TileSet.CELL_NEIGHBOR_BOTTOM_CORNER, TileSet.CELL_NEIGHBOR_LEFT_CORNER,
]

func _ready() -> void:
	var used_cells = world.get_used_cells()
	for cell in used_cells:
		var atlas_coord := world.get_cell_atlas_coords(cell)
		var source := world.get_cell_source_id(cell)
		var state := atlas_to_state(source, atlas_coord)
		grid_data[cell] = state
		if source == SRC_TERRAIN:
			land_variant[cell] = atlas_coord
			land_class[cell] = LandClass.DRY if atlas_coord.y == 0 else \
				(LandClass.COURTYARD if atlas_coord.y == 3 else LandClass.NEAR)
			land_dist[cell] = 1 if atlas_coord.y == 1 else 2
		if state == TileState.CANAL:
			dug[cell] = true  # saluran yang dicat manual di editor dianggap kanal galian
		elevation[cell] = world.get_cell_alternative_tile(cell)

	_build_v2_source()
	_build_flow_source()

	if map_seed == 0:
		randomize()
		map_seed = randi_range(1, 999999)
	seed(map_seed)

	choose_active_area()
	spawn_area = active_area
	setup_camera()
	_setup_zoom()

	Engine.time_scale = 1.0
	GameSettings.load_settings()
	if not demo_mode:
		Audio.stop_music()
		Audio.start_ambience()
	water.setup(self)
	facilities.setup(self)
	weather.setup(self)
	score.setup(self)
	overlay_layer.setup(self)
	hud.setup(self)
	balance_log.setup(self)
	set_tool(Tool.GALI)
	buildings.building_destroyed.connect(_on_building_destroyed)
	buildings.building_spawned.connect(func(b): roads.connect_building(b.cell))
	roads.setup(self)
	buildings.setup(self)
	_check_new_day()
	update_hud()
	if demo_mode:
		hud.hide()
		cursor.hide()
		# geser pandangan supaya peta tidak tertutup panel menu di kiri
		camera.offset.x = -108.0 / camera.zoom.x

# --- Loop permainan: hari, kuota kerusakan, menang/kalah ---

func current_day() -> int:
	return int(elapsed / day_length) + 1

func _process(delta: float) -> void:
	_update_camera()
	if base_zoom > 0.0:
		Audio.set_zoom(camera.zoom.x / base_zoom)
	_process_dig_queue(delta)
	_update_cursor()
	if game_over:
		return
	elapsed += delta
	if current_day() > target_days:
		score.end_of_day()
		balance_log.log_day_end(target_days)
		end_game(score.reached(), "waktu")
	else:
		_check_new_day()
		if score.end_on_target and score.reached():
			end_game(true)
	update_hud()

func _exit_tree() -> void:
	Audio.stop_ambience()

func _check_new_day() -> void:
	var d := current_day()
	if d != last_day:
		if last_day > 0:
			score.end_of_day()
			balance_log.log_day_end(last_day)
			Audio.play("day_new")
		score.start_of_day()
		shovel_left = {Tool.GALI: dig_per_day, Tool.RATAKAN: level_per_day, Tool.TIMBUN: fill_per_day}
		shovel_used = 0
		last_day = d
		roads.on_new_day(d)
		facilities.on_new_day(d)
		var k := unlock_step_for_day(d)
		if k != unlock_step:
			_expand_to(k)
		weather.start_day(d)
		buildings.start_day(d)

func _on_building_destroyed(_b) -> void:
	balance_log.log_destroyed(_b)
	Audio.play("bld_destroyed")
	if buildings.destroyed_count > damage_quota:
		end_game(false, "kuota")

func end_game(won: bool, reason: String = "") -> void:
	if game_over or demo_mode:
		return
	game_over = true
	buildings.stop()
	balance_log.log_end("MENANG" if won else "KALAH", reason if reason != "" else "target tercapai")
	Engine.time_scale = 1.0
	Audio.play_jingle(won)
	update_hud()
	if not hud.end_panel.play_again.is_connected(_restart):
		hud.end_panel.play_again.connect(_restart)
		hud.end_panel.main_menu.connect(_to_menu)
	hud.show_end(won, score.stars() if won else 0, buildings.destroyed_count)

func _restart() -> void:
	balance_log.log_end("DITINGGALKAN", "main ulang")
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()

func _to_menu() -> void:
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(MENU_SCENE)


func update_hud() -> void:
	hud.refresh()

const TILE_NAMES := ["Land", "Dry Canal", "Grass", "Water", "Road"]

## Sorotan petak di bawah kursor, berwarna sesuai bisa/tidaknya alat dipakai di sana.
func _update_cursor() -> void:
	if demo_mode:
		return
	var cell := pick_cell(get_global_mouse_position())
	hover_cell = cell
	hover_valid = grid_data.has(cell) and is_in_active_area(cell)
	var over_ui: bool = get_viewport().has_method("gui_get_hovered_control") \
		and get_viewport().gui_get_hovered_control() != null
	if dragging:
		_update_drag(cell)
	cursor.visible = hover_valid and not game_over and not over_ui and not dragging
	if cursor.visible:
		cursor.position = cell_to_global(cell)
		var ok: int = action_preview(cell)[0]
		cursor.modulate = cursor_ok if ok > 0 else (cursor_bad if ok < 0 else cursor_info)

## Info petak untuk tooltip: judul, detail, dan pratinjau aksi alat yang dipilih.
func tile_info(cell: Vector2i) -> Dictionary:
	var t: int = grid_data[cell]
	var tname: String = TILE_NAMES[t]
	var wet: bool = water.is_wet(cell)
	if t == TileState.CANAL:
		tname = "Canal" if wet else "Dry Canal"
	if t == TileState.WATER:
		tname = "Water Source" if wet else "Water Source (dry)"
	if roads.bridges.has(cell):
		tname = "Bridge (wet)" if wet else "Bridge (dry)"
	if water.is_flooded(cell):
		tname = "Flooded"
	if facilities.has_facility(cell):
		tname = facilities.KIND_NAMES[facilities.kind_at(cell)]
	var detail := ""
	if buildings.has_building(cell):
		var b = buildings.buildings[cell]
		tname = b.TYPE_DATA[b.type]["name"]
		detail = "Water %d%%  -  %s" % [int(100.0 * b.water / b.max_water), ["Healthy", "At Risk", "Destroyed"][b.state]]
	elif facilities.kind_at(cell) == facilities.Kind.KINCIR:
		var targets: Array = water.pump_targets.get(cell, [])
		if water.pumped.has(cell):
			detail = "Pumping water up to %d canal(s) (%.1f/s)" % [targets.size(), water.pumped[cell]]
		elif not targets.is_empty():
			detail = "Ready - the wheel needs water to pump"
		else:
			detail = "Not pumping - place next to a canal %d level higher" % 1
		var pw: float = facilities.kincir_power(cell)
		if pw >= 0.03:
			detail += "\n+%.1f pts/s from the current" % (pw * facilities.kincir_points_per_second)
	elif water.get_depth(cell) > 0.005:
		detail = "Water depth %.2f" % water.get_depth(cell)
	var pv: Array = action_preview(cell)
	if dragging:
		pv = _drag_summary()
	return {
		"title": "%s  |  %s (%d)" % [tname, ELEV_NAMES[get_elev(cell)], get_elev(cell)],
		"detail": detail,
		"ok": pv[0],
		"action": pv[1],
	}

## Pratinjau aksi alat terpilih di petak ini: [1 = bisa, -1 = tidak bisa, 0 = info], teks.
func action_preview(cell: Vector2i) -> Array:
	if not is_playable(cell):
		var nd := next_unlock_day()
		return [-1, "Area not unlocked yet" + (" (day %d)" % nd if nd > 0 else "")]
	var t: int = grid_data[cell]
	var land: bool = t == TileState.DIRT or t == TileState.GRASS
	var occupied: bool = buildings.has_building(cell) or facilities.has_facility(cell)
	var no_shovel: bool = shovel <= 0
	match current_tool:
		Tool.GALI:
			if occupied: return [-1, "Tile has a building or facility"]
			if roads.is_road(cell): return [-1, "Road - use a Bridge"]
			if dig_pending.has(cell): return [0, "Digging..."]
			if land: return [-1, "No uses left - refills tomorrow"] if no_shovel else [1, "Click: dig canal"]
			return [-1, "Already a canal or water"]
		Tool.RATAKAN:
			if occupied or roads.is_road(cell): return [-1, "Can't be leveled"]
			if is_natural_water(cell): return [-1, "Water sources can't be leveled"]
			if no_shovel: return [-1, "No uses left - refills tomorrow"]
			var h := get_elev(cell)
			return [1, "Left: lower to %d  |  Right: raise to %d" % [maxi(h - 1, 0), mini(h + 1, MAX_ELEV)]]
		Tool.TIMBUN:
			if facilities.has_facility(cell): return [1, "Click: remove %s (refunded)" % facilities.KIND_NAMES[facilities.kind_at(cell)]]
			if roads.bridges.has(cell): return [1, "Click: remove bridge"]
			if dug.has(cell): return [-1, "No uses left - refills tomorrow"] if no_shovel else [1, "Click: fill canal"]
			return [0, "Nothing to fill"]
		Tool.JEMBATAN:
			if roads.bridge_stock <= 0: return [-1, "Out of bridges"]
			if t != TileState.ROAD or roads.bridges.has(cell): return [-1, "Roads only"]

			# Validasi visual kursor untuk jembatan (cek mask jalan lurus)
			var tl = world.get_neighbor_cell(cell, TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE)
			var tr = world.get_neighbor_cell(cell, TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE)
			var bl = world.get_neighbor_cell(cell, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE)
			var br = world.get_neighbor_cell(cell, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE)

			var valid_conn = func(c: Vector2i):
				return roads.is_road(c) or buildings.has_building(c)

			var mask = 0
			if valid_conn.call(tl): mask |= 1
			if valid_conn.call(tr): mask |= 2
			if valid_conn.call(bl): mask |= 4
			if valid_conn.call(br): mask |= 8

			if mask != 9 and mask != 6:
				return [-1, "Straight roads only"]

			return [1, "Click: build bridge"]

		Tool.BOR, Tool.SPILLWAY, Tool.KINCIR:
			var why: String = facilities.why_not(tool_kind(current_tool), cell)
			if why == "":
				if current_tool == Tool.KINCIR:
					var n: int = water.lift_targets(cell).size()
					return [1, "Click: build Water Wheel - pumps up to %d canal(s)" % n] if n > 0 \
						else [1, "Click: build Water Wheel (no higher canal next to it yet)"]
				return [1, "Click: build %s" % facilities.KIND_NAMES[tool_kind(current_tool)]]
			return [-1, why]
	return [0, ""]

# --- Helper untuk BuildingManager ---

func cell_to_global(cell: Vector2i) -> Vector2:
	return world.to_global(world.map_to_local(cell) - Vector2(0, ELEV_STEP * get_elev(cell)))

## Bisa dibangun: di dalam area aktif dan tanahnya DIRT/GRASS.
func is_buildable(cell: Vector2i) -> bool:
	var t: int = grid_data.get(cell, -1)
	return is_in_active_area(cell) and (t == TileState.DIRT or t == TileState.GRASS) \
		and not facilities.has_facility(cell) and not roads.is_road(cell) and not dig_pending.has(cell)

## Sumber air alami atau sumur bor (dasar sungai/danau), berair ataupun sedang kering.
func is_natural_water(cell: Vector2i) -> bool:
	return grid_data.get(cell, -1) == TileState.WATER

const NEIGHBORS_SIDE := [
	TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE,
	TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE,
]

## Bangunan teraliri kalau salah satu dari 4 tetangga SISI-nya (bukan sudut/serong) kanal/sumber
## yang berair dan sama tinggi atau lebih tinggi (air tidak bisa naik).
func is_cell_supplied(cell: Vector2i) -> bool:
	for n in (NEIGHBORS_8 if supply_diagonals else NEIGHBORS_SIDE):
		var c := world.get_neighbor_cell(cell, n)
		if water.is_channel(c) and water.is_wet(c) and get_elev(c) >= get_elev(cell):
			return true
	return false

## Jarak dalam langkah tile lewat sisi (= jumlah tile kanal yang perlu digali).
func iso_distance(a: Vector2i, b: Vector2i) -> int:
	var d := world.map_to_local(a) - world.map_to_local(b)
	var half := Vector2(world.tile_set.tile_size) / 2.0
	var u := d.x / half.x + d.y / half.y
	var v := d.x / half.x - d.y / half.y
	return int(round((absf(u) + absf(v)) / 2.0))

## Jarak ke WATER terdekat (maksimal max_r). -1 kalau tidak ada.
func water_distance(cell: Vector2i, max_r: int) -> int:
	var best := -1
	for y in range(cell.y - max_r, cell.y + max_r + 1):
		for x in range(cell.x - (max_r + 1) / 2, cell.x + (max_r + 1) / 2 + 1):
			var c := Vector2i(x, y)
			if grid_data.get(c, -1) != TileState.WATER:
				continue
			var d := iso_distance(cell, c)
			if d <= max_r and (best == -1 or d < best):
				best = d
	return best

# --- Area bermain acak (AREA_SIZE x AREA_SIZE) ---

func choose_active_area() -> void:
	var c := area_center
	if demo_mode:
		c = Vector2i(AREA_SIZE / 2, AREA_SIZE / 2)
	elif c.x < 0 or c.y < 0:
		c = _random_area_center()
	active_area = Rect2i(c - Vector2i(AREA_SIZE / 2, AREA_SIZE / 2), Vector2i(AREA_SIZE, AREA_SIZE))

## Pusat acak yang punya air (tapi tidak didominasi air) dan cukup jauh dari tepi peta
## supaya bingkai zoom out penuh (~34 kolom x ~76 baris) tetap di dalam peta.
func _random_area_center() -> Vector2i:
	var mx := 22
	var my := 46
	var best := Vector2i(MAP_SIZE / 2, MAP_SIZE / 2)
	var best_n := 0
	for i in MAX_ORIGIN_TRIES:
		var c := Vector2i(randi_range(mx, MAP_SIZE - 1 - mx), randi_range(my, MAP_SIZE - 1 - my))
		var n := _water_count(Rect2i(c - Vector2i(10, 10), Vector2i(21, 21)))
		if n >= 12 and n <= 150:
			return c
		if n > best_n and n <= 220:
			best = c
			best_n = n
	return best

func _water_count(rect: Rect2i) -> int:
	var n := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if grid_data.get(Vector2i(x, y), -1) == TileState.WATER:
				n += 1
	return n

## Persegi petak (koordinat peta) yang terlihat oleh kamera, termasuk yang tertutup sebagian
## oleh tepi layar/UI. Layout stacked: kotak layar = kotak di koordinat peta.
func visible_area() -> Rect2i:
	var half_view := get_viewport_rect().size / camera.zoom / 2.0
	var lo := world.local_to_map(world.to_local(camera.global_position - half_view))
	var hi := world.local_to_map(world.to_local(camera.global_position + half_view))
	lo -= Vector2i(1, 1)
	hi += Vector2i(1, 1 + int(ceil(ELEV_STEP * MAX_ELEV / 8.0)))  # petak di bawah layar bisa terangkat masuk layar
	lo = lo.clamp(Vector2i.ZERO, Vector2i(MAP_SIZE - 1, MAP_SIZE - 1))
	hi = hi.clamp(Vector2i.ZERO, Vector2i(MAP_SIZE - 1, MAP_SIZE - 1))
	return Rect2i(lo, hi - lo + Vector2i.ONE).merge(spawn_area)

func is_in_active_area(cell: Vector2i) -> bool:
	return active_area.has_point(cell)

func setup_camera() -> void:
	var first := spawn_area.position
	var last := spawn_area.end - Vector2i.ONE
	# Empat sudut area. Baris ganjil pada layout stacked tergeser setengah tile,
	# jadi sudut di baris sebelahnya ikut dihitung supaya bounding box pas.
	var corners: Array[Vector2i] = [
		first, Vector2i(last.x, first.y), Vector2i(first.x, last.y), last,
		first + Vector2i(0, 1), Vector2i(last.x, first.y + 1),
		Vector2i(first.x, last.y - 1), last - Vector2i(0, 1),
	]

	var half_tile := 16.0 # map_to_local mengembalikan titik tengah tile
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for c in corners:
		var p := world.to_global(world.map_to_local(c))
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	min_p -= Vector2(half_tile, half_tile)
	max_p += Vector2(half_tile, half_tile)

	var box_size := max_p - min_p
	camera.position = (min_p + max_p) / 2.0

	# Zoom supaya seluruh area aktif muat di layar (tanpa pan).
	var screen := get_viewport_rect().size # 640x360
	var z: float = min(screen.x / box_size.x, screen.y / box_size.y)
	camera.zoom = Vector2(z, z)

	# Layar lebih tinggi dari area, jadi baris di atas/bawah area ikut terlihat.
	# Geser kamera seperlunya supaya tidak memperlihatkan bagian di luar peta.
	# Pakai titik tengah tile baris/kolom terluar agar tepi bergerigi tidak terlihat.
	var map_min := world.to_global(world.map_to_local(Vector2i(1, 0)))
	var map_max := world.to_global(world.map_to_local(Vector2i(MAP_SIZE - 1, MAP_SIZE - 1)))
	var half_view := screen / z / 2.0
	if map_max.y - map_min.y > half_view.y * 2.0:
		camera.position.y = clamp(camera.position.y, map_min.y + half_view.y, map_max.y - half_view.y)
	if map_max.x - map_min.x > half_view.x * 2.0:
		camera.position.x = clamp(camera.position.x, map_min.x + half_view.x, map_max.x - half_view.x)

	camera.make_current()

# --- Zoom & geser kamera ---
# Scroll = zoom ke arah kursor · tombol tengah mouse (seret) / WASD / panah = geser.
# Kamera tidak bisa keluar dari bingkai zoom out penuh (play_rect), jadi area yang
# disimulasikan tetap sama sepanjang permainan.

var base_zoom: float = 0.0     ## zoom awal (pas area inti 25x25)
var target_zoom: float = 0.0
var play_rect: Rect2           ## bingkai kamera saat zoom out penuh (koordinat global)
var unlocked_area: Rect2i      ## kotak pembungkus lahan aktif (untuk mencari tempat spawn)
var unlock_core: Rect2i        ## kotak pembungkus lahan awal
var unlock_max: Rect2i         ## kotak pembungkus lahan terluas
var iso_center: Vector2i       ## pusat lahan belah ketupat (koordinat isometrik, lihat iso_of)
var unlock_r0: int = 0         ## "jari-jari" lahan awal (petak dari pusat ke ujung, sepanjang sumbu isometrik)
var unlock_rmax: int = 0       ## jari-jari lahan terluas
var unlock_r: int = 0          ## jari-jari lahan sekarang
var unlock_step: int = 0
var _shade: Node2D             ## gambar gelap lahan terkunci + garis batas
var _pan_goal: Vector2         ## tujuan geser kamera otomatis (saat lahan melebar)
var _pan_goal_on: bool = false
var _zoom_anchor: Vector2      ## posisi kursor di layar saat scroll (titik yang dipertahankan)
var _panning: bool = false
var _cam_last_us: int = 0

func _setup_zoom() -> void:
	base_zoom = camera.zoom.x
	target_zoom = base_zoom
	var base_pos: Vector2 = camera.position
	var screen := get_viewport_rect().size
	var zmin: float = base_zoom * (1.0 if demo_mode else zoom_out_limit)
	var pos := _clamp_view(base_pos, zmin, _map_rect())
	var half := screen / zmin / 2.0
	play_rect = Rect2(pos - half, half * 2.0)
	# area aktif = semua yang bisa terlihat saat zoom out penuh
	camera.zoom = Vector2(zmin, zmin)
	camera.position = pos
	active_area = visible_area()
	camera.zoom = Vector2(base_zoom, base_zoom)
	camera.position = base_pos
	# lahan belah ketupat: awal = muat di tampilan awal, terluas = muat di bingkai zoom out
	var base_view := Rect2(base_pos - screen / base_zoom / 2.0, screen / base_zoom)
	var mid_shift: float = (ui_margin_bottom - ui_margin_top) * diamond_ui_respect * base_view.size.y / 2.0
	iso_center = iso_of(world.local_to_map(world.to_local(base_view.get_center() - Vector2(0, mid_shift))))
	unlock_r0 = _r_fit(base_view)
	unlock_rmax = maxi(unlock_r0, _r_fit(play_rect))
	if demo_mode:
		unlock_r0 = 999
		unlock_rmax = 999
	unlock_r = unlock_r0
	unlock_core = _diamond_bounds(unlock_r0)
	unlock_max = _diamond_bounds(unlock_rmax)
	unlocked_area = unlock_core
	spawn_area = unlock_core
	_cam_last_us = Time.get_ticks_usec()
	_shade = LockedShade.new()
	_shade.w = self
	_shade.z_index = 1
	add_child(_shade)
	move_child(_shade, world.get_index() + 1)
	_shade.set_rect(_diamond_px(unlock_r), false)

## Koordinat isometrik petak: (i, j) dengan i+ = kanan-bawah layar, j+ = kanan-atas layar.
## Petak yang |i - pusat.i| <= r dan |j - pusat.j| <= r membentuk belah ketupat di layar.
func iso_of(cell: Vector2i) -> Vector2i:
	var p := world.map_to_local(cell)
	return Vector2i(roundi((p.x / 16.0 + p.y / 8.0) / 2.0), roundi((p.x / 16.0 - p.y / 8.0) / 2.0))

func in_diamond(cell: Vector2i, r: int) -> bool:
	var d := iso_of(cell) - iso_center
	return absi(d.x) <= r and absi(d.y) <= r

## Jari-jari belah ketupat terbesar yang muat di tampilan ini (memperhitungkan tepi UI).
func _r_fit(view: Rect2) -> int:
	var h: float = view.size.y * (1.0 - (ui_margin_top + ui_margin_bottom) * diamond_ui_respect)
	var w: float = view.size.x * (1.0 - 2.0 * ui_margin_side)
	return maxi(2, mini(int((h / 16.0 - 1.0) / 2.0), int((w / 32.0 - 1.0) / 2.0)))

## Kotak (koordinat peta) yang membungkus lahan belah ketupat berjari-jari r.
func _diamond_bounds(r: int) -> Rect2i:
	var out := Rect2i()
	var first := true
	for y in range(active_area.position.y, active_area.end.y):
		for x in range(active_area.position.x, active_area.end.x):
			var c := Vector2i(x, y)
			if in_diamond(c, r):
				if first:
					out = Rect2i(c, Vector2i.ONE)
					first = false
				else:
					out = out.expand(c)
	if first:
		return active_area
	return Rect2i(out.position, out.size + Vector2i.ONE).intersection(active_area)

## Kotak piksel (global) yang membungkus belah ketupat berjari-jari r (gambarnya belah ketupat di dalamnya).
func _diamond_px(r: int) -> Rect2:
	# kebalikan iso_of: posisi lokal = (16 (i + j), 8 (i - j))
	var local := Vector2((iso_center.x + iso_center.y) * 16.0, (iso_center.x - iso_center.y) * 8.0)
	# naikkan sesuai elevasi petak tengah supaya garis batas pas dengan tile yang terangkat
	var c := world.to_global(local) - Vector2(0, ELEV_STEP * get_elev(world.local_to_map(local)))
	var half := Vector2(32.0 * r + 16.0, 16.0 * r + 8.0)
	return Rect2(c - half, half * 2.0)

## Bagian rect (koordinat global) yang tidak tertutup UI.
func _ui_inset(r: Rect2) -> Rect2:
	return Rect2(r.position + Vector2(r.size.x * ui_margin_side, r.size.y * ui_margin_top),
		r.size * Vector2(1.0 - 2.0 * ui_margin_side, 1.0 - ui_margin_top - ui_margin_bottom))

## Petak yang seluruhnya berada di dalam rect global.
func _cells_in(r: Rect2) -> Rect2i:
	var lo := world.local_to_map(world.to_local(r.position)) + Vector2i(1, 2)
	var hi := world.local_to_map(world.to_local(r.end)) - Vector2i(1, 2)
	return Rect2i(lo, (hi - lo + Vector2i.ONE).max(Vector2i.ONE))

## Kotak piksel (global) yang menutupi sekumpulan petak.
func _cells_px(a: Rect2i) -> Rect2:
	var half := Vector2(world.tile_set.tile_size) / 2.0
	var a0 := world.to_global(world.map_to_local(a.position))
	var a1 := world.to_global(world.map_to_local(a.position + Vector2i(0, 1)))
	var b0 := world.to_global(world.map_to_local(a.end - Vector2i.ONE))
	var b1 := world.to_global(world.map_to_local(a.end - Vector2i(1, 2)))
	var lo := a0.min(a1) - half
	var hi := b0.max(b1) + half
	return Rect2(lo, hi - lo)

## Lahan aktif (bisa dipakai alat, tempat bangunan muncul).
func is_playable(cell: Vector2i) -> bool:
	return active_area.has_point(cell) and in_diamond(cell, unlock_r)

## Jari-jari lahan untuk tahap ekspansi k (0 = awal).
func _radius_for_step(k: int) -> int:
	var t: float = clampf(float(k) / float(maxi(expansion_steps, 1)), 0.0, 1.0)
	return roundi(lerpf(unlock_r0, unlock_rmax, t))

func unlock_step_for_day(d: int) -> int:
	if expand_every_days <= 0:
		return 0
	return clampi((d - 1) / expand_every_days, 0, expansion_steps)

## Hari lahan berikutnya terbuka (-1 kalau sudah terluas).
func next_unlock_day() -> int:
	if unlock_step >= expansion_steps or expand_every_days <= 0:
		return -1
	return (unlock_step + 1) * expand_every_days + 1

func _expand_to(k: int) -> void:
	unlock_step = k
	unlock_r = _radius_for_step(k)
	unlocked_area = _diamond_bounds(unlock_r)
	_shade.set_rect(_diamond_px(unlock_r), true)
	balance_log.log_note("EKSPANSI", "lahan tahap %d: jari-jari %d" % [k, unlock_r])
	hud.toast("New land unlocked! (%d/%d)" % [k, expansion_steps])
	if k > 0:
		Audio.play("land_expand")
	_focus_on(_diamond_px(unlock_r))

## Geser & zoom out kamera pelan-pelan supaya seluruh lahan terlihat di luar UI.
func _focus_on(r: Rect2) -> void:
	var screen := get_viewport_rect().size
	var usable := screen * Vector2(1.0 - 2.0 * ui_margin_side, 1.0 - ui_margin_top - ui_margin_bottom)
	var fit: float = minf(usable.x / r.size.x, usable.y / r.size.y)
	if fit < camera.zoom.x:
		target_zoom = clampf(fit, base_zoom * zoom_out_limit, base_zoom * zoom_in_limit)
		_zoom_anchor = screen / 2.0
	# pusat layar di luar UI sedikit di atas pusat sebenarnya (UI bawah lebih tebal)
	var shift := Vector2(0, (ui_margin_bottom - ui_margin_top) * screen.y / 2.0) / target_zoom
	_pan_goal = r.get_center() + shift
	_pan_goal_on = true

## Batas peta dalam koordinat global (titik tengah tile terluar, supaya tepi bergerigi tak terlihat).
func _map_rect() -> Rect2:
	var a := world.to_global(world.map_to_local(Vector2i(1, 0)))
	var b := world.to_global(world.map_to_local(Vector2i(MAP_SIZE - 1, MAP_SIZE - 1)))
	return Rect2(a, b - a)

## Geser posisi kamera supaya pandangan (zoom z) tetap di dalam rect. Kalau pandangan lebih
## besar dari rect, kamera ditaruh di tengah rect.
func _clamp_view(pos: Vector2, z: float, rect: Rect2) -> Vector2:
	var half := get_viewport_rect().size / z / 2.0
	var out := pos
	if rect.size.x <= half.x * 2.0:
		out.x = rect.get_center().x
	else:
		out.x = clampf(pos.x, rect.position.x + half.x, rect.end.x - half.x)
	if rect.size.y <= half.y * 2.0:
		out.y = rect.get_center().y
	else:
		out.y = clampf(pos.y, rect.position.y + half.y, rect.end.y - half.y)
	return out

func zoom_by(factor: float, screen_anchor: Vector2) -> void:
	if base_zoom <= 0.0:
		return
	target_zoom = clampf(target_zoom * factor, base_zoom * zoom_out_limit, base_zoom * zoom_in_limit)
	_zoom_anchor = screen_anchor

## Input kamera dari _unhandled_input. true = event sudah dipakai.
func _camera_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					zoom_by(zoom_step, event.position)
				return true
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					zoom_by(1.0 / zoom_step, event.position)
				return true
			MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
				return true
	elif event is InputEventMouseMotion and _panning:
		_pan_goal_on = false
		camera.position = _clamp_view(camera.position - event.relative / camera.zoom.x, camera.zoom.x, play_rect)
		return true
	elif event is InputEventMagnifyGesture:  # trackpad pinch
		zoom_by(event.factor, event.position)
		return true
	elif event is InputEventPanGesture:      # trackpad dua jari
		camera.position = _clamp_view(camera.position + event.delta * 8.0 / camera.zoom.x, camera.zoom.x, play_rect)
		return true
	return false

## Dipanggil tiap frame. Memakai waktu nyata supaya zoom & geser tetap jalan saat dijeda.
func _update_camera() -> void:
	var now := Time.get_ticks_usec()
	var dt: float = minf(float(now - _cam_last_us) / 1000000.0, 0.1)
	_cam_last_us = now
	if demo_mode or base_zoom <= 0.0:
		return
	var z: float = camera.zoom.x
	var focus: Control = get_viewport().gui_get_focus_owner()
	var typing: bool = focus is LineEdit or focus is TextEdit
	if not game_over and not hud.pause_menu.visible and not typing:
		var dir := Vector2.ZERO
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): dir.x -= 1.0
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): dir.x += 1.0
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): dir.y -= 1.0
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): dir.y += 1.0
		if dir != Vector2.ZERO:
			_pan_goal_on = false
			camera.position += dir.normalized() * pan_speed * dt / z
	if _pan_goal_on:
		camera.position = camera.position.lerp(_pan_goal, 1.0 - exp(-4.0 * dt))
		if camera.position.distance_to(_pan_goal) < 0.5:
			_pan_goal_on = false
	if absf(z - target_zoom) > 0.00001:
		var nz: float = lerpf(z, target_zoom, 1.0 - exp(-zoom_smooth * dt))
		if absf(nz - target_zoom) < 0.0005:
			nz = target_zoom
		# pertahankan titik peta di bawah kursor saat zoom
		var off: Vector2 = _zoom_anchor - get_viewport_rect().size / 2.0
		var anchor_world: Vector2 = camera.position + off / z
		camera.zoom = Vector2(nz, nz)
		camera.position = anchor_world - off / nz
	camera.position = _clamp_view(camera.position, camera.zoom.x, play_rect)

# --- Elevasi ---
# Elevasi disimpan sebagai alternative tile di layer World (0..3), jadi bisa dicat
# manual di editor. Alternative tile di TileSet menaikkan tekstur ELEV_STEP px per tingkat.

const MAX_ELEV: int = 3
const ELEV_STEP: float = 4.0  ## harus sama dengan selisih texture_origin antar alternative tile (dinding tile = 4 px)
const ELEV_NAMES := ["Shoreline", "Lowland", "Midland", "Highland"]

func get_elev(cell: Vector2i) -> int:
	return elevation.get(cell, 0)

func set_elev(cell: Vector2i, h: int) -> void:
	elevation[cell] = clampi(h, 0, MAX_ELEV)
	water.refresh_cell(cell)

## Cari tile di bawah kursor dengan memperhitungkan tile yang terangkat.
## Tile paling depan (baris terbesar) yang cocok dengan tingginya yang dipilih.
func pick_cell(global_pos: Vector2) -> Vector2i:
	var local := world.to_local(global_pos)
	var found := false
	var best := world.local_to_map(local)
	for h in range(MAX_ELEV, -1, -1):
		var c := world.local_to_map(local + Vector2(0, ELEV_STEP * h))
		if grid_data.has(c) and get_elev(c) == h and (not found or c.y > best.y):
			best = c
			found = true
	return best

# --- Bulldoze: Gali / Ratakan / Timbun ---

enum Tool { GALI, RATAKAN, TIMBUN, JEMBATAN, BOR, SPILLWAY, KINCIR }

## Alat fasilitas -> FacilityManager.Kind (Bendungan sudah dihapus dari toolbar).
func tool_kind(t: int) -> int:
	match t:
		Tool.BOR: return facilities.Kind.BOR
		Tool.SPILLWAY: return facilities.Kind.SPILLWAY
		Tool.KINCIR: return facilities.Kind.KINCIR
	return -1
var current_tool: int = Tool.GALI

func set_tool(t: int) -> void:
	current_tool = t
	hud.select_tool(t)
	update_hud()

func _unhandled_input(event: InputEvent) -> void:
	if demo_mode:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if game_over:
			if _survey_typing():
				hud.get_node("Overlay/EndSurvey").feedback.release_focus()
				return
			_flush_survey()
			Engine.time_scale = 1.0
			get_tree().change_scene_to_file(MENU_SCENE)
		elif dragging:
			cancel_drag()
		elif hud.pause_menu.visible:
			hud.pause_menu.back()
		else:
			hud.pause_menu.open()
		return
	if hud.pause_menu.visible:
		return
	if _camera_input(event):
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SPACE and not game_over:
		hud.toggle_pause()
		return
	if game_over:
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_R and not _survey_typing():
			_flush_survey()
			balance_log.log_end("DITINGGALKAN", "main ulang")
			Engine.time_scale = 1.0
			get_tree().reload_current_scene()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1: set_tool(Tool.GALI)
			KEY_2: set_tool(Tool.RATAKAN)
			KEY_3: set_tool(Tool.TIMBUN)
			KEY_4: set_tool(Tool.JEMBATAN)
			KEY_5: set_tool(Tool.BOR)
			KEY_6: set_tool(Tool.SPILLWAY)
			KEY_7: set_tool(Tool.KINCIR)
			KEY_H: hud.toggle_ui()
		return

	if event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		var right: bool = event.button_index == MOUSE_BUTTON_RIGHT
		# Gali / Ratakan / Timbun: tekan, seret, lepas (jalur lurus mengikuti grid)
		if dragging:
			if not event.pressed and right == drag_right:
				_finish_drag()
			elif event.pressed and right != drag_right:
				cancel_drag()  # tombol mouse lain = batal
			return
		if not event.pressed:
			return
		var cell := pick_cell(get_global_mouse_position())
		if not grid_data.has(cell) or not is_playable(cell):
			return
		if not right and action_preview(cell)[0] < 0:
			Audio.play("ui_error")
		match current_tool:
			Tool.GALI, Tool.TIMBUN:
				if not right: _start_drag(cell, false)
			Tool.RATAKAN:
				_start_drag(cell, right)
			Tool.JEMBATAN:
				if not right and roads.build_bridge(cell):
					Audio.play("place_wood")
					balance_log.count("pasang_jembatan")
					update_hud()
			Tool.BOR, Tool.SPILLWAY, Tool.KINCIR:
				var kind: int = tool_kind(current_tool)
				if not right and facilities.place(kind, cell):
					Audio.play("place_wood" if kind == facilities.Kind.KINCIR else "place_stone")
					balance_log.count("pasang_fasilitas")
					update_hud()

## Ratakan: turunkan (klik kiri) / naikkan (klik kanan) satu tingkat.
## Berlaku untuk tanah dan kanal galian, tidak untuk sumber air alami atau bangunan.
func perform_leveling(cell_pos: Vector2i, delta_h: int) -> void:
	if buildings.has_building(cell_pos) or roads.is_road(cell_pos) or facilities.has_facility(cell_pos):
		return
	if is_natural_water(cell_pos):
		return
	var h := clampi(get_elev(cell_pos) + delta_h, 0, MAX_ELEV)
	if h == get_elev(cell_pos) or shovel <= 0:
		return
	shovel -= 1
	shovel_used += 1
	balance_log.count("ratakan_naik" if delta_h > 0 else "ratakan_turun")
	set_elev(cell_pos, h)
	Audio.play("tool_dirt", 1.1 if delta_h > 0 else 0.9, 0.08)

## Timbun: tutup kanal galian (kering atau berair) jadi tanah lagi.
func perform_filling(cell_pos: Vector2i) -> void:
	if facilities.has_facility(cell_pos):
		facilities.remove(cell_pos)
		balance_log.count("bongkar_fasilitas")
		Audio.play("place_stone", 1.3)
		update_hud()
		return
	if roads.bridges.has(cell_pos):
		roads.remove_bridge(cell_pos)
		balance_log.count("lepas_jembatan")
		Audio.play("place_wood", 1.3)
		water.clear_water(cell_pos)
		return
	if not dug.has(cell_pos) or shovel <= 0:
		return
	shovel -= 1
	shovel_used += 1
	balance_log.count("timbun")
	Audio.play("tool_dirt", 0.8, 0.08)
	dug.erase(cell_pos)
	set_base(cell_pos, TileState.DIRT)
	water.clear_water(cell_pos)

## Ganti jenis dasar petak (tanah, kanal, jalan, dasar sungai).
## Tile yang tampil ditentukan WaterSim dari jenis dasar + kedalaman air.
func set_base(cell_pos: Vector2i, new_state: int) -> void:
	grid_data[cell_pos] = new_state
	if new_state == TileState.DIRT or new_state == TileState.GRASS:
		land_class[cell_pos] = LandClass.DRY if new_state == TileState.DIRT else LandClass.NEAR
		land_variant.erase(cell_pos)
	water.refresh_cell(cell_pos)

## Jenis petak dari koordinat atlas (dipakai saat membaca peta dari editor).
func atlas_to_state(source: int, a: Vector2i) -> int:
	if source == SRC_WATER_ROAD:
		return a.x  # urutan tile lama sama dengan TileState: tanah, kanal, rumput, air, jalan
	return TileState.DIRT if a.y == 0 else TileState.GRASS  # terrain_tiles: semuanya daratan

## Dipanggil WaterSim saat kelas daratan sebuah petak berubah.
func set_land_class(cell_pos: Vector2i, cls: int, dist: int) -> void:
	land_class[cell_pos] = cls
	land_dist[cell_pos] = dist
	grid_data[cell_pos] = TileState.DIRT if cls == LandClass.DRY else TileState.GRASS
	land_variant.erase(cell_pos)
	water.refresh_cell(cell_pos)

func _pick(weights: Array) -> int:
	var total := 0
	for w in weights:
		total += w
	var r := randi() % total
	var i := 0
	while r >= weights[i]:
		r -= weights[i]
		i += 1
	return i

## Varian tile daratan untuk petak ini, sesuai kelasnya; dipilih acak sekali lalu diingat.
func _land_atlas(cell_pos: Vector2i, state: int) -> Vector2i:
	if land_variant.has(cell_pos):
		return land_variant[cell_pos]
	var cls: int = land_class.get(cell_pos, LandClass.DRY if state == TileState.DIRT else LandClass.NEAR)
	var v: Vector2i
	match cls:
		LandClass.DRY:
			v = Vector2i(_pick(DRY_WEIGHTS), 0)
		LandClass.COURTYARD:
			v = Vector2i(COURTYARD_COLS[_pick(COURTYARD_WEIGHTS)], 3)
		_:
			# makin dekat air makin hijau terang (baris 1), agak jauh lebih gelap (baris 2)
			var row := 1 if land_dist.get(cell_pos, 1) <= 1 else 2
			if randf() > 0.7:
				row = 3 - row
			v = Vector2i(_pick(NEAR_WEIGHTS), row)
	land_variant[cell_pos] = v
	return v

## Dipanggil WaterSim untuk menggambar tile. `tile` = jenis yang tampil (TileState),
## `water_row` = baris tile arus di water_flow.png (-1 = tile air statis lama).
func show_tile(cell_pos: Vector2i, tile: int, water_row: int = -1) -> void:
	var source := SRC_WATER_ROAD
	var atlas: Vector2i
	match tile:
		TileState.WATER:
			atlas = ATLAS_WATER
			if water_row >= 0:
				source = SRC_WATER_FLOW
				atlas = Vector2i(0, water_row)
		TileState.CANAL:
			atlas = ATLAS_CANAL_DRY
		TileState.ROAD:
			atlas = ATLAS_ROAD
		_:
			source = SRC_TERRAIN
			atlas = _land_atlas(cell_pos, tile)
	world.set_cell(cell_pos, source, atlas, get_elev(cell_pos))

# --- Drag Gali / Ratakan / Timbun (gaya Mini Motorways, jalur rapi mengikuti grid) ---
# Tekan di satu petak lalu seret: jalur dibuat lurus searah sumbu isometrik, lalu belok
# sekali (bentuk L) mengikuti arah seret pertama. Pratinjau hijau = dikerjakan,
# putih = dilewati (sudah sesuai), merah = tidak bisa / sekop tidak cukup.
# Aksi baru dijalankan saat tombol mouse dilepas. Esc atau klik tombol lain = batal.

@export var max_drag_length: int = 40  ## panjang jalur drag maksimal (petak)

var dragging: bool = false
var drag_right: bool = false
var drag_start: Vector2i
var drag_axis: int = -1  # sumbu yang ditempuh lebih dulu: 0 = kiri-atas/kanan-bawah, 1 = kanan-atas/kiri-bawah
var drag_path: Array[Vector2i] = []
var drag_status: Array[int] = []  # 1 dikerjakan, 0 dilewati, -1 tidak bisa

func _start_drag(cell: Vector2i, right: bool) -> void:
	dragging = true
	drag_right = right
	drag_start = cell
	drag_axis = -1
	_update_drag(cell)

func cancel_drag() -> void:
	dragging = false
	drag_path.clear()
	drag_status.clear()
	drag_preview.clear()

func _finish_drag() -> void:
	var path := drag_path.duplicate()
	var status := drag_status.duplicate()
	cancel_drag()
	if path.size() > 1:
		balance_log.count("drag")
	var order := 0
	for i in path.size():
		if status[i] <= 0:
			continue
		var c: Vector2i = path[i]
		match current_tool:
			Tool.GALI:
				queue_dig(c, order * dig_step_delay)
				order += 1
			Tool.RATAKAN: perform_leveling(c, 1 if drag_right else -1)
			Tool.TIMBUN: perform_filling(c)
	update_hud()

## Jalur rapi dari a ke b: lurus di satu sumbu isometrik, lalu belok sekali ke sumbu lainnya.
func _drag_path(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var d := world.map_to_local(b) - world.map_to_local(a)
	var half := Vector2(world.tile_set.tile_size) / 2.0
	var u := int(round((d.x / half.x + d.y / half.y) / 2.0))  # langkah ke kanan-bawah (+) / kiri-atas (-)
	var v := int(round((d.x / half.x - d.y / half.y) / 2.0))  # langkah ke kanan-atas (+) / kiri-bawah (-)
	if u == 0 and v == 0:
		drag_axis = -1
	elif drag_axis == -1:
		drag_axis = 0 if absi(u) >= absi(v) else 1
	var legs := [[0, u], [1, v]] if drag_axis != 1 else [[1, v], [0, u]]
	var path: Array[Vector2i] = [a]
	var cur := a
	for leg in legs:
		var n: int = leg[1]
		var side: int
		if leg[0] == 0:
			side = TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE if n > 0 else TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE
		else:
			side = TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE if n > 0 else TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE
		for i in absi(n):
			if path.size() >= max_drag_length:
				return path
			cur = world.get_neighbor_cell(cur, side)
			path.append(cur)
	return path

func _update_drag(cell: Vector2i) -> void:
	if not grid_data.has(cell):
		return
	drag_path = _drag_path(drag_start, cell)
	drag_status.clear()
	drag_preview.clear()
	var budget := shovel
	for c in drag_path:
		var st := _drag_cell_status(c, budget)
		if st == 1 and _drag_cost(c) > 0:
			budget -= 1
		drag_status.append(st)
		if grid_data.has(c):
			var alt := get_elev(c) + (0 if st == 1 else (8 if st == 0 else 4))
			drag_preview.set_cell(c, 0, Vector2i.ZERO, alt)

func _drag_cost(c: Vector2i) -> int:
	if current_tool == Tool.TIMBUN and (facilities.has_facility(c) or roads.bridges.has(c)):
		return 0  # bongkar fasilitas/jembatan gratis
	return 1

func _drag_cell_status(c: Vector2i, budget: int) -> int:
	if not grid_data.has(c) or not is_playable(c):
		return -1
	var t: int = grid_data[c]
	match current_tool:
		Tool.GALI:
			if water.is_channel(c) or dig_pending.has(c):
				return 0  # sudah kanal/air (atau sedang digali): dilewati saja
		Tool.TIMBUN:
			if not dug.has(c) and not facilities.has_facility(c) and not roads.bridges.has(c):
				return 0  # tidak ada yang perlu ditimbun
		Tool.RATAKAN:
			var h := get_elev(c) + (1 if drag_right else -1)
			if h < 0 or h > MAX_ELEV:
				return 0  # sudah paling rendah/tinggi
	if _drag_cost(c) > 0 and budget <= 0:
		return -1
	# cek aturan alat seperti klik biasa (tanpa memperhitungkan sekop yang sudah habis)
	var keep := shovel
	shovel = maxi(shovel, 1)
	var ok: int = action_preview(c)[0]
	shovel = keep
	if current_tool == Tool.RATAKAN and ok > 0:
		return 1
	return 1 if ok > 0 else -1

## Teks tooltip selama drag: jumlah petak dan sekop yang akan terpakai.
func _drag_summary() -> Array:
	var n := 0
	var cost := 0
	var bad := 0
	for i in drag_path.size():
		if drag_status[i] == 1:
			n += 1
			cost += _drag_cost(drag_path[i])
		elif drag_status[i] < 0:
			bad += 1
	var txt := "Release: %d tiles, %d uses (%d left)" % [n, cost, shovel - cost]
	if bad > 0:
		txt += "  |  %d red tiles skipped" % bad
	return [1 if n > 0 else -1, txt]

# --- Survei layar akhir ---

func _survey_typing() -> bool:
	var s = hud.get_node_or_null("Overlay/EndSurvey")
	return s != null and s.is_typing()

## Simpan isian survei yang belum dikirim sebelum meninggalkan layar akhir.
func _flush_survey() -> void:
	var s = hud.get_node_or_null("Overlay/EndSurvey")
	if s:
		s.flush()

# --- Gambar lahan terkunci ---

## Menggelapkan semua di luar lahan aktif + garis batas. Melebar dengan animasi saat ekspansi.
class LockedShade extends Node2D:
	var w
	var rect: Rect2
	var _tw: Tween

	func set_rect(r: Rect2, animate: bool) -> void:
		if _tw:
			_tw.kill()
		if not animate:
			rect = r
			queue_redraw()
			return
		_tw = create_tween()
		_tw.tween_method(func(v: Rect2):
			rect = v
			queue_redraw(), rect, r, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	func _draw() -> void:
		if w == null or w.demo_mode:
			return
		# lahan aktif = belah ketupat di dalam rect; di luarnya digelapkan (4 segilima + 4 pita)
		var big := 4000.0
		var r := Rect2(to_local(rect.position), rect.size)
		var col: Color = w.locked_shade
		var c := r.get_center()
		var t := Vector2(c.x, r.position.y)
		var rt := Vector2(r.end.x, c.y)
		var b := Vector2(c.x, r.end.y)
		var l := Vector2(r.position.x, c.y)
		# pita di luar kotak pembungkus
		draw_rect(Rect2(r.position.x - big, r.position.y - big, r.size.x + big * 2.0, big), col)
		draw_rect(Rect2(r.position.x - big, r.end.y, r.size.x + big * 2.0, big), col)
		draw_rect(Rect2(r.position.x - big, r.position.y, big, r.size.y), col)
		draw_rect(Rect2(r.end.x, r.position.y, big, r.size.y), col)
		# 4 sudut kotak pembungkus di luar belah ketupat
		draw_colored_polygon(PackedVector2Array([r.position, t, l]), col)
		draw_colored_polygon(PackedVector2Array([t, Vector2(r.end.x, r.position.y), rt]), col)
		draw_colored_polygon(PackedVector2Array([rt, r.end, b]), col)
		draw_colored_polygon(PackedVector2Array([b, Vector2(r.position.x, r.end.y), l]), col)
		draw_polyline(PackedVector2Array([t, rt, b, l, t]), w.border_color, 1.0)

# --- Tileset air & jalan v2 (assets/Tiles/tilesset_water_road.png) ---

enum Side { TL = 1, TR = 2, BL = 4, BR = 8 }
const SIDE_CELLS := [
	[TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE, Side.TL], [TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE, Side.TR],
	[TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE, Side.BL], [TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE, Side.BR],
]
## Kolom tile kanal/jalan dari sisi yang TERSAMBUNG (bitmask TL=1, TR=2, BL=4, BR=8).
## 0: TR+BR, 1: BL+BR, 2: lurus TL-BR, 3: lurus TR-BL, 4: TL+TR, 5: TL+BL,
## 6-9: pertigaan tanpa TL / BL / TR / BR, 10: perempatan.
const LINK_COL := {
	0: 2, 1: 2, 8: 2, 9: 2, 2: 3, 4: 3, 6: 3,
	10: 0, 12: 1, 3: 4, 5: 5,
	14: 6, 11: 7, 13: 8, 7: 9, 15: 10,
}
## Kolom tile air alami dari sisi yang berbatasan dengan DARATAN (bertembok).
## 8: tengah, 1/3/4/6: satu sisi (TL/TR/BL/BR), 2/5/0/7: sudut (TL+TR / BL+BR / TL+BL / TR+BR).
const LAKE_COL := {
	0: 8, 1: 1, 2: 3, 4: 4, 8: 6,
	3: 2, 12: 5, 5: 0, 10: 7,
	9: 1, 6: 3,                      # dua sisi berseberangan: tidak ada tile-nya, pakai tembok belakang
	7: 2, 11: 2, 13: 0, 14: 7, 15: 2,  # tiga/empat sisi: pakai sudut terdekat
}
const V2_CANAL_ROW := 10
const V2_ROAD_ROW := 17

var dig_pending: Dictionary = {}   ## petak yang sudah dipesan untuk digali (menunggu animasi)
var _dig_queue: Array = []
var _dig_clock: float = 0.0

## Buat atlas source tileset baru saat runtime (4 tingkat elevasi sebagai alternative tile,
## offset & warna mengikuti tile daratan). Artist cukup menimpa PNG-nya.
func _build_v2_source() -> void:
	if not use_tileset_v2:
		return
	var tex: Texture2D = water_road_texture
	if tex == null:
		push_warning("water_road_texture kosong: tileset v2 dimatikan.")
		use_tileset_v2 = false
		return
	var ts: TileSet = world.tile_set
	if ts.has_source(SRC_V2):
		return
	var land: TileSetAtlasSource = ts.get_source(SRC_TERRAIN) as TileSetAtlasSource
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(32, 32)
	var grid := Vector2i(tex.get_width() / 32, tex.get_height() / 32)
	var rows: Array[int] = []
	for r in 9:
		rows.append(r)
	for r in range(V2_CANAL_ROW, V2_CANAL_ROW + 6):
		rows.append(r)
	rows.append(V2_ROAD_ROW)
	for r in rows:
		var cols: int = 9 if r < 9 else 11
		for c in mini(cols, grid.x):
			var a := Vector2i(c, r)
			if r >= grid.y:
				continue
			src.create_tile(a)
			for h in MAX_ELEV + 1:
				if h > 0:
					src.create_alternative_tile(a, h)
				var td: TileData = src.get_tile_data(a, h)
				var ref: TileData = land.get_tile_data(Vector2i(0, 0), h) if land and land.has_alternative_tile(Vector2i(0, 0), h) else null
				td.texture_origin = (ref.texture_origin if ref else Vector2i(0, 4 * h + 4)) + Vector2i(0, v2_top_shift)
				td.modulate = ref.modulate if ref else Color.WHITE
				if r >= V2_CANAL_ROW and r < V2_CANAL_ROW + 6:
					td.y_sort_origin = v2_canal_sort_boost
	ts.add_source(src, SRC_V2)

# --- Animasi arus air (assets/Tiles/waterflow.png) ---
## Sheet 4 kolom (frame animasi) x 128 baris. Indeks baris di bawah dihitung dari 0 (= baris panduan - 1).
##   0-8    air alami 3/4, 9 bentuk (urutan kolom LAKE_COL)   |  9-17   air alami penuh
##   18-28  kanal 3/4, 11 bentuk (urutan kolom LINK_COL)      |  29-39  kanal penuh
##   41-60  air alami arus lurus 3/4: 5 bentuk (kolom 1,3,4,6,8) x 4 arah  |  61-80 penuh
##   81-84  kanal lurus 3/4: arah kiri-atas, kanan-bawah (kolom 2), kanan-atas, kiri-bawah (kolom 3) | 85-88 penuh
##   89-96  pusaran sudut air alami (kolom 0,2,5,7), selang-seling 3/4 lalu penuh
##   97-104 pusaran belokan kanal (kolom 0,1,4,5) | 105-112 pertigaan (kolom 6-9) | 113-114 perempatan
const FLOW_NAT_CALM := [0, 9]
const FLOW_CANAL_CALM := [18, 29]
const FLOW_NAT_DIR := [41, 61]
const FLOW_CANAL_DIR := [81, 85]
const FLOW_NAT_TURB := 89
const FLOW_CANAL_TURB := 97
const FLOW_NAT_SHAPES := [1, 3, 4, 6, 8]     ## bentuk air alami yang punya arus lurus
const FLOW_NAT_CORNERS := [0, 2, 5, 7]       ## sudut air alami -> pusaran
const FLOW_CANAL_BENDS := [0, 1, 4, 5]       ## belokan kanal -> pusaran
## arah water_sim.flow_dir (0 kiri-atas, 1 kanan-atas, 2 kiri-bawah, 3 kanan-bawah) -> urutan di sheet
## (kiri-atas, kanan-bawah, kanan-atas, kiri-bawah)
const FLOW_DIR_ORDER := [0, 2, 3, 1]

var water_flow: TileMapLayer  ## layer animasi arus, anak World (ikut y-sort seperti tile air)

func _build_flow_source() -> void:
	if not use_tileset_v2 or not show_water_flow:
		return
	if waterflow_texture == null:
		waterflow_texture = load("res://assets/Tiles/waterflow.png")
	if waterflow_texture == null:
		return
	var ts: TileSet = world.tile_set
	if not ts.has_source(SRC_FLOW):
		var land: TileSetAtlasSource = ts.get_source(SRC_TERRAIN) as TileSetAtlasSource
		var src := TileSetAtlasSource.new()
		src.texture = waterflow_texture
		src.texture_region_size = Vector2i(32, 32)
		var frames: int = mini(4, waterflow_texture.get_width() / 32)
		for r in waterflow_texture.get_height() / 32:
			var a := Vector2i(0, r)
			src.create_tile(a)
			src.set_tile_animation_columns(a, frames)
			src.set_tile_animation_frames_count(a, frames)
			src.set_tile_animation_speed(a, waterflow_fps)
			if waterflow_random_start:
				src.set_tile_animation_mode(a, TileSetAtlasSource.TILE_ANIMATION_MODE_RANDOM_START_TIMES)
			var canal_row: bool = (r >= 18 and r <= 39) or (r >= 81 and r <= 88) or r >= 97
			for h in MAX_ELEV + 1:
				if h > 0:
					src.create_alternative_tile(a, h)
				var td: TileData = src.get_tile_data(a, h)
				# offset & warna sama persis dengan tile tanah/air di elevasi yang sama (alternative 0-3)
				var ref: TileData = land.get_tile_data(Vector2i(0, 0), h) if land and land.has_alternative_tile(Vector2i(0, 0), h) else null
				td.texture_origin = (ref.texture_origin if ref else Vector2i(0, 4 * h - 2)) + Vector2i(0, v2_top_shift)
				td.modulate = ref.modulate if ref else Color.WHITE
				if canal_row:
					td.y_sort_origin = v2_canal_sort_boost
		ts.add_source(src, SRC_FLOW)
	water_flow = TileMapLayer.new()
	water_flow.name = "WaterFlow"
	water_flow.y_sort_enabled = true
	water_flow.tile_set = ts
	world.add_child(water_flow)

## Baris waterflow.png untuk petak berair dengan tile v2 `a`, atau -1 (tanpa animasi arus).
func flow_row(c: Vector2i, a: Vector2i) -> int:
	if water_flow == null or a.x < 0 or a.y == V2_ROAD_ROW:
		return -1
	var canal: bool = a.y >= V2_CANAL_ROW
	var lvl: int = (a.y - V2_CANAL_ROW) % 3 if canal else a.y % 3
	if lvl <= 0:
		return -1  # kering
	var full: int = 1 if lvl == 2 else 0
	var col: int = a.x
	var d: int = water.flow_dir(c) if is_in_active_area(c) else -1
	if not canal:
		if d < 0:
			return FLOW_NAT_CALM[full] + col
		var si: int = FLOW_NAT_SHAPES.find(col)
		if si >= 0:
			return FLOW_NAT_DIR[full] + si * 4 + FLOW_DIR_ORDER[d]
		return FLOW_NAT_TURB + FLOW_NAT_CORNERS.find(col) * 2 + full
	if d < 0:
		return FLOW_CANAL_CALM[full] + col
	var v: Vector2 = water.flow_vec.get(c, Vector2.ZERO)
	match col:
		2:  # lurus kiri-atas <-> kanan-bawah
			return FLOW_CANAL_DIR[full] + (0 if v.x < 0.0 else 1)
		3:  # lurus kanan-atas <-> kiri-bawah
			return FLOW_CANAL_DIR[full] + (2 if v.y > 0.0 else 3)
		10:
			return FLOW_CANAL_TURB + 16 + full
	var bi: int = FLOW_CANAL_BENDS.find(col)
	if bi >= 0:
		return FLOW_CANAL_TURB + bi * 2 + full
	return FLOW_CANAL_TURB + 8 + (col - 6) * 2 + full

## Pasang / hapus animasi arus di petak ini.
func set_flow_cell(c: Vector2i, row: int) -> void:
	if water_flow == null:
		return
	if row < 0:
		water_flow.erase_cell(c)
	else:
		water_flow.set_cell(c, SRC_FLOW, Vector2i(0, row), get_elev(c))

## Pasang tile v2 di peta.
func set_v2_cell(c: Vector2i, a: Vector2i) -> void:
	world.set_cell(c, SRC_V2, a, get_elev(c))

func _water_level(c: Vector2i) -> int:
	if grid_data.get(c, -1) == TileState.WATER and not is_in_active_area(c):
		return 2  # di luar area simulasi: air alami selalu penuh
	var d: float = water.get_depth(c)
	if d < water.wet_threshold:
		return 0
	return 1 if d < v2_full_depth else 2

## Bitmask sisi yang memenuhi syarat.
func _side_mask(c: Vector2i, pred: Callable) -> int:
	var m := 0
	for s in SIDE_CELLS:
		if pred.call(world.get_neighbor_cell(c, s[0])):
			m |= s[1]
	return m

func _is_channel_like(n: Vector2i) -> bool:
	return water.is_channel(n) or dig_pending.has(n)

func _is_road_like(n: Vector2i) -> bool:
	return roads.is_road(n)

## Petak kanal yang "masuk" ke bangunan ini: kanal galian di sisi bangunan, utamakan ujung kanal
## (paling sedikit sambungan), lalu urutan sisi tetap. (-1,-1) kalau tidak ada.
func canal_link(b: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_n := 99
	for s in SIDE_CELLS:
		var n := world.get_neighbor_cell(b, s[0])
		if grid_data.get(n, -1) != TileState.CANAL and not dig_pending.has(n):
			continue
		var links := 0
		var m := _side_mask(n, _is_channel_like)
		for bit in [1, 2, 4, 8]:
			if m & bit:
				links += 1
		if links < best_n:
			best_n = links
			best = n
	return best

## Kelompok warna bibir air alami dari daratan di sekitarnya: 0 kering, 1 rumput, 2 rumput gelap.
func _lake_group(c: Vector2i) -> int:
	for s in SIDE_CELLS:
		var n := world.get_neighbor_cell(c, s[0])
		if not grid_data.has(n) or _is_channel_like(n):
			continue
		var cls: int = land_class.get(n, LandClass.DRY)
		if cls == LandClass.DRY:
			return 0
		return 1 if (cls == LandClass.COURTYARD or land_dist.get(n, 1) <= 1) else 2
	return 0

## Koordinat atlas tileset v2 untuk petak ini, atau (-1, -1) kalau petak ini memakai tile daratan.
func v2_atlas(c: Vector2i) -> Vector2i:
	var t: int = grid_data.get(c, -1)
	match t:
		TileState.ROAD:
			var m := _side_mask(c, _is_road_like)
			if m == 0 or m == 1 or m == 2 or m == 4 or m == 8:
				# ujung jalan: sambungkan ke bangunan di sebelahnya
				m |= _side_mask(c, func(n): return buildings.has_building(n))
			return Vector2i(LINK_COL.get(m, 2), V2_ROAD_ROW)
		TileState.CANAL:
			var cm := _side_mask(c, _is_channel_like)
			# kanal menyambung masuk ke bangunan di sebelahnya (satu sambungan per bangunan)
			cm |= _side_mask(c, func(n): return buildings.has_building(n) and canal_link(n) == c)
			return Vector2i(LINK_COL.get(cm, 2), V2_CANAL_ROW + canal_style * 3 + _water_level(c))
		TileState.WATER:
			var land_m := _side_mask(c, func(n): return grid_data.has(n) and not _is_channel_like(n))
			return Vector2i(LAKE_COL.get(land_m, 8), _lake_group(c) * 3 + _water_level(c))
		_:
			if is_in_active_area(c) and water.is_flooded(c):
				return Vector2i(8, _lake_group(c) * 3 + 1)  # daratan tergenang banjir
	return Vector2i(-1, -1)

# --- Animasi petak "jatuh" (jalan baru & kanal galian) ---

## Sprite tile dari atlas yang jatuh dari atas sambil memudar masuk, lalu on_done dipanggil
## (biasanya memasang tile aslinya). parent = node tempat sprite digambar.
func drop_fx(cell: Vector2i, source_id: int, atlas: Vector2i, parent: Node2D, on_done: Callable,
		drop_time: float = 0.22, drop_height: float = 10.0) -> void:
	var src: TileSetAtlasSource = world.tile_set.get_source(source_id) as TileSetAtlasSource if world.tile_set.has_source(source_id) else null
	if src == null or drop_time <= 0.0 or not src.has_tile(atlas):
		on_done.call()
		return
	var td: TileData = src.get_tile_data(atlas, get_elev(cell)) if src.has_alternative_tile(atlas, get_elev(cell)) else src.get_tile_data(atlas, 0)
	var spr := Sprite2D.new()
	spr.texture = src.texture
	spr.region_enabled = true
	spr.region_rect = Rect2(src.get_tile_texture_region(atlas))
	spr.modulate = td.modulate
	# sprite jadi anak layer World (ikut y-sort) supaya tertutup tanah di depannya persis seperti tile aslinya
	var _unused = parent
	spr.position = world.map_to_local(cell) + Vector2(0, 0.5)
	var final_off: Vector2 = -Vector2(td.texture_origin) - Vector2(0, 0.5)
	spr.offset = final_off - Vector2(0, drop_height)
	spr.self_modulate = Color(1, 1, 1, 0)
	spr.scale = Vector2(0.7, 0.7)
	world.add_child(spr)
	var tw := spr.create_tween().set_parallel(true)
	tw.tween_property(spr, "offset", final_off, drop_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(spr, "scale", Vector2.ONE, drop_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(spr, "self_modulate:a", 1.0, drop_time * 0.6)
	tw.chain().tween_callback(func():
		on_done.call()
		spr.queue_free())

## Pesan galian: sekop langsung dipotong, petaknya dikerjakan setelah delay (animasi berurutan).
func queue_dig(c: Vector2i, delay: float) -> void:
	var st: int = grid_data.get(c, -1)
	if dig_pending.has(c) or shovel <= 0 or not (st == TileState.DIRT or st == TileState.GRASS) \
			or buildings.has_building(c) or facilities.has_facility(c) or roads.is_road(c):
		return
	shovel -= 1
	shovel_used += 1
	balance_log.count("gali")
	dig_pending[c] = true
	_dig_queue.append({"cell": c, "at": _dig_clock + delay})
	_dig_queue.sort_custom(func(a, b): return a["at"] < b["at"])
	# tetangga kanal ikut diperbarui supaya sambungannya langsung terlihat menyambung
	water.refresh_cell(c)

func _process_dig_queue(delta: float) -> void:
	_dig_clock += delta
	while not _dig_queue.is_empty() and _dig_queue[0]["at"] <= _dig_clock:
		var c: Vector2i = _dig_queue.pop_front()["cell"]
		if use_tileset_v2:
			var keep: int = grid_data.get(c, -1)
			grid_data[c] = TileState.CANAL
			var a := v2_atlas(c)
			grid_data[c] = keep
			a.y = V2_CANAL_ROW + canal_style * 3  # animasi: kanal kering
			drop_fx(c, SRC_V2, a, roads, _finish_dig.bind(c), dig_drop_time, dig_drop_height)
		else:
			_finish_dig(c)

func _finish_dig(c: Vector2i) -> void:
	dig_pending.erase(c)
	var st: int = grid_data.get(c, -1)
	if (st == TileState.DIRT or st == TileState.GRASS) and not buildings.has_building(c) \
			and not facilities.has_facility(c) and not roads.is_road(c):
		Audio.play("tool_dirt", 1.0, 0.08)
		dug[c] = true
		set_base(c, TileState.CANAL)
	else:
		shovel_left[Tool.GALI] += 1  # batal (petak keburu terisi): sekop dikembalikan
		water.refresh_cell(c)
