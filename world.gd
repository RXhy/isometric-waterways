extends Node2D

@onready var world: TileMapLayer = $World
@onready var camera: Camera2D = $Camera2D
@onready var buildings = $Buildings
@onready var roads = $Roads
@onready var facilities = $Facilities
@onready var weather = $Weather
@onready var fx_kemarau: CanvasItem = $WeatherFX/Kemarau
@onready var fx_hujan: CanvasItem = $WeatherFX/Hujan
@onready var weather_label: Label = $HUD/Cuaca
@onready var stats_label: Label = $HUD/Stats
@onready var overlay: ColorRect = $HUD/Overlay
@onready var message_label: Label = $HUD/Overlay/Message
@onready var info_label: Label = $HUD/Info
@onready var btn_gali: Button = $HUD/Tools/Gali
@onready var btn_ratakan: Button = $HUD/Tools/Ratakan
@onready var btn_timbun: Button = $HUD/Tools/Timbun
@onready var btn_jembatan: Button = $HUD/Tools/Jembatan
@onready var btn_bor: Button = $HUD/Tools/Bor
@onready var btn_bendungan: Button = $HUD/Tools/Bendungan
@onready var btn_spillway: Button = $HUD/Tools/Spillway

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
var main_source_id: int = 0

var is_flowing: bool = false
var flow_queue: Dictionary = {} # dipakai sebagai set: flow_queue[cell] = true

var active_area: Rect2i
var elevation: Dictionary = {}  # Vector2i -> 0..3
var dug: Dictionary = {}        # set petak hasil galian (kanal kering atau berair)

# --- Aturan permainan (bisa diubah di Inspector node Node2D) ---
@export var day_length: float = 30.0  ## detik per hari (bangunan baru muncul tiap awal hari)
@export var target_days: int = 8      ## bertahan sampai hari ini = menang (sementara, sebelum ada sistem poin)
@export var damage_quota: int = 5     ## kalah kalau bangunan hancur MELEBIHI angka ini

var elapsed: float = 0.0
var game_over: bool = false
var last_day: int = 0

const NEIGHBORS_8 := [
	TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE,
	TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE,
	TileSet.CELL_NEIGHBOR_TOP_CORNER, TileSet.CELL_NEIGHBOR_RIGHT_CORNER,
	TileSet.CELL_NEIGHBOR_BOTTOM_CORNER, TileSet.CELL_NEIGHBOR_LEFT_CORNER,
]

func _ready() -> void:
	var used_cells = world.get_used_cells()
	for cell in used_cells:
		var atlas_coord = world.get_cell_atlas_coords(cell)
		grid_data[cell] = atlas_coord.x
		elevation[cell] = world.get_cell_alternative_tile(cell)
		main_source_id = world.get_cell_source_id(cell)

	choose_active_area()
	setup_camera()

	overlay.hide()
	btn_gali.pressed.connect(set_tool.bind(Tool.GALI))
	btn_ratakan.pressed.connect(set_tool.bind(Tool.RATAKAN))
	btn_timbun.pressed.connect(set_tool.bind(Tool.TIMBUN))
	btn_jembatan.pressed.connect(set_tool.bind(Tool.JEMBATAN))
	btn_bor.pressed.connect(set_tool.bind(Tool.BOR))
	btn_bendungan.pressed.connect(set_tool.bind(Tool.BENDUNGAN))
	btn_spillway.pressed.connect(set_tool.bind(Tool.SPILLWAY))
	facilities.setup(self)
	weather.setup(self)
	set_tool(Tool.GALI)
	buildings.building_destroyed.connect(_on_building_destroyed)
	buildings.building_spawned.connect(func(b): roads.connect_building(b.cell))
	roads.setup(self)
	buildings.setup(self)
	_check_new_day()
	update_hud()

# --- Loop permainan: hari, kuota kerusakan, menang/kalah ---

func current_day() -> int:
	return int(elapsed / day_length) + 1

func _process(delta: float) -> void:
	if game_over:
		return
	elapsed += delta
	if current_day() > target_days:
		end_game(true)
	else:
		_check_new_day()
	update_hud()

