extends Node
## Simulasi air berbasis kedalaman (terinspirasi Timberborn).
##
## Setiap petak di area aktif menyimpan kedalaman air. Satuan tinggi: 1.0 = satu tingkat elevasi.
##   permukaan = dasar + kedalaman
##   dasar     = elevasi              (daratan)
##             = elevasi - channel_depth  (kanal galian, dasar sungai/danau, sumur bor)
## Tiap langkah, air berpindah ke tetangga sisi yang permukaannya lebih rendah.
## Kanal/sungai punya "tepi" setinggi elevasinya sendiri: air baru tumpah ke daratan
## kalau permukaannya melewati tepi itu (meluap). Jadi air tidak bisa naik, dan banjir
## muncul sendiri saat sumber terlalu penuh.
##
## Sumber air = badan air alami (mengisi ulang menuju target, diatur cuaca) dan sumur bor.
## Bendungan = petak kedap air. Spillway = kanal yang membuang kelebihan air.

@export var tick_rate: float = 20.0         ## langkah simulasi per detik
@export var flow_k: float = 0.2             ## porsi selisih permukaan yang berpindah per langkah (maks 0.25)
@export var channel_depth: float = 0.5      ## dalamnya kanal/dasar sungai di bawah permukaan tanah
@export var source_rate: float = 1.5        ## kecepatan sumber mengisi ulang ke targetnya (per detik)
@export var wet_threshold: float = 0.06     ## kedalaman minimal agar petak terlihat/terhitung berair
@export var flood_threshold: float = 0.1    ## kedalaman air di daratan yang dihitung banjir
@export var canal_evaporation: float = 0.02 ## penguapan kanal galian per detik
@export var land_absorb: float = 0.08       ## air di daratan meresap per detik (membatasi luas banjir)
@export var spillway_drain: float = 1.0     ## laju spillway membuang air per detik
@export var near_water_radius: int = 2      ## daratan sejauh ini dari air berair tampil hijau (baris 2-3 tileset)

var world
var depth: Dictionary = {}       # Vector2i -> float
var body_of: Dictionary = {}     # petak badan air alami -> id badan air
var body_size: Dictionary = {}   # id -> jumlah petak
var body_target: Dictionary = {} # id -> target kedalaman sumber
var wells: Dictionary = {}       # petak sumur bor -> true
var drains: Dictionary = {}      # petak spillway -> true
var walls: Dictionary = {}       # petak bendungan -> true
var cells: Array[Vector2i] = []  # semua petak di area aktif

var _acc := 0.0
var _vis: Dictionary = {}        # cache tile yang sedang tampil
var _grass_timer := 0.0

func setup(w) -> void:
	world = w
	var a: Rect2i = world.active_area
	for y in range(a.position.y, a.end.y):
		for x in range(a.position.x, a.end.x):
			var c := Vector2i(x, y)
			if world.grid_data.has(c):
				cells.append(c)
	_compute_bodies()
	for c in body_of:
		depth[c] = channel_depth
	for id in body_size:
		body_target[id] = channel_depth
	refresh_all()
	update_land()

# --- Data petak ---

func is_channel(c: Vector2i) -> bool:
	var t: int = world.grid_data.get(c, -1)
	return t == world.TileState.CANAL or t == world.TileState.WATER

func is_natural(c: Vector2i) -> bool:
	return body_of.has(c)

func ground(c: Vector2i) -> float:
	return float(world.get_elev(c)) - (channel_depth if is_channel(c) else 0.0)

func get_depth(c: Vector2i) -> float:
	return depth.get(c, 0.0)

func surface(c: Vector2i) -> float:
	return ground(c) + get_depth(c)

func is_wet(c: Vector2i) -> bool:
	return get_depth(c) >= wet_threshold

func is_flooded(c: Vector2i) -> bool:
	return not is_channel(c) and get_depth(c) >= flood_threshold

## Badan air alami yang sedang kering (misal saat kemarau).
func is_dry_source(c: Vector2i) -> bool:
	return (is_natural(c) or wells.has(c)) and not is_wet(c)

func _open(c: Vector2i) -> bool:
	return world.is_in_active_area(c) and world.grid_data.has(c) and not walls.has(c)

# --- Badan air alami ---

func _compute_bodies() -> void:
	var next_id := 0
	for c in cells:
		if body_of.has(c) or world.grid_data[c] != world.TileState.WATER:
			continue
		var stack: Array[Vector2i] = [c]
		body_of[c] = next_id
		var n := 0
		while not stack.is_empty():
			var cur: Vector2i = stack.pop_back()
			n += 1
			for nb in world.world.get_surrounding_cells(cur):
				if not body_of.has(nb) and world.is_in_active_area(nb) \
						and world.grid_data.get(nb, -1) == world.TileState.WATER:
					body_of[nb] = next_id
					stack.append(nb)
		body_size[next_id] = n
		next_id += 1

## Id badan air alami yang bersebelahan dengan petak ini.
func bodies_touching(c: Vector2i) -> Array:
	var out := []
	for nb in world.world.get_surrounding_cells(c):
		if body_of.has(nb) and not out.has(body_of[nb]):
			out.append(body_of[nb])
	return out

# --- Perubahan dari pemain / fasilitas ---

