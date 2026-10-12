extends Node2D
## Spawning dinamis bangunan + cek pasokan air tiap bangunan.

signal building_spawned(building)
signal building_destroyed(building)

const Building = preload("res://building.gd")

@export var building_scene: PackedScene  ## scenes/building.tscn

@export var buildings_first_day: int = 2          ## jumlah bangunan yang muncul di awal hari 1
## Laju bangunan baru per hari (setelah hari 1), naik pelan dari awal ke akhir permainan.
## Pecahan dikumpulkan: 0.6/hari = rata-rata 3 bangunan tiap 5 hari. Total 45 hari ~ 40 bangunan.
@export var spawn_rate_start: float = 0.6
@export var spawn_rate_end: float = 1.2
@export var min_building_spacing: int = 3       ## jarak minimal antar bangunan (tile)
@export var min_water_distance: int = 3         ## minimal panjang kanal yang perlu digali
@export var max_water_distance_start: int = 6   ## maksimal panjang kanal di awal
@export var max_water_distance_end: int = 12    ## maksimal panjang kanal di akhir
@export_range(0.0, 1.0) var farm_chance: float = 0.35

var world  # world.gd (root scene)
var buildings: Dictionary = {}  # Vector2i -> Building
var destroyed_count: int = 0
var day: int = 1
var running: bool = false
var _spawn_acc: float = 0.0  # sisa pecahan laju spawn

func setup(w) -> void:
	world = w
	running = true

func stop() -> void:
	running = false

## 0 di hari pertama, 1 di hari terakhir. Dipakai untuk menaikkan kesulitan.
func progress() -> float:
	return clamp(float(day - 1) / max(1.0, float(world.target_days - 1)), 0.0, 1.0)

## Laju spawn (bangunan/hari) di hari d.
func spawn_rate(d: int) -> float:
	var p: float = clamp(float(d - 1) / max(1.0, float(world.target_days - 1)), 0.0, 1.0)
	return lerp(spawn_rate_start, spawn_rate_end, p)

## Jumlah bangunan BARU yang muncul di awal hari d.
func buildings_for_day(d: int) -> int:
	if d <= 1:
		return buildings_first_day
	_spawn_acc += spawn_rate(d)
	var n := int(_spawn_acc)
	_spawn_acc -= n
	return n

## Area muncul bangunan = lahan yang sudah terbuka (melebar bertahap, lihat Node2D grup "Lahan & ekspansi").
func current_spawn_area() -> Rect2i:
	return world.unlocked_area

## Dipanggil world.gd setiap awal hari (termasuk hari 1).
func start_day(d: int) -> void:
	if not running:
		return
	day = d
	var n := buildings_for_day(d)
	var spawned := 0
	for i in n:
		if try_spawn():
			spawned += 1
	if spawned < n:
		push_warning("Hari %d: hanya %d dari %d bangunan dapat tempat." % [d, spawned, n])
		world.balance_log.count("gagal_spawn", n - spawned)

func _process(delta: float) -> void:
	if not running:
		return

	for cell in buildings:
		var b = buildings[cell]
		var supplied: bool = world.is_cell_supplied(cell) or world.weather.current == world.weather.Weather.HUJAN
		if b.tick(delta, supplied, world.water.is_flooded(cell)):
			destroyed_count += 1
			building_destroyed.emit(b)
			if not running:
				return

func has_building(cell: Vector2i) -> bool:
	return buildings.has(cell)

func try_spawn() -> bool:
	var area: Rect2i = current_spawn_area()  # area inti yang melebar seiring hari, tidak di bawah UI
	var max_dist := int(round(lerp(float(max_water_distance_start), float(max_water_distance_end), progress())))
	for i in 150:
		var cell := Vector2i(
			randi_range(area.position.x + 1, area.end.x - 2),
			randi_range(area.position.y + 2, area.end.y - 3))
		if buildings.has(cell) or not world.is_buildable(cell) or not world.is_playable(cell):
			continue
		if _too_close_to_building(cell):
			continue
		var d: int = world.water_distance(cell, max_dist)
		if d == -1 or d < min_water_distance:
			continue
		_spawn(cell, Building.Type.LADANG if randf() < farm_chance else Building.Type.RUMAH)
		return true
	return false

func _too_close_to_building(cell: Vector2i) -> bool:
	for other in buildings:
		if world.iso_distance(cell, other) < min_building_spacing:
			return true
	return false

func _spawn(cell: Vector2i, type: int) -> void:
	var b = building_scene.instantiate()
	b.setup(cell, type)
	b.position = to_local(world.cell_to_global(cell))
	add_child(b)
	buildings[cell] = b
	# ujung kanal/jalan di sebelahnya ikut berbelok ke bangunan baru
	world.water.refresh_cell(cell)
	building_spawned.emit(b)

func count_state(state: int) -> int:
	var n := 0
	for cell in buildings:
		if buildings[cell].state == state:
			n += 1
	return n
