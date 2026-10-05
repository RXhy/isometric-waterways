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
# Sumber 0 = assets/Tiles/terrain_tiles.png (5 kolom x 4 baris), semuanya daratan:
#   baris 0   = daratan kering yang jauh dari air
#   baris 1-2 = tanah dekat air (rumput terang/gelap, semak, pohon)
#   baris 3   = pelataran di sekitar bangunan yang dekat air
#   Kelas daratan dihitung ulang tiap detik oleh WaterSim dari jarak ke air.
# Sumber 1 = assets/Tiles/tileset_iso_waterways.png: parit kanal, air, dan jalan.
const SRC_TERRAIN := 0
const SRC_WATER_ROAD := 1
const SRC_WATER_FLOW := 2  ## assets/water/water_flow_source.tres: air beranimasi (tenang, arus 4 arah pelan/deras, dangkal)
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
@export var target_days: int = 8      ## bertahan sampai hari ini = menang (sementara, sebelum ada sistem poin)
@export var damage_quota: int = 5     ## kalah kalau bangunan hancur MELEBIHI angka ini
@export var shovel_per_day: int = 15  ## aksi sekop (Gali / Ratakan / Timbun kanal) per hari; sisa tidak terbawa ke besok
@export var demo_mode: bool = false  ## latar menu utama: HUD disembunyikan, input mati, tidak bisa kalah
## Seed peta & kejadian acak. 0 = acak tiap main (seed yang terpakai dicatat di log playtest).
## Isi dengan seed dari log untuk mengulang peta/kondisi yang sama saat membandingkan balancing.
@export var map_seed: int = 0
## Tombol debug F1-F4 (hanya aktif di build debug/editor, otomatis mati di export release).
@export var debug_tools: bool = true

const MENU_SCENE := "res://scenes/main_menu.tscn"

var elapsed: float = 0.0
var game_over: bool = false
var last_day: int = 0
var shovel: int = 0  ## sisa aksi sekop hari ini
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

	if map_seed == 0:
		randomize()
		map_seed = randi_range(1, 999999)
	seed(map_seed)

	choose_active_area()
	spawn_area = active_area
	setup_camera()
	active_area = visible_area()

	Engine.time_scale = 1.0
	GameSettings.load_settings()
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
		if score.reached():
			end_game(true)
	update_hud()

func _check_new_day() -> void:
	var d := current_day()
	if d != last_day:
		if last_day > 0:
			score.end_of_day()
			balance_log.log_day_end(last_day)
		score.start_of_day()
		shovel = shovel_per_day
		shovel_used = 0
		last_day = d
		roads.on_new_day(d)
		weather.start_day(d)
		buildings.start_day(d)

func _on_building_destroyed(_b) -> void:
	balance_log.log_destroyed(_b)
	if buildings.destroyed_count > damage_quota:
		end_game(false, "kuota")

func end_game(won: bool, reason: String = "") -> void:
	if game_over or demo_mode:
		return
	game_over = true
	buildings.stop()
	balance_log.log_end("MENANG" if won else "KALAH", reason if reason != "" else "target tercapai")
	Engine.time_scale = 1.0
	update_hud()
	var pts := "Poin %d / %d" % [int(score.total), score.target_points]
	var text: String
	if won:
		text = "TARGET TERCAPAI!\n%s pada hari ke-%d.\n\nR: main lagi   |   Esc: menu utama" % [pts, mini(current_day(), target_days)]
	elif reason == "waktu":
		text = "WAKTU HABIS\n%s. Target belum tercapai.\n\nR: coba lagi   |   Esc: menu utama" % pts
	else:
		text = "KOTA RUNTUH\n%d bangunan hancur (batas %d).\n\nR: coba lagi   |   Esc: menu utama" % [buildings.destroyed_count, damage_quota]
	hud.show_end(text)

func update_hud() -> void:
	hud.refresh()

const TILE_NAMES := ["Tanah", "Kanal kering", "Rumput", "Air", "Jalan"]

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
		tname = "Kanal berair" if wet else "Kanal kering"
	if t == TileState.WATER:
		tname = "Sumber air" if wet else "Sumber air (kering)"
	if roads.bridges.has(cell):
		tname = "Jembatan (berair)" if wet else "Jembatan (kering)"
	if water.is_flooded(cell):
		tname = "Banjir"
	if facilities.has_facility(cell):
		tname = facilities.KIND_NAMES[facilities.kind_at(cell)]
	var detail := ""
	if buildings.has_building(cell):
		var b = buildings.buildings[cell]
		tname = b.TYPE_DATA[b.type]["name"]
		detail = "Air %d%%  -  %s" % [int(100.0 * b.water / b.max_water), ["Hidup", "Terancam", "Hancur"][b.state]]
	elif facilities.kind_at(cell) == facilities.Kind.KINCIR:
		var pw: float = facilities.kincir_power(cell)
		detail = "Putaran %d%%  -  +%.1f poin/detik" % [int(pw * 100.0), pw * facilities.kincir_points_per_second] \
			if pw >= 0.03 else "Diam - butuh air yang mengalir"
	elif water.get_depth(cell) > 0.005:
		detail = "Kedalaman air %.2f" % water.get_depth(cell)
	var pv: Array = action_preview(cell)
	if dragging:
		pv = _drag_summary()
	return {
		"title": "%s  |  %s (%d)" % [tname, ELEV_NAMES[get_elev(cell)], get_elev(cell)],
		"detail": detail,
		"ok": pv[0],
		"action": "[%s] %s" % [TOOL_NAMES[current_tool], pv[1]],
	}

