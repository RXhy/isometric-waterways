extends SceneTree
## Pembuat awal peta khusus main menu -> scenes/menu_map.tscn
## Jalankan SEKALI dari terminal:  godot --headless -s res://tools/build_menu_map.gd
## Setelah itu peta diedit langsung di editor Godot (scenes/menu_map.tscn);
## script ini hanya titik awal, menjalankannya lagi akan MENIMPA hasil editan.
##
## Koordinat desain memakai sumbu isometrik (i, j) dari pojok kiri pulau:
##   i+ = ke kanan-bawah layar, j+ = ke kanan-atas layar. Pulau 13 x 13 petak.

const N := 13
const STEP := 4  # px per tingkat elevasi (sama dengan world.gd ELEV_STEP)
const SRC_TERRAIN := 0
const SRC_WATER_ROAD := 1
const SRC_FLOW := 2
# baris tile arus di water_flow.png
const TENANG := 0
const PELAN := 1
const DERAS := 5
enum { TL, TR, BL, BR }

var ground: TileMapLayer
var edge: TileMapLayer
var base := Vector2.ZERO
var water := {}    # Vector2i(i,j) -> baris tile arus
var road := {}     # Vector2i(i,j) -> true
var bridge := {}   # Vector2i(i,j) -> arah (0 / 1)
var props := []    # [jenis, Vector2i(i,j)]
var rng := RandomNumberGenerator.new()

func elev(p: Vector2i) -> int:
	if p.x <= 0 or p.y <= 0 or p.x >= N - 1 or p.y >= N - 1:
		return 0
	var d := p.y - p.x
	if d >= 5: return 3
	if d >= 2: return 2
	if d >= -2: return 1
	return 0

func cell(p: Vector2i) -> Vector2i:
	return ground.local_to_map(base + Vector2((p.x + p.y) * 16, (p.x - p.y) * 8))

func pos(p: Vector2i) -> Vector2:
	return ground.map_to_local(cell(p)) - Vector2(0, STEP * elev(p))

func path(start: Vector2i, legs: Array) -> Array:
	# legs: [[arah, jumlah, deras?], ...]  arah: BL = j-1, BR = i+1, TR = j+1, TL = i-1
	var out := []
	var cur := start
	for leg in legs:
		for k in leg[1]:
			out.append([cur, leg[0], leg[2] if leg.size() > 2 else false])
			match leg[0]:
				BL: cur += Vector2i(0, -1)
				BR: cur += Vector2i(1, 0)
				TR: cur += Vector2i(0, 1)
				TL: cur += Vector2i(-1, 0)
	out.append([cur, -1, false])
	return out

func flow_row(dir: int, fast: bool) -> int:
	# urutan arah di tile arus: 0 kiri-atas, 1 kanan-atas, 2 kiri-bawah, 3 kanan-bawah
	var idx: int = {TL: 0, TR: 1, BL: 2, BR: 3}[dir]
	return (DERAS if fast else PELAN) + idx