func _check_new_day() -> void:
	var d := current_day()
	if d != last_day:
		last_day = d
		roads.on_new_day(d)
		weather.start_day(d)
		buildings.start_day(d)

func _on_building_destroyed(_b) -> void:
	if buildings.destroyed_count > damage_quota:
		end_game(false)

func end_game(won: bool) -> void:
	if game_over:
		return
	game_over = true
	buildings.stop()
	update_hud()
	if won:
		message_label.text = "KOTA BERTAHAN!\nKamu berhasil melewati %d hari.\n\nTekan R untuk main lagi" % target_days
	else:
		message_label.text = "KOTA RUNTUH\n%d bangunan hancur (batas %d).\n\nTekan R untuk coba lagi" % [buildings.destroyed_count, damage_quota]
	overlay.show()

func update_hud() -> void:
	var total: int = buildings.buildings.size()
	var hancur: int = buildings.destroyed_count
	var terancam: int = buildings.count_state(buildings.Building.State.TERANCAM)
	var day := mini(current_day(), target_days)
	var sisa := int(ceil(day_length - fmod(elapsed, day_length)))
	stats_label.text = "Hari %d / %d  (%ds)    Bangunan: %d  (terancam %d)    Hancur: %d / %d    Jembatan: %d" % [
		day, target_days, sisa, total - hancur, terancam, hancur, damage_quota, roads.bridge_stock]
	var besok: String = weather.NAMES[weather.weather_for(current_day() + 1)] if current_day() < target_days else "-"
	weather_label.text = "Cuaca: %s\nBesok: %s" % [weather.NAMES[weather.current], besok]
	btn_bor.text = "5 Bor (%d)" % facilities.stock[facilities.Kind.BOR]
	btn_bendungan.text = "6 Bendungan (%d)" % facilities.stock[facilities.Kind.BENDUNGAN]
	btn_spillway.text = "7 Spillway (%d)" % facilities.stock[facilities.Kind.SPILLWAY]
	update_info()

const TILE_NAMES := ["Tanah", "Kanal kering", "Rumput", "Air", "Jalan"]

func update_info() -> void:
	var hint := ""
	match current_tool:
		Tool.GALI: hint = "Klik kiri: gali kanal"
		Tool.RATAKAN: hint = "Klik kiri: turunkan  |  Klik kanan: naikkan"
		Tool.TIMBUN: hint = "Klik kiri: tutup kanal / bongkar jembatan & fasilitas"
		Tool.BOR: hint = "Klik kiri di tanah: sumber air tanah (tahan kemarau)"
		Tool.BENDUNGAN: hint = "Klik kiri di tanah: lindungi radius %d dari banjir" % weather.dam_radius
		Tool.SPILLWAY: hint = "Klik kiri di tepi sumber air: sumber itu tidak meluap"
		Tool.JEMBATAN: hint = "Klik kiri pada jalan: pasang jembatan (sisa %d)" % roads.bridge_stock
	var cell := pick_cell(get_global_mouse_position())
	var tile := ""
	if grid_data.has(cell) and is_in_active_area(cell):
		var t: int = grid_data[cell]
		var tname: String = TILE_NAMES[t]
		if t == TileState.WATER:
			tname = "Kanal berair" if dug.has(cell) else "Sumber air"
		if roads.bridges.has(cell):
			tname = "Jembatan (berair)" if t == TileState.WATER else "Jembatan (kering)"
		if weather.is_flooded(cell):
			tname = "Banjir"
		if weather.is_dried(cell):
			tname = "Sumber air (kering)"
		if facilities.has_facility(cell):
			tname = facilities.KIND_NAMES[facilities.kind_at(cell)]
		if buildings.has_building(cell):
			tname = "Bangunan"
		tile = "%s, %s (%d)" % [tname, ELEV_NAMES[get_elev(cell)], get_elev(cell)]
	info_label.text = "[%s] %s\n%s" % [TOOL_NAMES[current_tool], hint, tile]

# --- Helper untuk BuildingManager ---

