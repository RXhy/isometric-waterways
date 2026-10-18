extends Node2D
## Fasilitas: Mesin Bor, Bendungan, Spillway (mitigasi cuaca) dan Kincir Air (penghasil poin).
## Tampilan tiap fasilitas ada di scenes/*.tscn (diatur lewat Inspector).

enum Kind { BOR, BENDUNGAN, SPILLWAY, KINCIR }
const KIND_NAMES := ["Drill Well", "Dam", "Spillway", "Water Wheel"]

@export var bor_scene: PackedScene
@export var bendungan_scene: PackedScene
@export var spillway_scene: PackedScene
@export var kincir_scene: PackedScene
@export var start_stock: Array[int] = [1, 0, 1, 1]  ## stok awal [Bor, Bendungan, Spillway, Kincir]
@export var stock_every_days: Array[int] = [3, 0, 5, 3]  ## stok +1 tiap N hari [Bor, Bendungan, Spillway, Kincir]; 0 = tidak bertambah
@export var facilities_sort_with_buildings: bool = true  ## urutan gambar fasilitas digabung dengan bangunan (yang di depan menutupi yang di belakang)
@export var kincir_face_invert: bool = true  ## balik arah kincir kalau sprite terlihat terbalik
## (lama, tidak dipakai lagi)
@export var stock_per_forecast: Array[int] = [1, 0, 1, 1]  ## tambahan stok [Bor, Bendungan (dihapus, biarkan 0), Spillway, Kincir]; Kincir bertambah saat besok Cerah
@export_group("Water Wheel")
## Fungsi utama kincir: POMPA. Air dari petak kincir diangkat ke kanal/sungai di sebelahnya
## (4 sisi) yang lebih tinggi, supaya aliran bisa naik ke dataran yang lebih tinggi.
@export var kincir_lift_rate: float = 0.8   ## air yang diangkat per detik (kedalaman/detik)
@export var kincir_max_lift: int = 1        ## beda tingkat elevasi maksimal yang bisa dinaikkan
@export var kincir_full_flux: float = 0.1        ## debit (kedalaman/detik) yang membuat kincir berputar penuh
@export var kincir_points_per_second: float = 0.25 ## poin per detik saat berputar penuh (7.5/hari, setara ~1 bangunan terlayani)

var world
var stock: Array[int] = [0, 0, 0, 0]
var facilities: Dictionary = {}  # Vector2i -> {"kind": int, "node": Node2D}

func setup(w) -> void:
	world = w
	stock = start_stock.duplicate()

func has_facility(cell: Vector2i) -> bool:
	return facilities.has(cell)

func kind_at(cell: Vector2i) -> int:
	return facilities[cell]["kind"] if facilities.has(cell) else -1

## Dipanggil saat prakiraan cuaca besok diumumkan.
func on_forecast(_weather: int) -> void:
	pass

## Dipanggil tiap hari baru (dari world.gd): tambah stok berkala.
func on_new_day(day: int) -> void:
	if day <= 1:
		return
	for k in stock_every_days.size():
		var n: int = stock_every_days[k]
		if n > 0 and (day - 1) % n == 0:
			stock[k] += 1

func _old_on_forecast(weather: int) -> void:
	if weather == world.weather.Weather.KEMARAU:
		stock[Kind.BOR] += stock_per_forecast[Kind.BOR]
	elif weather == world.weather.Weather.HUJAN:
		stock[Kind.BENDUNGAN] += stock_per_forecast[Kind.BENDUNGAN]
		stock[Kind.SPILLWAY] += stock_per_forecast[Kind.SPILLWAY]
	else:
		stock[Kind.KINCIR] += stock_per_forecast[Kind.KINCIR]

func _get_water_mask(cell: Vector2i) -> int:
	var tl = world.world.get_neighbor_cell(cell, TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE)
	var tr = world.world.get_neighbor_cell(cell, TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE)
	var bl = world.world.get_neighbor_cell(cell, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE)
	var br = world.world.get_neighbor_cell(cell, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE)
	
	var mask = 0
	if world.water.is_channel(tl): mask |= 1
	if world.water.is_channel(tr): mask |= 2
	if world.water.is_channel(bl): mask |= 4
	if world.water.is_channel(br): mask |= 8
	return mask

## Alasan fasilitas tidak bisa dipasang di petak ini ("" kalau bisa). Dipakai tooltip HUD.
func why_not(kind: int, cell: Vector2i) -> String:
	if stock[kind] <= 0:
		return "Out of %s" % KIND_NAMES[kind]
	if facilities.has(cell) or world.buildings.has_building(cell):
		return "Tile is occupied"
	if world.dig_pending.has(cell):
		return "Digging..."
	if world.roads.is_road(cell):
		return "Can't be placed on roads"
	var t: int = world.grid_data.get(cell, -1)
	var land: bool = t == world.TileState.DIRT or t == world.TileState.GRASS
	match kind:
		Kind.KINCIR:
			if not world.water.is_channel(cell):
				return "Canals or rivers only"
			if world.water.wells.has(cell):
				return "Tile is occupied"
		Kind.BENDUNGAN:
			if not (land or world.dug.has(cell)):
				return "On land or across a canal only"
		Kind.SPILLWAY:
			if not world.water.is_channel(cell):
				return "Canals or rivers only"
			var mask = _get_water_mask(cell)
			if mask != 9 and mask != 6:
				return "Straight waterways only"
		_:
			if not land:
				return "Land only"
	return ""