## Pratinjau aksi alat terpilih di petak ini: [1 = bisa, -1 = tidak bisa, 0 = info], teks.
func action_preview(cell: Vector2i) -> Array:
	var t: int = grid_data[cell]
	var land: bool = t == TileState.DIRT or t == TileState.GRASS
	var occupied: bool = buildings.has_building(cell) or facilities.has_facility(cell)
	var no_shovel: bool = shovel <= 0
	match current_tool:
		Tool.GALI:
			if occupied: return [-1, "Petak terisi bangunan/fasilitas"]
			if roads.is_road(cell): return [-1, "Jalan - pakai Jembatan"]
			if land: return [-1, "Sekop habis - tambah lagi besok"] if no_shovel else [1, "Klik: gali kanal"]
			return [-1, "Sudah kanal/air"]
		Tool.RATAKAN:
			if occupied or roads.is_road(cell): return [-1, "Tidak bisa diratakan"]
			if is_natural_water(cell): return [-1, "Sumber air tidak bisa diratakan"]
			if no_shovel: return [-1, "Sekop habis - tambah lagi besok"]
			var h := get_elev(cell)
			return [1, "Kiri: turun ke %d  |  Kanan: naik ke %d" % [maxi(h - 1, 0), mini(h + 1, MAX_ELEV)]]
		Tool.TIMBUN:
			if facilities.has_facility(cell): return [1, "Klik: bongkar %s (stok kembali)" % facilities.KIND_NAMES[facilities.kind_at(cell)]]
			if roads.bridges.has(cell): return [1, "Klik: lepas jembatan"]
			if dug.has(cell): return [-1, "Sekop habis - tambah lagi besok"] if no_shovel else [1, "Klik: tutup kanal"]
			return [0, "Tidak ada yang bisa ditimbun"]
		Tool.JEMBATAN:
			if roads.bridge_stock <= 0: return [-1, "Stok jembatan habis"]
			if t == TileState.ROAD and not roads.bridges.has(cell): return [1, "Klik: pasang jembatan"]
			return [-1, "Hanya di jalan"]
		Tool.BOR, Tool.BENDUNGAN, Tool.SPILLWAY, Tool.KINCIR:
			var why: String = facilities.why_not(current_tool - Tool.BOR, cell)
			if why == "":
				return [1, "Klik: pasang %s" % facilities.KIND_NAMES[current_tool - Tool.BOR]]
			return [-1, why]
	return [0, ""]

# --- Helper untuk BuildingManager ---

func cell_to_global(cell: Vector2i) -> Vector2:
	return world.to_global(world.map_to_local(cell) - Vector2(0, ELEV_STEP * get_elev(cell)))

## Bisa dibangun: di dalam area aktif dan tanahnya DIRT/GRASS.
func is_buildable(cell: Vector2i) -> bool:
	var t: int = grid_data.get(cell, -1)
	return is_in_active_area(cell) and (t == TileState.DIRT or t == TileState.GRASS) \
		and not facilities.has_facility(cell)

## Sumber air alami atau sumur bor (dasar sungai/danau), berair ataupun sedang kering.
func is_natural_water(cell: Vector2i) -> bool:
	return grid_data.get(cell, -1) == TileState.WATER

## Bangunan teraliri kalau salah satu dari 8 tetangganya kanal/sumber yang berair
## dan sama tinggi atau lebih tinggi (air tidak bisa naik).
func is_cell_supplied(cell: Vector2i) -> bool:
	for n in NEIGHBORS_8:
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
	var max_origin := MAP_SIZE - AREA_SIZE
	for i in MAX_ORIGIN_TRIES:
		var origin := Vector2i(randi_range(0, max_origin), randi_range(0, max_origin))
		var rect := Rect2i(origin, Vector2i(AREA_SIZE, AREA_SIZE))
		if area_has_water(rect):
			active_area = rect
			return

	# Cadangan kalau percobaan acak gagal: ambil area pertama yang ada airnya.
	for y in range(max_origin + 1):
		for x in range(max_origin + 1):
			var rect := Rect2i(Vector2i(x, y), Vector2i(AREA_SIZE, AREA_SIZE))
			if area_has_water(rect):
				active_area = rect
				return

	push_warning("Tidak ada area %dx%d yang berisi WATER." % [AREA_SIZE, AREA_SIZE])
	active_area = Rect2i(Vector2i.ZERO, Vector2i(AREA_SIZE, AREA_SIZE))

func area_has_water(rect: Rect2i) -> bool:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if grid_data.get(Vector2i(x, y), -1) == TileState.WATER:
				return true
	return false

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