func cell_to_global(cell: Vector2i) -> Vector2:
	return world.to_global(world.map_to_local(cell) - Vector2(0, ELEV_STEP * get_elev(cell)))

## Bisa dibangun: di dalam area aktif dan tanahnya DIRT/GRASS.
func is_buildable(cell: Vector2i) -> bool:
	var t: int = grid_data.get(cell, -1)
	return is_in_active_area(cell) and (t == TileState.DIRT or t == TileState.GRASS) \
		and not facilities.has_facility(cell)

## Air alami: sumber air, sumur bor, atau genangan banjir (bukan kanal galian).
func is_natural_water(cell: Vector2i) -> bool:
	return grid_data.get(cell, -1) == TileState.WATER and not dug.has(cell)

## Bangunan teraliri kalau salah satu dari 8 tetangganya WATER yang
## sama tinggi atau lebih tinggi (air tidak bisa naik).
func is_cell_supplied(cell: Vector2i) -> bool:
	for n in NEIGHBORS_8:
		var c := world.get_neighbor_cell(cell, n)
		if grid_data.get(c, -1) == TileState.WATER and get_elev(c) >= get_elev(cell):
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

func is_in_active_area(cell: Vector2i) -> bool:
	return active_area.has_point(cell)

func setup_camera() -> void:
	var first := active_area.position
	var last := active_area.end - Vector2i.ONE
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
const ELEV_STEP: float = 6.0  ## harus sama dengan selisih texture_origin antar alternative tile
const ELEV_NAMES := ["Garis pantai", "Dataran rendah", "Dataran menengah", "Dataran tinggi"]

func get_elev(cell: Vector2i) -> int:
	return elevation.get(cell, 0)

func set_elev(cell: Vector2i, h: int) -> void:
	elevation[cell] = clampi(h, 0, MAX_ELEV)
	world.set_cell(cell, main_source_id, Vector2i(grid_data[cell], 0), elevation[cell])

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

enum Tool { GALI, RATAKAN, TIMBUN, JEMBATAN, BOR, BENDUNGAN, SPILLWAY }
const TOOL_NAMES := ["Gali", "Ratakan", "Timbun", "Jembatan", "Mesin Bor", "Bendungan", "Spillway"]
var current_tool: int = Tool.GALI

func set_tool(t: int) -> void:
	current_tool = t
	var btns := [btn_gali, btn_ratakan, btn_timbun, btn_jembatan, btn_bor, btn_bendungan, btn_spillway]
	for i in btns.size():
		btns[i].set_pressed_no_signal(i == t)
	update_hud()

func _unhandled_input(event: InputEvent) -> void:
	if game_over:
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_R:
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
		return

	if event is InputEventMouseButton and event.is_pressed() \
			and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		var cell := pick_cell(get_global_mouse_position())
		if not grid_data.has(cell) or not is_in_active_area(cell):
			return
		var right: bool = event.button_index == MOUSE_BUTTON_RIGHT
		match current_tool:
			Tool.GALI:
				if not right: perform_digging(cell)
			Tool.RATAKAN:
				perform_leveling(cell, 1 if right else -1)
			Tool.TIMBUN:
				if not right: perform_filling(cell)
			Tool.JEMBATAN:
				if not right and roads.build_bridge(cell):
					update_water()
					update_hud()
			Tool.BOR, Tool.BENDUNGAN, Tool.SPILLWAY:
				var kind: int = current_tool - Tool.BOR  # urutan sama dengan FacilityManager.Kind
				if not right and facilities.place(kind, cell):
					update_water()
					update_hud()

## Gali: tanah (DIRT/GRASS) -> kanal.
func perform_digging(cell_pos: Vector2i) -> void:
	if buildings.has_building(cell_pos) or facilities.has_facility(cell_pos):
		return
	var current_state = grid_data[cell_pos]
	if current_state == TileState.DIRT or current_state == TileState.GRASS:
		dug[cell_pos] = true
		change_tile_state(cell_pos, TileState.CANAL)
		update_water()

