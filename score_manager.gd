extends Node
## Sistem poin (versi awal). Semua angka bisa diatur di Inspector node Score.
## Menang = total poin mencapai target sebelum hari terakhir berakhir.

@export var target_points: int = 600
@export var supplied_per_second: float = 0.5  ## poin per detik untuk tiap bangunan yang teraliri
@export var day_bonus_per_building: int = 10  ## bonus akhir hari per bangunan yang DIALIRI pemain hari itu
## Bangunan baru dapat bonus akhir hari kalau teraliri kanal/sumber minimal selama porsi hari ini
## (0.5 = setengah hari). Hujan tidak dihitung, supaya bonus hanya datang dari kerja pemain.
@export_range(0.0, 1.0, 0.05) var day_bonus_min_supplied: float = 0.5
@export var bridge_bonus_per_day: int = 3     ## bonus akhir hari per jembatan terpasang

const SOURCES := ["Bangunan teraliri", "Kincir air", "Bonus akhir hari", "Jembatan"]

var world
var by_source: Dictionary = {}  # sumber -> poin
var total: float = 0.0
var today: float = 0.0
var supplied_time: Dictionary = {}  # petak bangunan -> detik teraliri hari ini (tanpa hujan)

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
			supplied_time[c] = supplied_time.get(c, 0.0) + delta
	if n > 0:
		add("Bangunan teraliri", n * supplied_per_second * delta)
	var k: float = world.facilities.kincir_points_rate()
	if k > 0.0:
		add("Kincir air", k * delta)

## Dipanggil di akhir setiap hari.
func end_of_day() -> void:
	add("Bonus akhir hari", bonus_buildings() * day_bonus_per_building)
	add("Jembatan", world.roads.bridges.size() * bridge_bonus_per_day)

## Jumlah bangunan hidup yang cukup lama dialiri hari ini (berhak bonus akhir hari).
func bonus_buildings() -> int:
	var need: float = day_bonus_min_supplied * world.day_length
	var n := 0
	for c in world.buildings.buildings:
		var b = world.buildings.buildings[c]
		if b.state != b.State.HANCUR and supplied_time.get(c, 0.0) >= need:
			n += 1
	return n

func start_of_day() -> void:
	today = 0.0
	supplied_time.clear()

func progress() -> float:
	return clamp(total / float(target_points), 0.0, 1.0)

func reached() -> bool:
	return total >= target_points