func design() -> void:
	# Laut tenang mengelilingi pulau
	for i in N:
		for j in N:
			if i == 0 or j == 0 or i == N - 1 or j == N - 1:
				water[Vector2i(i, j)] = TENANG
	# Danau di depan (dataran rendah), tersambung ke laut
	for i in range(7, 12):
		for j in range(1, 5):
			var p := Vector2i(i, j)
			if p.y - p.x <= -3 and Vector2(i - 8.8, j - 2.4).length() < 2.4:
				water[p] = TENANG
	water[Vector2i(11, 2)] = TENANG
	# Sungai: mata air di dataran tinggi, berkelok turun ke danau (arus mengikuti arah)
	water[Vector2i(1, 10)] = TENANG  # kolam mata air
	water[Vector2i(2, 11)] = TENANG
	water[Vector2i(1, 11)] = TENANG
	var river := path(Vector2i(2, 10), [[BL, 2], [BR, 3, true], [BL, 2, true], [BR, 2], [BL, 2, true]])
	for st in river:
		if st[1] >= 0:
			water[st[0]] = flow_row(st[1], st[2])
	# Kanal galian dari sungai ke desa
	for i in range(6, 10):
		water[Vector2i(i, 7)] = flow_row(BR, false)
	# Jalan desa: memanjang di sumbu j, menyeberang kanal dengan jembatan
	for j in range(5, 12):
		var p := Vector2i(8, j)
		if not water.has(p) or j == 7:
			road[p] = true
	for i in range(9, 11):
		road[Vector2i(i, 10)] = true
	bridge[Vector2i(8, 7)] = 1
	# Bangunan, ladang, fasilitas
	for p in [Vector2i(9, 8), Vector2i(10, 9), Vector2i(7, 9), Vector2i(9, 11), Vector2i(10, 11)]:
		props.append(["rumah", p])
	for p in [Vector2i(9, 6), Vector2i(10, 6), Vector2i(10, 7), Vector2i(6, 4)]:
		props.append(["ladang", p])
	props.append(["kincir", Vector2i(7, 7)])
	props.append(["kincir", Vector2i(3, 8)])
	props.append(["bor", Vector2i(3, 3)])
	props.append(["bendungan", Vector2i(10, 8)])

func near_water(p: Vector2i, r: int) -> int:
	var best := 99
	for w in water:
		var dd: int = absi(w.x - p.x) + absi(w.y - p.y)
		if dd < best:
			best = dd
	return best if best <= r else -1

func land_tile(p: Vector2i) -> Vector2i:
	var court := false
	for pr in props:
		if pr[0] == "rumah" and absi(pr[1].x - p.x) + absi(pr[1].y - p.y) <= 1:
			court = true
	if court:
		return Vector2i([0, 1, 4][rng.randi() % 3], 3)
	var d := near_water(p, 2)
	if d == -1:
		# daratan kering: sesekali retak / pohon mati
		var r := rng.randf()
		return Vector2i(4 if r < 0.08 else (1 if r < 0.3 else (2 if r < 0.5 else 0)), 0)
	var row := 1 if d <= 1 else 2
	var r2 := rng.randf()
	var col := 0
	if r2 < 0.18: col = 4        # pohon
	elif r2 < 0.35: col = 3      # semak
	elif r2 < 0.6: col = 1
	return Vector2i(col, row)

