extends SceneTree
## Pembuat peta latar main menu -> scenes/menu_map.tscn
## Jalankan dari terminal:  godot --headless --path . -s res://tools/build_menu_map.gd
## Menjalankannya lagi akan MENIMPA scenes/menu_map.tscn (termasuk editan manual di editor).
##
## Peta lebar penuh layar (52 x 52 petak isometrik, tepinya di luar layar) memakai
## tileset baru assets/Tiles/tilesset_water_road.png untuk air alami, kanal, dan jalan.
## Desain ditulis dalam koordinat LAYAR relatif pusat kamera (sx, sy) supaya mudah ditata:
##   viewport 640 x 360, pusat (0, 0); panel menu ada di sx -220..-43.
## Koordinat petak (i, j): i+ = kanan-bawah layar, j+ = kanan-atas layar.

const N := 52
const C := 26                 # pusat peta (i = j = C)
const STEP := 4               # px per tingkat elevasi (sama dengan world.gd ELEV_STEP)
const SRC_TERRAIN := 0
const SRC_V2 := 3
const V2_TOP_SHIFT := 0       # sama dengan world.gd v2_top_shift (tanah v3)
const V2_TEX := "res://assets/Tiles/tilesset_water_road.png"
enum { TL = 1, TR = 2, BL = 4, BR = 8 }
const SIDES := [[Vector2i(-1, 0), TL], [Vector2i(0, 1), TR], [Vector2i(0, -1), BL], [Vector2i(1, 0), BR]]
# kolom tile (sama dengan world.gd LINK_COL / LAKE_COL)
const LINK_COL := {0: 2, 1: 2, 8: 2, 9: 2, 2: 3, 4: 3, 6: 3, 10: 0, 12: 1, 3: 4, 5: 5, 14: 6, 11: 7, 13: 8, 7: 9, 15: 10}
const LAKE_COL := {0: 8, 1: 1, 2: 3, 4: 4, 8: 6, 3: 2, 12: 5, 5: 0, 10: 7, 9: 1, 6: 3, 7: 2, 11: 2, 13: 0, 14: 7, 15: 2}

var ground: TileMapLayer
var base := Vector2.ZERO
var water := {}    # air alami (sungai, danau)
var canal := {}    # kanal galian
var road := {}
var bridge := {}   # petak kanal yang dilintasi jalan
var props := []    # [jenis, Vector2i]
var rng := RandomNumberGenerator.new()

# --- koordinat ---

## Petak di posisi layar (sx, sy) relatif pusat kamera.
func at(sx: float, sy: float) -> Vector2i:
	return Vector2i(roundi(C + (sx / 16.0 + sy / 8.0) / 2.0), roundi(C + (sx / 16.0 - sy / 8.0) / 2.0))

func screen(p: Vector2i) -> Vector2:
	return Vector2((p.x + p.y - 2 * C) * 16, (p.x - p.y) * 8)

func elev(p: Vector2i) -> int:
	var s := screen(p)
	var t := s.y + 18.0 * sin((p.x + p.y) * 0.31) + 10.0 * sin(p.x * 0.7)
	if t < -120.0: return 3
	if t < -40.0: return 2
	if t < 55.0: return 1
	return 0

func cell(p: Vector2i) -> Vector2i:
	return ground.local_to_map(base + Vector2((p.x + p.y) * 16, (p.x - p.y) * 8))

func pos(p: Vector2i) -> Vector2:
	return ground.map_to_local(cell(p)) - Vector2(0, STEP * elev(p))

## Jalur isometrik: legs = [[arah, jumlah], ...]; arah TL/TR/BL/BR.
func walk(start: Vector2i, legs: Array) -> Array:
	var out := [start]
	var cur := start
	for leg in legs:
		for k in leg[1]:
			for sd in SIDES:
				if sd[1] == leg[0]:
					cur += sd[0]
			out.append(cur)
	return out

func is_channel(p: Vector2i) -> bool:
	return water.has(p) or canal.has(p)

func is_building(p: Vector2i) -> bool:
	for pr in props:
		if (pr[0] == "rumah" or pr[0] == "ladang") and pr[1] == p:
			return true
	return false

func mask(p: Vector2i, pred: Callable) -> int:
	var m := 0
	for sd in SIDES:
		if pred.call(p + sd[0]):
			m |= sd[1]
	return m

