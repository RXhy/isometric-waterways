extends Node2D
## Jalan raya otomatis + jembatan.
## - Setiap bangunan baru disambungkan dengan jalan ke bangunan/jalan terdekat.
## - Jalan tidak bisa digali. Pemain memasang Jembatan di petak jalan supaya
##   kanal bisa lewat di bawahnya. Papan jembatan digambar di sini (placeholder).

@export var bridges_start: int = 2    ## stok jembatan di awal
@export var bridges_per_day: int = 1  ## tambahan stok tiap hari baru

var world  # world.gd
var bridges: Dictionary = {}  # petak jembatan -> arah (0: kiri-atas/kanan-bawah, 1: kanan-atas/kiri-bawah)
var bridge_stock: int = 0

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
	if not world.is_in_active_area(cell) or world.buildings.has_building(cell):
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
	queue_redraw()
	return true

## Timbun jembatan: kembali jadi jalan biasa, stok dikembalikan.
func remove_bridge(cell: Vector2i) -> void:
	bridges.erase(cell)
	world.dug.erase(cell)
	world.change_tile_state(cell, world.TileState.ROAD)
	bridge_stock += 1
	queue_redraw()

func _draw() -> void:
	for cell in bridges:
		var p: Vector2 = to_local(world.cell_to_global(cell)) + Vector2(0, -3)
		var a := Vector2(8.0, 4.0)     # setengah panjang searah jalan (sampai tepi petak)
		var b := Vector2(8.0, -4.0)    # setengah lebar melintang
		if bridges[cell] == 1:
			var t := a
			a = b
			b = t
		var w := 0.5
		var deck := PackedVector2Array([p - a - b * w, p + a - b * w, p + a + b * w, p - a + b * w])
		draw_colored_polygon(deck, Color(0.58, 0.38, 0.21))
		for i in range(-3, 4):
			var c := p + a * (i / 3.5)
			draw_line(c - b * w, c + b * w, Color(0.36, 0.22, 0.11), 1.0)
		var outline := deck.duplicate()
		outline.append(deck[0])
		draw_polyline(outline, Color(0.22, 0.13, 0.07), 1.0)
