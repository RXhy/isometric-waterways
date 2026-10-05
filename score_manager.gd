extends Node
## Sistem poin (versi awal). Semua angka bisa diatur di Inspector node Score.
## Menang = total poin mencapai target sebelum hari terakhir berakhir.

@export var target_points: int = 600
@export var supplied_per_second: float = 0.5  ## poin per detik untuk tiap bangunan yang teraliri
@export var day_bonus_per_building: int = 10  ## bonus akhir hari per bangunan yang masih berdiri
@export var bridge_bonus_per_day: int = 3     ## bonus akhir hari per jembatan terpasang

const SOURCES := ["Bangunan teraliri", "Kincir air", "Bonus akhir hari", "Jembatan"]

var world
var by_source: Dictionary = {}  # sumber -> poin
var total: float = 0.0
var today: float = 0.0

func setup(w) -> void:
	world = w
	for s in SOURCES:
		by_source[s] = 0.0

func add(source: String, amount: float) -> void:
	by_source[source] = by_source.get(source, 0.0) + amount
	total += amount
	today += amount

func _process(delta: float) -> void:
	if world == null or world.game_over or world.demo_mode:
		return
	var n := 0
	for c in world.buildings.buildings:
		var b = world.buildings.buildings[c]
		if b.state != b.State.HANCUR and world.is_cell_supplied(c):
			n += 1
	if n > 0:
		add("Bangunan teraliri", n * supplied_per_second * delta)
	var k: float = world.facilities.kincir_points_rate()
	if k > 0.0:
		add("Kincir air", k * delta)

## Dipanggil di akhir setiap hari.
func end_of_day() -> void:
	var alive: int = world.buildings.buildings.size() - world.buildings.destroyed_count
	add("Bonus akhir hari", alive * day_bonus_per_building)
	add("Jembatan", world.roads.bridges.size() * bridge_bonus_per_day)

func start_of_day() -> void:
	today = 0.0

func progress() -> float:
	return clamp(total / float(target_points), 0.0, 1.0)

func reached() -> bool:
	return total >= target_points