# --- desain ---

func design() -> void:
	# Danau / laut di kiri-bawah layar, tepi bergelombang
	for i in N:
		for j in N:
			var p := Vector2i(i, j)
			var s := screen(p)
			if s.y > 120.0 + 14.0 * sin(s.x * 0.03) + maxf(0.0, s.x + 40.0) * 0.35:
				water[p] = true
	# Kolam mata air di dataran tinggi (kanan atas)
	for i in N:
		for j in N:
			var p := Vector2i(i, j)
			if screen(p).distance_to(Vector2(40, -150)) < 26.0:
				water[p] = true
	# Sungai 2 petak berkelok dari kolam turun ke danau
	var river := walk(at(30, -140), [[BL, 4], [BR, 5], [BL, 4], [BR, 3], [BL, 6], [BR, 4], [BL, 8]])
	for p in river:
		water[p] = true
		water[p + Vector2i(1, 0)] = true
	# Sungai kedua di kiri (terlihat sedikit di sisi kiri panel)
	for p in walk(at(-300, -150), [[BR, 5], [BL, 3], [BR, 8], [BL, 4], [BR, 6]]):
		water[p] = true
		water[p + Vector2i(0, 1)] = true

	# Desa di kanan: jalan berbentuk tangga dengan rumah di sisinya
	var v0 := at(150, -10)
	var main_road := walk(v0, [[BR, 4], [TR, 5], [BR, 4], [TR, 4]])
	for p in main_road:
		road[p] = true
	for p in walk(v0 + Vector2i(2, 0), [[BL, 4]]):
		road[p] = true
	for p in walk(v0 + Vector2i(4, 5), [[TL, 4]]):
		road[p] = true
	# Kanal galian dari sungai ke desa (melintas jalan dengan jembatan)
	var river_pt: Vector2i = river[16]
	var canal_path := walk(river_pt + Vector2i(2, 0), [[TR, 3], [BR, 1]])
	var cur: Vector2i = canal_path[-1]
	while screen(cur).x < 140.0 and canal_path.size() < 40:
		cur += Vector2i(0, 1)
		canal_path.append(cur)
	for p in canal_path:
		if not water.has(p):
			canal[p] = true
	for p in canal:
		if road.has(p):
			bridge[p] = true
	for p in bridge:
		road.erase(p)
	# Rumah di sisi jalan, ladang dekat kanal
	var spots := [Vector2i(1, -1), Vector2i(-1, 1)]
	var houses := 0
	for k in range(0, main_road.size(), 2):
		for d in spots:
			var h: Vector2i = main_road[k] + d
			if houses < 9 and not road.has(h) and not is_channel(h) and not is_building(h) and rng.randf() < 0.7:
				props.append(["rumah", h])
				houses += 1
	var farms := 0
	for p in canal:
		for d in [Vector2i(-1, 0), Vector2i(1, 0)]:
			var f: Vector2i = p + d
			if farms < 6 and not is_channel(f) and not road.has(f) and not is_building(f) and rng.randf() < 0.45:
				props.append(["ladang", f])
				farms += 1
	# Fasilitas
	props.append(["kincir", river[9]])
	props.append(["kincir", river[22]])
	props.append(["bor", at(250, -120)])
	props.append(["bor", at(-90, -130)])

func near_water(p: Vector2i, r: int) -> int:
	var best := 99
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			if is_channel(p + Vector2i(dx, dy)):
				best = mini(best, absi(dx) + absi(dy))
	return best if best <= r else -1

func land_tile(p: Vector2i) -> Vector2i:
	for pr in props:
		if pr[0] == "rumah" and absi(pr[1].x - p.x) + absi(pr[1].y - p.y) <= 1:
			return Vector2i([0, 1, 4][rng.randi() % 3], 3)
	var d := near_water(p, 3)
	if d == -1:
		var r := rng.randf()
		return Vector2i(4 if r < 0.08 else (1 if r < 0.3 else (2 if r < 0.5 else 0)), 0)
	var row := 1 if d <= 1 else 2
	var r2 := rng.randf()
	var col := 0
	if r2 < 0.18: col = 4
	elif r2 < 0.35: col = 3
	elif r2 < 0.6: col = 1
	return Vector2i(col, row)

