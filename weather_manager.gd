extends Node
## Siklus cuaca per hari: Cerah, Kemarau, Hujan lebat.
## Cuaca tidak mengubah petak secara langsung; ia hanya mengatur target sumber air
## di WaterSim. Kering dan banjir lalu muncul sendiri dari simulasi.
## - Kemarau: badan air kecil berhenti mengalir (target 0), badan air besar menyusut.
##            Sumur bor tidak terpengaruh.
## - Hujan lebat: badan air naik melewati tepinya dan meluap ke daratan yang lebih rendah;
##            semua bangunan tersiram. Badan air yang punya Spillway tidak dinaikkan.
## Efek visual ada di node WeatherFX (world.tscn); ikon cuaca diatur di Inspector.

enum Weather { CERAH, KEMARAU, HUJAN }
const NAMES := ["Cerah", "Kemarau", "Hujan lebat"]

@export var schedule: Array[Weather] = [
	Weather.CERAH, Weather.CERAH, Weather.CERAH, Weather.CERAH,
	Weather.CERAH, Weather.CERAH, Weather.CERAH, Weather.CERAH,
]  ## cuaca tiap hari (indeks 0 = hari 1); hari di luar daftar = Cerah
@export var icons: Array[Texture2D] = []    ## ikon [Cerah, Kemarau, Hujan lebat] untuk HUD
@export var drought_small_body: int = 15    ## badan air lebih kecil dari ini berhenti mengalir saat kemarau
@export var drought_level: float = 0.25     ## target sumber badan air besar saat kemarau (normal = 0.5)
@export var rain_surge: float = 0.35        ## kenaikan target sumber saat hujan (di atas tepi = meluap)

var world
var current: int = Weather.CERAH

func setup(w) -> void:
	world = w

func weather_for(day: int) -> int:
	return schedule[day - 1] if day >= 1 and day - 1 < schedule.size() else Weather.CERAH

func icon_for(w: int) -> Texture2D:
	return icons[w] if w < icons.size() else null

func start_day(day: int) -> void:
	current = weather_for(day)
	apply_targets()
	world.facilities.on_forecast(weather_for(day + 1))
	world.fx_kemarau.visible = current == Weather.KEMARAU
	world.fx_hujan.visible = current == Weather.HUJAN

## Hitung ulang target semua sumber alami. Dipanggil juga saat Spillway dipasang/dibongkar.
func apply_targets() -> void:
	var sim = world.water
	var normal: float = sim.channel_depth
	var spill_bodies := {}
	for c in sim.drains:
		for id in sim.bodies_touching(c):
			spill_bodies[id] = true
	for id in sim.body_size:
		var t := normal
		match current:
			Weather.KEMARAU:
				t = 0.0 if sim.body_size[id] < drought_small_body else drought_level
			Weather.HUJAN:
				t = normal if spill_bodies.has(id) else normal + rain_surge
		sim.body_target[id] = t
