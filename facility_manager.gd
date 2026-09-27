extends Node2D
## Fasilitas mitigasi: Mesin Bor, Bendungan, Spillway.
## Tampilan tiap fasilitas ada di scenes/*.tscn (diatur lewat Inspector).

enum Kind { BOR, BENDUNGAN, SPILLWAY }
const KIND_NAMES := ["Mesin Bor", "Bendungan", "Spillway"]

@export var bor_scene: PackedScene
@export var bendungan_scene: PackedScene
@export var spillway_scene: PackedScene
@export var start_stock: Array[int] = [1, 0, 0]  ## stok awal [Bor, Bendungan, Spillway]
@export var stock_per_forecast: int = 1          ## tambahan stok saat prakiraan cuaca buruk

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
		stock[Kind.BOR] += stock_per_forecast
	elif weather == world.weather.Weather.HUJAN:
		stock[Kind.BENDUNGAN] += stock_per_forecast
		stock[Kind.SPILLWAY] += stock_per_forecast

func _touches_natural_water(cell: Vector2i) -> bool:
	for n in world.world.get_surrounding_cells(cell):
		if world.is_natural_water(n):
			return true
	return false

func can_place(kind: int, cell: Vector2i) -> bool:
	if stock[kind] <= 0 or not world.is_buildable(cell) or world.buildings.has_building(cell):
		return false
	if kind == Kind.SPILLWAY and not _touches_natural_water(cell):
		return false
	return true

func place(kind: int, cell: Vector2i) -> bool:
	if not can_place(kind, cell):
		return false
	stock[kind] -= 1
	var scene: PackedScene = [bor_scene, bendungan_scene, spillway_scene][kind]
	var node: Node2D = scene.instantiate()
	node.position = to_local(world.cell_to_global(cell))
	add_child(node)
	facilities[cell] = {"kind": kind, "node": node, "prev": world.grid_data[cell]}
	if kind == Kind.BOR:
		# Sumur bor = sumber air tanah permanen di petak ini
		world.change_tile_state(cell, world.TileState.WATER)
	return true

## Timbun fasilitas: dibongkar, stok dikembalikan.
func remove(cell: Vector2i) -> void:
	var f: Dictionary = facilities[cell]
	f["node"].queue_free()
	facilities.erase(cell)
	stock[f["kind"]] += 1
	if f["kind"] == Kind.BOR:
		world.change_tile_state(cell, f["prev"])

func is_well(cell: Vector2i) -> bool:
	return kind_at(cell) == Kind.BOR

func dam_protects(cell: Vector2i, radius: int) -> bool:
	for c in facilities:
		if facilities[c]["kind"] == Kind.BENDUNGAN and world.iso_distance(c, cell) <= radius:
			return true
	return false

func spillway_cells() -> Array:
	var out := []
	for c in facilities:
		if facilities[c]["kind"] == Kind.SPILLWAY:
			out.append(c)
	return out
