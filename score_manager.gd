extends Node
## Sistem poin. Semua angka bisa diatur di Inspector node Score.
## Permainan berjalan sampai hari terakhir (45 hari). Di akhir, poin menentukan bintang:
##   >= target_points = 1 bintang (menang), >= star2_points = 2 bintang, >= star3_points = 3 bintang.
## Patokan dari simulasi bot (seed 507093, bot hanya menggali kanal, tanpa fasilitas):
## ~5400 poin di hari 39 lalu kalah kuota saat kemarau beruntun. Pemain yang memakai Mesin Bor
## & Kincir diperkirakan 7000-9000+. Sesuaikan lagi setelah ada log playtest manusia.
##
## Satu bangunan yang dialiri penuh sehari = 0.2 x 30 + 4 = 10 poin, jadi poin harian
## kira-kira 10 x jumlah bangunan yang terlayani.

@export var target_points: int = 5000  ## 1 bintang: batas menang
@export var star2_points: int = 7000   ## 2 bintang
@export var star3_points: int = 9000   ## 3 bintang
## true = permainan langsung selesai (menang) begitu 1 bintang tercapai (perilaku lama).
## false = tetap main sampai hari terakhir untuk mengejar bintang 2-3.
@export var end_on_target: bool = false
@export var supplied_per_second: float = 0.2  ## poin per detik untuk tiap bangunan yang teraliri
@export var day_bonus_per_building: int = 4   ## bonus akhir hari per bangunan yang DIALIRI pemain hari itu
## Bangunan baru dapat bonus akhir hari kalau teraliri kanal/sumber minimal selama porsi hari ini
## (0.5 = setengah hari). Hujan tidak dihitung, supaya bonus hanya datang dari kerja pemain.
@export_range(0.0, 1.0, 0.05) var day_bonus_min_supplied: float = 0.5
@export var bridge_bonus_per_day: int = 1     ## bonus akhir hari per jembatan yang BERFUNGSI (ada air mengalir di bawahnya)

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
	add("Jembatan", working_bridges() * bridge_bonus_per_day)

## Jembatan yang benar-benar dilewati air. Jembatan di jalan tanpa kanal tidak dihitung,
## supaya pemain tidak menimbun poin dengan memasang semua stok jembatan.
func working_bridges() -> int:
	var n := 0
	for c in world.roads.bridges:
		if world.water.is_wet(c):
			n += 1
	return n

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

## Batas poin tiap bintang [1, 2, 3].
func thresholds() -> Array[int]:
	return [target_points, star2_points, star3_points]

## Jumlah bintang yang sudah didapat (0-3).
func stars() -> int:
	var n := 0
	for t in thresholds():
		if total >= t:
			n += 1
	return n

## Batas bintang berikutnya yang sedang dikejar (bintang 3 kalau semua sudah tercapai).
func next_threshold() -> int:
	var th := thresholds()
	return th[mini(stars(), th.size() - 1)]

## Progres menuju bintang berikutnya (dipakai bar poin di HUD).
func progress() -> float:
	return clamp(total / float(next_threshold()), 0.0, 1.0)

func reached() -> bool:
	return total >= target_points