## Ratakan: turunkan (klik kiri) / naikkan (klik kanan) satu tingkat.
## Berlaku untuk tanah dan kanal galian, tidak untuk sumber air alami atau bangunan.
func perform_leveling(cell_pos: Vector2i, delta_h: int) -> void:
	if buildings.has_building(cell_pos) or roads.is_road(cell_pos) or facilities.has_facility(cell_pos):
		return
	if is_natural_water(cell_pos) or weather.is_dried(cell_pos):
		return
	var h := clampi(get_elev(cell_pos) + delta_h, 0, MAX_ELEV)
	if h == get_elev(cell_pos):
		return
	set_elev(cell_pos, h)
	update_water()

## Timbun: tutup kanal galian (kering atau berair) jadi tanah lagi.
func perform_filling(cell_pos: Vector2i) -> void:
	if facilities.has_facility(cell_pos):
		facilities.remove(cell_pos)
		update_water()
		update_hud()
		return
	if roads.bridges.has(cell_pos):
		roads.remove_bridge(cell_pos)
		update_water()
		return
	if not dug.has(cell_pos):
		return
	dug.erase(cell_pos)
	change_tile_state(cell_pos, TileState.DIRT)
	update_water()

func change_tile_state(cell_pos: Vector2i, new_state: int) -> void:
	grid_data[cell_pos] = new_state
	world.set_cell(cell_pos, main_source_id, Vector2i(new_state, 0), get_elev(cell_pos))

# --- Aliran air dengan gravitasi ---
# Sumber = WATER alami (bukan galian). Air mengalir dari satu petak ke petak kanal
# di sebelahnya hanya kalau kanal itu SAMA TINGGI atau LEBIH RENDAH.

## Kanal yang bisa dicapai air dari sumber alami mengikuti gravitasi.
func compute_reachable() -> Dictionary:
	var reach := {}
	var queue: Array[Vector2i] = []
	for c in dug:
		if is_in_active_area(c):
			for n in world.get_surrounding_cells(c):
				if is_in_active_area(n) and grid_data.get(n, -1) == TileState.WATER \
						and not dug.has(n) and get_elev(n) >= get_elev(c):
					reach[c] = true
					queue.append(c)
					break
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for n in world.get_surrounding_cells(c):
			if dug.has(n) and not reach.has(n) and is_in_active_area(n) and get_elev(n) <= get_elev(c):
				reach[n] = true
				queue.append(n)
	return reach

## Kanal yang punya tetangga berair dengan posisi sama tinggi / lebih tinggi.
func has_feeder(cell: Vector2i) -> bool:
	for n in world.get_surrounding_cells(cell):
		if is_in_active_area(n) and grid_data.get(n, -1) == TileState.WATER and get_elev(n) >= get_elev(cell):
			return true
	return false

## Dipanggil setiap kali peta berubah. Kanal yang terputus langsung kering,
## kanal yang tersambung terisi bertahap per gelombang 0,5 detik.
func update_water() -> void:
	var reach := compute_reachable()
	for c in dug:
		if grid_data[c] == TileState.WATER and not reach.has(c):
			change_tile_state(c, TileState.CANAL)
	for c in reach:
		if grid_data[c] == TileState.CANAL and has_feeder(c):
			flow_queue[c] = true
	if not is_flowing and not flow_queue.is_empty():
		process_flow_queue()

func process_flow_queue() -> void:
	is_flowing = true

	while not flow_queue.is_empty():
		var current_batch = flow_queue.keys()
		flow_queue.clear()

		var changes_made = false

		for cell in current_batch:
			if grid_data.get(cell, -1) == TileState.CANAL and dug.has(cell) and has_feeder(cell):
				change_tile_state(cell, TileState.WATER)
				changes_made = true

				for n in world.get_surrounding_cells(cell):
					if not grid_data.has(n) or not is_in_active_area(n):
						continue
					if grid_data[n] == TileState.CANAL and dug.has(n) and get_elev(n) <= get_elev(cell):
						flow_queue[n] = true
					elif grid_data[n] == TileState.DIRT and not buildings.has_building(n):
						change_tile_state(n, TileState.GRASS)

		if changes_made:
			await get_tree().create_timer(0.5).timeout

	is_flowing = false