func add_well(c: Vector2i) -> void:
	wells[c] = true
	refresh_cell(c)

func remove_well(c: Vector2i) -> void:
	wells.erase(c)
	depth.erase(c)
	refresh_cell(c)

func set_wall(c: Vector2i, on: bool) -> void:
	if on:
		walls[c] = true
		depth.erase(c)
	else:
		walls.erase(c)
	refresh_cell(c)

func set_drain(c: Vector2i, on: bool) -> void:
	if on:
		drains[c] = true
	else:
		drains.erase(c)

func clear_water(c: Vector2i) -> void:
	depth.erase(c)
	refresh_cell(c)

# --- Langkah simulasi ---

func _process(delta: float) -> void:
	if world == null or world.game_over:
		return
	var step := 1.0 / tick_rate
	_acc = min(_acc + delta, step * 4.0)  # jangan menumpuk kalau frame tersendat
	var stepped := false
	while _acc >= step:
		_acc -= step
		step_sim(step)
		stepped = true
	if stepped:
		refresh_all()
	_grass_timer += delta
	if _grass_timer >= 1.0:
		_grass_timer = 0.0
		update_land()

func step_sim(dt: float) -> void:
	# 1) Sumber mengisi ulang (atau surut) menuju targetnya
	var k: float = min(1.0, source_rate * dt)
	for c in body_of:
		var t: float = body_target[body_of[c]]
		depth[c] = get_depth(c) + (t - get_depth(c)) * k
	for c in wells:
		depth[c] = get_depth(c) + (channel_depth - get_depth(c)) * k

	# 2) Aliran antar petak
	var change := {}
	for c in cells:
		var d := get_depth(c)
		if d <= 0.0001 or not _open(c):
			continue
		var s := ground(c) + d
		var channel := is_channel(c)
		var bank := float(world.get_elev(c))
		var outs := []
		var total := 0.0
		for nb in world.world.get_surrounding_cells(c):
			if not _open(nb):
				continue
			var level := surface(nb)
			if channel and not is_channel(nb):
				level = max(level, bank)  # air hanya tumpah ke daratan kalau melewati tepi kanal
			var head := s - level
			if head > 0.0005:
				var f := head * flow_k
				outs.append([nb, f])
				total += f
		if total <= 0.0:
			continue
		var scale: float = min(1.0, d / total)
		for o in outs:
			var f: float = o[1] * scale
			change[c] = change.get(c, 0.0) - f
			change[o[0]] = change.get(o[0], 0.0) + f
	for c in change:
		depth[c] = max(0.0, get_depth(c) + change[c])

	# 3) Penguapan, resapan, spillway
	for c in depth.keys():
		var d: float = depth[c]
		if drains.has(c):
			d -= spillway_drain * dt
		elif not is_channel(c):
			d -= land_absorb * dt
		elif not body_of.has(c) and not wells.has(c):
			d -= canal_evaporation * dt
		if d <= 0.0001:
			depth.erase(c)
		else:
			depth[c] = d

# --- Tampilan ---

## Tile yang ditampilkan untuk petak ini, dari jenis dasar + kedalaman air.
func visual_tile(c: Vector2i) -> int:
	var base: int = world.grid_data[c]
	var wet := is_wet(c)
	if base == world.TileState.WATER or base == world.TileState.CANAL:
		return world.TileState.WATER if wet else world.TileState.CANAL
	if get_depth(c) >= flood_threshold:
		return world.TileState.WATER
	return base

func refresh_cell(c: Vector2i) -> void:
	_vis.erase(c)
	if world.grid_data.has(c):
		var t := visual_tile(c)
		_vis[c] = t
		world.show_tile(c, t)

func refresh_all() -> void:
	for c in cells:
		var t := visual_tile(c)
		if _vis.get(c, -1) != t:
			_vis[c] = t
			world.show_tile(c, t)

## Tentukan kelas tiap daratan di area aktif dari jarak ke air yang sedang berair:
##   jauh dari air -> kering (baris 0), dekat air -> hijau (baris 1-2),
##   bangunan dekat air + tetangga sisinya -> pelataran (baris 3).
func update_land() -> void:
	var dist := {}
	var frontier: Array[Vector2i] = []
	for c in cells:
		if is_channel(c) and is_wet(c):
			dist[c] = 0
			frontier.append(c)
	for d in range(1, near_water_radius + 1):
		var nxt: Array[Vector2i] = []
		for c in frontier:
			for nb in world.world.get_surrounding_cells(c):
				if not dist.has(nb) and world.is_in_active_area(nb):
					dist[nb] = d
					nxt.append(nb)
		frontier = nxt
	var courtyard := {}
	for b in world.buildings.buildings:
		if dist.has(b):
			courtyard[b] = true
			for nb in world.world.get_surrounding_cells(b):
				courtyard[nb] = true
	for c in cells:
		var t: int = world.grid_data[c]
		if t != world.TileState.DIRT and t != world.TileState.GRASS:
			continue
		var cls: int = world.LandClass.DRY
		if courtyard.has(c):
			cls = world.LandClass.COURTYARD
		elif dist.has(c):
			cls = world.LandClass.NEAR
		var dd: int = dist.get(c, 0)
		if world.land_class.get(c, -1) != cls:
			world.set_land_class(c, cls, dd)