# --- Elevasi ---
# Elevasi disimpan sebagai alternative tile di layer World (0..3), jadi bisa dicat
# manual di editor. Alternative tile di TileSet menaikkan tekstur ELEV_STEP px per tingkat.

const MAX_ELEV: int = 3
const ELEV_STEP: float = 4.0  ## harus sama dengan selisih texture_origin antar alternative tile (dinding tile = 4 px)
const ELEV_NAMES := ["Garis pantai", "Dataran rendah", "Dataran menengah", "Dataran tinggi"]

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

enum Tool { GALI, RATAKAN, TIMBUN, JEMBATAN, BOR, BENDUNGAN, SPILLWAY, KINCIR }
const TOOL_NAMES := ["Gali", "Ratakan", "Timbun", "Jembatan", "Mesin Bor", "Bendungan", "Spillway", "Kincir Air"]
var current_tool: int = Tool.GALI

func set_tool(t: int) -> void:
	current_tool = t
	hud.select_tool(t)
	update_hud()

func _unhandled_input(event: InputEvent) -> void:
	if demo_mode:
		return
	if event is InputEventKey and event.pressed and not event.echo and _debug_key(event.physical_keycode):
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if game_over:
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
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SPACE and not game_over:
		hud.toggle_pause()
		return
	if game_over:
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_R:
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
			KEY_6: set_tool(Tool.BENDUNGAN)
			KEY_7: set_tool(Tool.SPILLWAY)
			KEY_8: set_tool(Tool.KINCIR)
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
		if not grid_data.has(cell) or not is_in_active_area(cell):
			return
		match current_tool:
			Tool.GALI, Tool.TIMBUN:
				if not right: _start_drag(cell, false)
			Tool.RATAKAN:
				_start_drag(cell, right)
			Tool.JEMBATAN:
				if not right and roads.build_bridge(cell):
					update_hud()
			Tool.BOR, Tool.BENDUNGAN, Tool.SPILLWAY, Tool.KINCIR:
				var kind: int = current_tool - Tool.BOR  # urutan sama dengan FacilityManager.Kind
				if not right and facilities.place(kind, cell):
					update_hud()

## Gali: tanah (DIRT/GRASS) -> kanal.
func perform_digging(cell_pos: Vector2i) -> void:
	if buildings.has_building(cell_pos) or facilities.has_facility(cell_pos):
		return
	var current_state = grid_data[cell_pos]
	if (current_state == TileState.DIRT or current_state == TileState.GRASS) and shovel > 0:
		shovel -= 1
		shovel_used += 1
		dug[cell_pos] = true
		set_base(cell_pos, TileState.CANAL)

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
	set_elev(cell_pos, h)

## Timbun: tutup kanal galian (kering atau berair) jadi tanah lagi.
func perform_filling(cell_pos: Vector2i) -> void:
	if facilities.has_facility(cell_pos):
		facilities.remove(cell_pos)
		update_hud()
		return
	if roads.bridges.has(cell_pos):
		roads.remove_bridge(cell_pos)
		water.clear_water(cell_pos)
		return
	if not dug.has(cell_pos) or shovel <= 0:
		return
	shovel -= 1
	shovel_used += 1
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

# --- Tombol debug untuk balancing (F1-F4) ---

func debug_enabled() -> bool:
	return debug_tools and OS.is_debug_build() and not demo_mode

## F1: lompat ke hari berikutnya · F2: ganti cuaca hari ini · F3: tambah sekop & stok · F4: buka folder log.
func _debug_key(key: int) -> bool:
	if key == KEY_F4:
		balance_log.open_folder()
		return true
	if not debug_enabled() or game_over:
		return false
	match key:
		KEY_F1:
			balance_log.log_note("DEBUG", "F1 lompat ke hari %d" % (current_day() + 1))
			elapsed = current_day() * day_length
		KEY_F2:
			var w: int = (weather.current + 1) % 3
			weather.force_weather(w)
			balance_log.log_note("DEBUG", "F2 cuaca dipaksa %s" % weather.NAMES[w])
		KEY_F3:
			shovel += 10
			for i in facilities.stock.size():
				facilities.stock[i] += 1
			roads.bridge_stock += 1
			balance_log.log_note("DEBUG", "F3 +10 sekop, +1 semua stok")
		_:
			return false
	update_hud()
	return true

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
	for i in path.size():
		if status[i] <= 0:
			continue
		var c: Vector2i = path[i]
		match current_tool:
			Tool.GALI: perform_digging(c)
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
	if not grid_data.has(c) or not is_in_active_area(c):
		return -1
	var t: int = grid_data[c]
	match current_tool:
		Tool.GALI:
			if water.is_channel(c):
				return 0  # sudah kanal/air: dilewati saja
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
	var txt := "Lepas: %d petak, %d sekop (sisa %d)" % [n, cost, shovel - cost]
	if bad > 0:
		txt += "  |  %d petak merah dilewati" % bad
	return [1 if n > 0 else -1, txt]
