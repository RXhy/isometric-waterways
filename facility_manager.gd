extends Node2D
## Fasilitas mitigasi: Mesin Bor, Bendungan, Spillway.
## Tampilan tiap fasilitas ada di scenes/*.tscn (diatur lewat Inspector).

enum Kind { BOR, BENDUNGAN, SPILLWAY }
const KIND_NAMES := ["Mesin Bor", "Bendungan", "Spillway"]

@export var bor_scene: PackedScene
@export var bendungan_scene: PackedScene
@export var spillway_scene: PackedScene
@export var start_stock: Array[int] = [1, 0, 0]  ## stok awal [Bor, Bendungan, Spillway]
@export var stock_per_forecast: Array[int] = [1, 3, 1]  ## tambahan stok [Bor, Bendungan, Spillway] saat prakiraan cuaca buruk

var world
var stock: Array[int] = [0, 0, 0]
var facilities: Dictionary = {}  # Vector2i -> {"kind": int, "node": Node2D}

func setup(w) -> void:
	world = w
	stock = start_stock.duplicate()

func has_facility(cell: Vector2i) -> bool:
	return facilities.has(cell)

func kind_at(cell: Vector2i) -> int:
	return facilities[cell]["kind"] if facilities.has(cell) else -1

## Dipanggil saat prakiraan cuaca besok diumumkan.
func on_forecast(weather: int) -> void:
	if weather == world.weather.Weather.KEMARAU:
		stock[Kind.BOR] += stock_per_forecast[Kind.BOR]
	elif weather == world.weather.Weather.HUJAN:
		stock[Kind.BENDUNGAN] += stock_per_forecast[Kind.BENDUNGAN]
		stock[Kind.SPILLWAY] += stock_per_forecast[Kind.SPILLWAY]

## Alasan fasilitas tidak bisa dipasang di petak ini ("" kalau bisa). Dipakai tooltip HUD.
func why_not(kind: int, cell: Vector2i) -> String:
	if stock[kind] <= 0:
		return "Stok %s habis" % KIND_NAMES[kind]
	if facilities.has(cell) or world.buildings.has_building(cell):
		return "Petak sudah terisi"
	if world.roads.is_road(cell):
		return "Tidak bisa di jalan"
	var t: int = world.grid_data.get(cell, -1)
	var land: bool = t == world.TileState.DIRT or t == world.TileState.GRASS
	match kind:
		Kind.BENDUNGAN:
			if not (land or world.dug.has(cell)):
				return "Hanya di tanah atau melintang kanal"
		Kind.SPILLWAY:
			if not land:
				return "Hanya di tanah"
			if world.water.bodies_touching(cell).is_empty():
				return "Harus di tepi sumber air"
		_:
			if not land:
				return "Hanya di tanah"
	return ""

func can_place(kind: int, cell: Vector2i) -> bool:
	if stock[kind] <= 0 or facilities.has(cell) or world.buildings.has_building(cell):
		return false
	if not world.is_in_active_area(cell) or world.roads.is_road(cell):
		return false
	var t: int = world.grid_data.get(cell, -1)
	var land: bool = t == world.TileState.DIRT or t == world.TileState.GRASS
	match kind:
		Kind.BENDUNGAN:
			# tanggul/bendungan boleh di tanah atau melintang di kanal galian
			return land or world.dug.has(cell)
		Kind.SPILLWAY:
			return land and not world.water.bodies_touching(cell).is_empty()
	return land

func place(kind: int, cell: Vector2i) -> bool:
	if not can_place(kind, cell):
		return false
	stock[kind] -= 1
	var scene: PackedScene = [bor_scene, bendungan_scene, spillway_scene][kind]
	var node: Node2D = scene.instantiate()
	node.position = to_local(world.cell_to_global(cell))
	add_child(node)
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
			world.set_base(cell, world.TileState.CANAL)
			world.water.set_drain(cell, true)
			world.weather.apply_targets()
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
			world.water.clear_water(cell)
			world.weather.apply_targets()

func is_well(cell: Vector2i) -> bool:
	return kind_at(cell) == Kind.BOR