## Atlas source tileset baru (sama seperti world.gd _build_v2_source), disimpan di scene menu.
func add_v2_source(ts: TileSet) -> void:
	var tex: Texture2D = load(V2_TEX)
	var land: TileSetAtlasSource = ts.get_source(SRC_TERRAIN)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(32, 32)
	var rows: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 17]
	for r in rows:
		for c in (9 if r < 9 else 11):
			var a := Vector2i(c, r)
			src.create_tile(a)
			for h in 4:
				if h > 0:
					src.create_alternative_tile(a, h)
				var td: TileData = src.get_tile_data(a, h)
				var ref: TileData = land.get_tile_data(Vector2i(0, 0), h)
				td.texture_origin = ref.texture_origin + Vector2i(0, V2_TOP_SHIFT)
				td.modulate = ref.modulate
	ts.add_source(src, SRC_V2)

func _initialize() -> void:
	rng.seed = 2026
	var world_scene = load("res://world.tscn").instantiate()
	var tileset: TileSet = world_scene.get_node("World").tile_set.duplicate(true)
	world_scene.free()
	if tileset.has_source(SRC_V2):
		tileset.remove_source(SRC_V2)
	add_v2_source(tileset)

	var root_node := Node2D.new()
	root_node.name = "MenuMap"
	var bg_layer := CanvasLayer.new()
	bg_layer.name = "Background"
	bg_layer.layer = -10
	root_node.add_child(bg_layer)
	var bg := ColorRect.new()
	bg.name = "Sky"
	bg.color = Color(0.35, 0.55, 0.62)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg_layer.add_child(bg)

	ground = TileMapLayer.new()
	ground.name = "Ground"
	ground.tile_set = tileset
	ground.y_sort_enabled = true
	root_node.add_child(ground)
	var props_node := Node2D.new()
	props_node.name = "Props"
	props_node.z_index = 1
	props_node.y_sort_enabled = true
	root_node.add_child(props_node)

	base = ground.map_to_local(Vector2i(2, 2 * N + 4))
	design()

	var is_road_like := func(q: Vector2i) -> bool: return road.has(q) or bridge.has(q)
	for i in N:
		for j in N:
			var p := Vector2i(i, j)
			var h := elev(p)
			if water.has(p):
				var lm := mask(p, func(q): return not is_channel(q) and q.x >= 0 and q.y >= 0 and q.x < N and q.y < N)
				ground.set_cell(cell(p), SRC_V2, Vector2i(LAKE_COL[lm], 3 + 2), h)
			elif canal.has(p):
				var cm := mask(p, is_channel)
				cm |= mask(p, is_building)
				ground.set_cell(cell(p), SRC_V2, Vector2i(LINK_COL[cm], 12), h)
			elif road.has(p):
				var rm: int = mask(p, is_road_like)
				if rm in [0, 1, 2, 4, 8]:
					rm |= mask(p, is_building)
				ground.set_cell(cell(p), SRC_V2, Vector2i(LINK_COL[rm], 17), h)
			else:
				ground.set_cell(cell(p), SRC_TERRAIN, land_tile(p), h)

	# --- objek ---
	var tex_rumah: Texture2D = load("res://assets/placeholder/rumah.png")
	var tex_ladang: Texture2D = load("res://assets/placeholder/ladang.png")
	var scenes := {
		"kincir": load("res://scenes/kincir.tscn"),
		"bor": load("res://scenes/sumur_bor.tscn"),
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
		n += 1
		br.name = "Jembatan_%d" % n
		br.position = pos(b)
		br.get_node("Sprite").flip_h = road.has(b + Vector2i(-1, 0)) or road.has(b + Vector2i(1, 0))
		props_node.add_child(br)

	# --- kamera: pusat peta di tengah layar; peta menutupi seluruh layar ---
	var cam := Camera2D.new()
	cam.name = "Camera2D"
	cam.position = ground.map_to_local(cell(Vector2i(C, C)))
	root_node.add_child(cam)

	_own(root_node, root_node)
	var packed := PackedScene.new()
	packed.pack(root_node)
	print("simpan menu_map: ", ResourceSaver.save(packed, "res://scenes/menu_map.tscn"))
	root_node.free()
	quit()

func _own(nd: Node, owner_node: Node) -> void:
	for c in nd.get_children():
		c.owner = owner_node
		if c.scene_file_path == "":
			_own(c, owner_node)
