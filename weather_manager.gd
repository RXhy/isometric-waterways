extends Node
## Siklus cuaca per hari: Cerah, Kemarau, Hujan lebat.
## - Kemarau: badan air alami yang kecil mengering (Mesin Bor tidak terpengaruh).
## - Hujan lebat: air meluap bertahap ke dataran rendah; semua bangunan tersiram.
##   Bendungan melindungi sekitarnya, Spillway membuat badan air di sebelahnya tidak meluap.
## Efek visual ada di node WeatherFX (world.tscn); script ini hanya menyalakan/mematikan.

enum Weather { CERAH, KEMARAU, HUJAN }
const NAMES := ["Cerah", "Kemarau", "Hujan lebat"]

@export var schedule: Array[Weather] = [
	Weather.CERAH, Weather.CERAH, Weather.KEMARAU, Weather.CERAH,
	Weather.HUJAN, Weather.KEMARAU, Weather.HUJAN, Weather.KEMARAU,
]  ## cuaca tiap hari (indeks 0 = hari 1); hari di luar daftar = Cerah
@export var drought_small_body: int = 15  ## badan air dengan petak kurang dari ini mengering total saat kemarau
@export var drought_shrink_large: bool = true  ## badan air besar menyusut: petak tepinya ikut kering
@export var flood_tick: float = 3.0       ## detik antar gelombang luapan banjir
@export var flood_reach: int = 3          ## banjir menjalar paling jauh sekian petak dari sumber air
@export var flood_max_elev: int = 1       ## banjir hanya menggenangi tingkat 0..nilai ini
@export var dam_radius: int = 2           ## jangkauan perlindungan Bendungan (petak)

var world
var current: int = Weather.CERAH
var dried: Dictionary = {}    # petak sumber air yang sedang kering
var flooded: Dictionary = {}  # petak tergenang -> jenis tile sebelumnya
var flood_depth: Dictionary = {}  # petak tergenang -> jarak dari sumber air
var _flood_timer: float = 0.0

func setup(w) -> void:
	world = w

func weather_for(day: int) -> int:
	return schedule[day - 1] if day >= 1 and day - 1 < schedule.size() else Weather.CERAH

func start_day(day: int) -> void:
	_end_weather()
	current = weather_for(day)
	if current == Weather.KEMARAU:
		_dry_sources()
	_flood_timer = 0.0
	world.facilities.on_forecast(weather_for(day + 1))
	_update_fx()
	world.update_water()

func is_flooded(cell: Vector2i) -> bool:
	return flooded.has(cell)

func is_dried(cell: Vector2i) -> bool:
	return dried.has(cell)

func _process(delta: float) -> void:
	if current != Weather.HUJAN or world == null or world.game_over:
		return
	_flood_timer += delta
	if _flood_timer >= flood_tick:
		_flood_timer = 0.0
		_spread_flood()

func _update_fx() -> void:
	world.fx_kemarau.visible = current == Weather.KEMARAU
	world.fx_hujan.visible = current == Weather.HUJAN

func _end_weather() -> void:
	for c in dried:
		world.change_tile_state(c, world.TileState.WATER)
	dried.clear()
	for c in flooded:
		world.change_tile_state(c, flooded[c])
	flooded.clear()
	flood_depth.clear()

# --- Kemarau ---

func _dry_sources() -> void:
	var seen := {}
	for y in range(world.active_area.position.y, world.active_area.end.y):
		for x in range(world.active_area.position.x, world.active_area.end.x):
			var start := Vector2i(x, y)
			if seen.has(start) or not world.is_natural_water(start) or world.facilities.is_well(start):
				continue
			var body := _collect_body(start, seen)
			var to_dry := []
			if body.size() < drought_small_body:
				to_dry = body
			elif drought_shrink_large:
				# tepi badan air (bersebelahan dengan daratan) ikut kering
				for c in body:
					for n in world.world.get_surrounding_cells(c):
						if world.grid_data.has(n) and world.grid_data[n] != world.TileState.WATER:
							to_dry.append(c)
							break
			for c in to_dry:
				dried[c] = true
				world.change_tile_state(c, world.TileState.CANAL)

## Badan air alami yang tersambung (lewat sisi, di dalam area).
func _collect_body(start: Vector2i, seen: Dictionary) -> Array:
	var body := [start]
	seen[start] = true
	var i := 0
	while i < body.size():
		for n in world.world.get_surrounding_cells(body[i]):
			if not seen.has(n) and world.is_in_active_area(n) and world.is_natural_water(n) \
					and not world.facilities.is_well(n):
				seen[n] = true
				body.append(n)
		i += 1
	return body

# --- Hujan lebat ---

func _spread_flood() -> void:
	var blocked := {}
	for s in world.facilities.spillway_cells():
		for n in world.world.get_surrounding_cells(s):
			if world.is_natural_water(n) and not blocked.has(n):
				for c in _collect_body(n, blocked):
					blocked[c] = true

	var area: Rect2i = world.active_area
	var new_cells := {}
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var c := Vector2i(x, y)
			if world.grid_data.get(c, -1) != world.TileState.WATER or blocked.has(c):
				continue
			var depth: int = flood_depth.get(c, 0)
			if depth >= flood_reach:
				continue
			for n in world.world.get_surrounding_cells(c):
				if _can_flood(n, c):
					new_cells[n] = mini(new_cells.get(n, 999), depth + 1)
	for n in new_cells:
		flooded[n] = world.grid_data[n]
		flood_depth[n] = new_cells[n]
		world.change_tile_state(n, world.TileState.WATER)
	if not new_cells.is_empty():
		world.update_water()

func _can_flood(n: Vector2i, from: Vector2i) -> bool:
	if flooded.has(n) or not world.is_in_active_area(n):
		return false
	var t: int = world.grid_data.get(n, -1)
	if t != world.TileState.DIRT and t != world.TileState.GRASS and t != world.TileState.ROAD:
		return false
	if world.facilities.has_facility(n):
		return false
	if world.get_elev(n) > world.get_elev(from) or world.get_elev(n) > flood_max_elev:
		return false
	return not world.facilities.dam_protects(n, dam_radius)
