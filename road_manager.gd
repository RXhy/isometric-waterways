extends Node2D
## Jalan raya otomatis + jembatan.
## - Setiap bangunan baru disambungkan dengan jalan ke bangunan/jalan terdekat.
## - Jalan tidak bisa digali. Pemain memasang Jembatan di petak jalan supaya
##   kanal bisa lewat di bawahnya. Tampilan jembatan ada di scenes/bridge.tscn.

@export var bridges_start: int = 2    ## stok jembatan di awal
@export var bridges_per_day: int = 1  ## tambahan stok tiap hari baru
@export var bridge_scene: PackedScene ## scenes/bridge.tscn

@export_group("Animasi jalan")
## Jalan baru tidak langsung muncul: dibangun petak demi petak dari jaringan jalan
## yang sudah ada menuju bangunan baru (seperti aliran di Terra Nil).
@export var road_start_delay: float = 0.6   ## detik setelah bangunan muncul sebelum petak jalan pertama dipasang
@export var road_step_delay: float = 0.08   ## jeda antar petak jalan (makin kecil makin cepat mengalir)
@export var road_drop_time: float = 0.22    ## lama animasi satu petak "jatuh" ke tempatnya
@export var road_drop_height: float = 10.0  ## tinggi awal petak sebelum jatuh (px)

var world  # world.gd
var bridges: Dictionary = {}  # petak jembatan -> arah (0: kiri-atas/kanan-bawah, 1: kanan-atas/kiri-bawah)
var bridge_stock: int = 0
var bridge_nodes: Dictionary = {}  # petak -> node jembatan
var pending: Dictionary = {}       # petak jalan yang sedang menunggu giliran dibangun -> true
var _queue: Array = []             # [{"cell": Vector2i, "at": float}] urut waktu pasang
var _clock: float = 0.0

func setup(w) -> void:
	world = w
	bridge_stock = bridges_start

func on_new_day(day: int) -> void:
	if day > 1:
		bridge_stock += bridges_per_day

func is_road(cell: Vector2i) -> bool:
	return world.grid_data.get(cell, -1) == world.TileState.ROAD or bridges.has(cell) or pending.has(cell)

# --- Generasi jalan ---

func _passable(cell: Vector2i) -> bool:
	if not world.is_in_active_area(cell) or world.buildings.has_building(cell) or world.facilities.has_facility(cell):
		return false
	if is_road(cell):
		return true
	if world.dig_pending.has(cell):
		return false
	var t: int = world.grid_data.get(cell, -1)
	return t == world.TileState.DIRT or t == world.TileState.GRASS

func _step_cost(from: Vector2i, to: Vector2i) -> float:
	var c := 0.2 if is_road(to) else 1.0  # utamakan jalan yang sudah ada
	return c + 0.5 * absi(world.get_elev(to) - world.get_elev(from))

func _is_goal(cell: Vector2i, origin: Vector2i) -> bool:
	if is_road(cell):
		return true
	for n in world.world.get_surrounding_cells(cell):
		if n != origin and world.buildings.has_building(n):
			return true
	return false

## Dijkstra dari bangunan baru ke jalan / bangunan lain terdekat.
func connect_building(origin: Vector2i) -> void:
	if world.buildings.buildings.size() <= 1:
		return
	var dist := {origin: 0.0}
	var prev := {}
	var open := [origin]
	var goal = null
	while not open.is_empty():
		var best_i := 0
		for i in open.size():
			if dist[open[i]] < dist[open[best_i]]:
				best_i = i
		var cur: Vector2i = open[best_i]
		open.remove_at(best_i)
		if cur != origin and _is_goal(cur, origin):
			goal = cur
			break
		for n in world.world.get_surrounding_cells(cur):
			if not _passable(n):
				continue
			var d: float = dist[cur] + _step_cost(cur, n)
			if not dist.has(n) or d < dist[n]:
				if not dist.has(n):
					open.append(n)
				dist[n] = d
				prev[n] = cur
	if goal == null:
		return  # tidak ada jalur (terhalang air/kanal)
	# Urutan dari jalan yang sudah ada menuju bangunan baru, lalu dipasang satu per satu.
	var c: Vector2i = goal
	var t: float = _clock + road_start_delay
	while c != origin:
		if not is_road(c):
			pending[c] = true
			_queue.append({"cell": c, "at": t})
			t += road_step_delay
		c = prev[c]
	_queue.sort_custom(func(a, b): return a["at"] < b["at"])

# --- Animasi pemasangan jalan ---

func _process(delta: float) -> void:
	_clock += delta
	while not _queue.is_empty() and _queue[0]["at"] <= _clock:
		var cell: Vector2i = _queue.pop_front()["cell"]
		_drop_tile(cell)

## Petak jalan muncul dari atas dengan efek jatuh + memudar masuk, lalu tile aslinya dipasang.
func _drop_tile(cell: Vector2i) -> void:
	if not pending.has(cell):
		return
	var src_id: int = world.SRC_WATER_ROAD
	var atlas: Vector2i = world.ATLAS_ROAD
	if world.use_tileset_v2:
		# bentuk sementara: anggap petak ini sudah jalan (sambungan ke petak jalan/antrian di sebelahnya)
		src_id = world.SRC_V2
		var keep: int = world.grid_data.get(cell, -1)
		world.grid_data[cell] = world.TileState.ROAD
		atlas = world.v2_atlas(cell)
		world.grid_data[cell] = keep
	world.drop_fx(cell, src_id, atlas, self, _place.bind(cell), road_drop_time, road_drop_height)

func _place(cell: Vector2i) -> void:
	pending.erase(cell)
	if world.grid_data.get(cell, -1) != world.TileState.ROAD and not bridges.has(cell):
		world.set_base(cell, world.TileState.ROAD)

# --- Jembatan ---

func build_bridge(cell: Vector2i) -> bool:
	if bridge_stock <= 0 or bridges.has(cell) or world.grid_data.get(cell, -1) != world.TileState.ROAD:
		return false
	bridge_stock -= 1
	var tl: Vector2i = world.world.get_neighbor_cell(cell, TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE)
	var br: Vector2i = world.world.get_neighbor_cell(cell, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE)
	bridges[cell] = 0 if (is_road(tl) or is_road(br)) else 1
	world.dug[cell] = true
	world.set_base(cell, world.TileState.CANAL)
	var node: Node2D = bridge_scene.instantiate()
	node.position = to_local(world.cell_to_global(cell))
	# gambar asli searah kiri-atas -> kanan-bawah; dibalik untuk arah satunya
	node.get_node("Sprite").flip_h = bridges[cell] == 1
	add_child(node)
	bridge_nodes[cell] = node
	return true

## Timbun jembatan: kembali jadi jalan biasa, stok dikembalikan.
func remove_bridge(cell: Vector2i) -> void:
	bridges.erase(cell)
	bridge_nodes[cell].queue_free()
	bridge_nodes.erase(cell)
	world.dug.erase(cell)
	world.set_base(cell, world.TileState.ROAD)
	bridge_stock += 1