func can_place(kind: int, cell: Vector2i) -> bool:
	if stock[kind] <= 0 or facilities.has(cell) or world.buildings.has_building(cell):
		return false
	if not world.is_playable(cell) or world.roads.is_road(cell):
		return false
	var t: int = world.grid_data.get(cell, -1)
	var land: bool = t == world.TileState.DIRT or t == world.TileState.GRASS
	match kind:
		Kind.KINCIR:
			# kincir dipasang di air (kanal galian atau sungai/danau), tidak menghalangi aliran
			return world.water.is_channel(cell) and not world.water.wells.has(cell)
		Kind.BENDUNGAN:
			# tanggul/bendungan boleh di tanah atau melintang di kanal galian
			return land or world.dug.has(cell)
		Kind.SPILLWAY:
			if not world.water.is_channel(cell):
				return false
			var mask = _get_water_mask(cell)
			return mask == 9 or mask == 6
	return land

func place(kind: int, cell: Vector2i) -> bool:
	if not can_place(kind, cell):
		return false
	stock[kind] -= 1
	var scene: PackedScene = [bor_scene, bendungan_scene, spillway_scene, kincir_scene][kind]
	var node: Node2D = scene.instantiate()
	
	# --- PENYESUAIAN WARNA KINCIR BERDASARKAN ELEVASI TILE ---
	if kind == Kind.KINCIR:
		var elev = world.get_elev(cell)
		if elev == 0:
			node.modulate = Color(0.8, 0.8, 0.8) # Paling gelap untuk elevasi bawah
		elif elev == 1:
			node.modulate = Color(0.9, 0.9, 0.9)
		else:
			node.modulate = Color(1.0, 1.0, 1.0) # Warna asli untuk dataran tinggi
	elif kind == Kind.SPILLWAY:
		var mask = _get_water_mask(cell)
		var spr = node.get_node("Sprite")
		spr.hframes = 2
		spr.frame = 0 if mask == 9 else 1
	# ---------------------------------------------------------
	
	# fasilitas ditaruh di node Buildings supaya urutan gambarnya (y-sort) menyatu dengan bangunan
	var host: Node2D = world.buildings if facilities_sort_with_buildings else self
	node.position = host.to_local(world.cell_to_global(cell))
	host.add_child(node)
	facilities[cell] = {"kind": kind, "node": node, "prev": world.grid_data[cell]}
	match kind:
		Kind.BOR:
			# sumur bor: jadi sumber air tanah permanen
			world.set_base(cell, world.TileState.WATER)
			world.water.add_well(cell)
		Kind.BENDUNGAN:
			world.water.set_wall(cell, true)
		Kind.SPILLWAY:
			# saluran buang di tepi badan air: badan air itu tidak meluap saat hujan
			world.water.set_drain(cell, true)
			world.weather.apply_targets()
		Kind.KINCIR:
			world.water.watch_flux(cell, true)
	return true

## Timbun fasilitas: dibongkar, stok dikembalikan.
func remove(cell: Vector2i) -> void:
	var f: Dictionary = facilities[cell]
	f["node"].queue_free()
	facilities.erase(cell)
	stock[f["kind"]] += 1
	match f["kind"]:
		Kind.BOR:
			world.water.remove_well(cell)
			world.set_base(cell, f["prev"])
		Kind.BENDUNGAN:
			world.water.set_wall(cell, false)
		Kind.SPILLWAY:
			world.water.set_drain(cell, false)
			world.set_base(cell, f["prev"])
			world.weather.apply_targets()
		Kind.KINCIR:
			world.water.watch_flux(cell, false)

func is_well(cell: Vector2i) -> bool:
	return kind_at(cell) == Kind.BOR

# --- Kincir Air ---

## Putaran kincir di petak ini, 0..1 (1 = debit penuh).
func kincir_power(cell: Vector2i) -> float:
	return clampf(world.water.get_flux(cell) / kincir_full_flux, 0.0, 1.0)

## Total poin per detik dari semua kincir saat ini.
func kincir_points_rate() -> float:
	var total := 0.0
	for c in facilities:
		if facilities[c]["kind"] == Kind.KINCIR:
			total += kincir_power(c) * kincir_points_per_second
	return total

func _process(_delta: float) -> void:
	if world == null:
		return
	for c in facilities:
		if facilities[c]["kind"] == Kind.KINCIR:
			# berputar saat dialiri air ATAU saat sedang memompa.
			# Parameter kedua mengirimkan arah aliran dari water_sim.
			facilities[c]["node"].set_power(maxf(kincir_power(c), world.water.pump_power(c)), kincir_facing(c))

## Arah hadap kincir: bagian belakang menghadap petak tetangga yang paling tinggi
## (air dialirkan ke dataran tinggi). 0:TL 1:TR 2:BL 3:BR. Kalau tidak ada yang lebih tinggi, ikut arah aliran.
func kincir_facing(c: Vector2i) -> int:
	var sides := [TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE,
		TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE]
	var best := -1
	var best_h: int = world.get_elev(c)
	for i in 4:
		var n: Vector2i = world.world.get_neighbor_cell(c, sides[i])
		if world.grid_data.has(n) and world.get_elev(n) > best_h:
			best_h = world.get_elev(n)
			best = i
	if best < 0:
		return world.water.flow_dir(c)
	return 3 - best if kincir_face_invert else best