func _initialize() -> void:
	rng.seed = 2026
	var world_scene = load("res://world.tscn").instantiate()
	var tileset: TileSet = world_scene.get_node("World").tile_set.duplicate(true)
	var edge_set: TileSet = load("res://assets/water/water_edge_tileset.tres")
	world_scene.free()

	var root_node := Node2D.new()
	root_node.name = "MenuMap"
	var bg_layer := CanvasLayer.new()
	bg_layer.name = "Background"
	bg_layer.layer = -10
	root_node.add_child(bg_layer)
	var grad := Gradient.new()
	grad.set_color(0, Color(0.80, 0.89, 0.92))
	grad.set_color(1, Color(0.60, 0.75, 0.81))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_from = Vector2(0, 0)
	gtex.fill_to = Vector2(0, 1)
	var bg := TextureRect.new()
	bg.name = "Sky"
	bg.texture = gtex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg_layer.add_child(bg)

	ground = TileMapLayer.new()
	ground.name = "Ground"
	ground.tile_set = tileset
	ground.y_sort_enabled = true
	root_node.add_child(ground)
	edge = TileMapLayer.new()
	edge.name = "WaterEdge"
	edge.tile_set = edge_set
	edge.y_sort_enabled = true
	ground.add_child(edge)
	var props_node := Node2D.new()
	props_node.name = "Props"
	props_node.z_index = 1
	props_node.y_sort_enabled = true
	root_node.add_child(props_node)

	base = ground.map_to_local(Vector2i(2, 24))
	design()

	# bayangan lembut di bawah pulau
	var shadow := Polygon2D.new()
	shadow.name = "Shadow"
	shadow.z_index = -1
	shadow.color = Color(0.1, 0.2, 0.25, 0.18)
	var w := N * 16.0 + 2.0   # setengah lebar pulau
	var hh := N * 8.0 + 1.0   # setengah tinggi pulau
	var c0 := base + Vector2((N - 1) * 16, 14)  # pusat pulau, digeser ke bawah
	shadow.polygon = PackedVector2Array([c0 + Vector2(-w, 0), c0 + Vector2(0, -hh), c0 + Vector2(w, 0), c0 + Vector2(0, hh)])
	root_node.add_child(shadow)
	root_node.move_child(shadow, 1)

	# --- tile ---
	for i in N:
		for j in N:
			var p := Vector2i(i, j)
			var h := elev(p)
			if water.has(p):
				ground.set_cell(cell(p), SRC_FLOW, Vector2i(0, water[p]), h)
			elif road.has(p) and not bridge.has(p):
				ground.set_cell(cell(p), SRC_WATER_ROAD, Vector2i(4, 0), h)
			elif bridge.has(p):
				ground.set_cell(cell(p), SRC_FLOW, Vector2i(0, flow_row(BR, false)), h)
			else:
				ground.set_cell(cell(p), SRC_TERRAIN, land_tile(p), h)
	# --- buih tepi air (bit: 1 kiri-atas, 2 kanan-atas, 4 kanan-bawah, 8 kiri-bawah) ---
	var dirs := [[Vector2i(-1, 0), 1], [Vector2i(0, 1), 2], [Vector2i(1, 0), 4], [Vector2i(0, -1), 8]]
	for p in water:
		var mask := 0
		for dd in dirs:
			var q: Vector2i = p + dd[0]
			if q.x < 0 or q.y < 0 or q.x >= N or q.y >= N:
				continue
			if not water.has(q) and not bridge.has(q):
				mask |= dd[1]
		if mask != 0:
			edge.set_cell(cell(p), 0, Vector2i(mask % 4, mask / 4), elev(p))

	# --- objek ---
	var tex_rumah: Texture2D = load("res://assets/placeholder/rumah.png")
	var tex_ladang: Texture2D = load("res://assets/placeholder/ladang.png")
	var scenes := {
		"kincir": load("res://scenes/kincir.tscn"),
		"bor": load("res://scenes/sumur_bor.tscn"),
		"bendungan": load("res://scenes/bendungan.tscn"),
		"jembatan": load("res://scenes/bridge.tscn"),
	}
	var n := 0
	for pr in props:
		var node: Node2D
		match pr[0]:
			"rumah", "ladang":
				var sp := Sprite2D.new()
				sp.texture = tex_rumah if pr[0] == "rumah" else tex_ladang
				sp.offset = Vector2(0, -9) if pr[0] == "rumah" else Vector2(0, -1.5)
				node = sp
			_:
				node = scenes[pr[0]].instantiate()
		n += 1
		node.name = "%s_%d" % [pr[0].capitalize(), n]
		node.position = pos(pr[1])
		props_node.add_child(node)
	for b in bridge:
		var br: Node2D = scenes["jembatan"].instantiate()
		br.name = "Jembatan_%d" % n
		n += 1
		br.position = pos(b)
		br.get_node("Sprite").flip_h = bridge[b] == 1
		props_node.add_child(br)

	# --- kamera: pulau di tengah area kanan (kiri tertutup panel menu 215 px) ---
	var cam := Camera2D.new()
	cam.name = "Camera2D"
	var center := base + Vector2((N - 1) * 16, 0)
	cam.position = center - Vector2(107, -4)
	root_node.add_child(cam)

	_own(root_node, root_node)
	var packed := PackedScene.new()
	packed.pack(root_node)
	print(ResourceSaver.save(packed, "res://scenes/menu_map.tscn"))
	root_node.free()
	quit()

func _own(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.owner = owner_node
		if c.scene_file_path == "":
			_own(c, owner_node)
