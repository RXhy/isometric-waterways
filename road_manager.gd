extends Node2D
## Jalan raya otomatis + jembatan.
## - Setiap bangunan baru disambungkan dengan jalan ke bangunan/jalan terdekat.
## - Jalan tidak bisa digali. Pemain memasang Jembatan di petak jalan supaya
##   kanal bisa lewat di bawahnya. Tampilan jembatan ada di scenes/bridge.tscn.

@export var bridges_start: int = 2    ## stok jembatan di awal
@export var bridges_per_day: int = 1  ## tambahan stok tiap hari baru
@export var bridge_scene: PackedScene ## scenes/bridge.tscn

var world  # world.gd
var bridges: Dictionary = {}  # petak jembatan -> arah (0: kiri-atas/kanan-bawah, 1: kanan-atas/kiri-bawah)
var bridge_stock: int = 0
var bridge_nodes: Dictionary = {}  # petak -> node jembatan

func setup(w) -> void:
	world = w
	bridge_stock = bridges_start

func on_new_day(day: int) -> void:
	if day > 1:
		bridge_stock += bridges_per_day

func is_road(cell: Vector2i) -> bool:
	return world.grid_data.get(cell, -1) == world.TileState.ROAD or bridges.has(cell)

# --- Generasi jalan ---

func _passable(cell: Vector2i) -> bool:
	if not world.is_in_active_area(cell) or world.buildings.has_building(cell) or world.facilities.has_facility(cell):
		return false
	if is_road(cell):
		return true
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
	var c: Vector2i = goal
	while c != origin:
		if not is_road(c):
			world.change_tile_state(c, world.TileState.ROAD)
		c = prev[c]

# --- Jembatan ---

func build_bridge(cell: Vector2i) -> bool:
	if bridge_stock <= 0 or bridges.has(cell) or world.grid_data.get(cell, -1) != world.TileState.ROAD:
		return false
	bridge_stock -= 1
	var tl: Vector2i = world.world.get_neighbor_cell(cell, TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE)
	var br: Vector2i = world.world.get_neighbor_cell(cell, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE)
	bridges[cell] = 0 if (is_road(tl) or is_road(br)) else 1
	world.dug[cell] = true
	world.change_tile_state(cell, world.TileState.CANAL)
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
	world.change_tile_state(cell, world.TileState.ROAD)
	bridge_stock += 1
