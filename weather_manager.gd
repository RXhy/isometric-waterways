extends Node
## Siklus cuaca per hari: Cerah, Kemarau, Hujan lebat.
## Cuaca tidak mengubah petak secara langsung; ia hanya mengatur target sumber air
## di WaterSim. Kering dan banjir lalu muncul sendiri dari simulasi.
## - Kemarau: sumber air menyusut PELAN-PELAN sepanjang hari (bukan langsung kering).
##            Tiap kemarau berikutnya lebih parah dari sebelumnya (tingkat 1, 2, 3, ...).
##            Badan air kecil menyusut lebih cepat. Sumur bor tidak terpengaruh.
##            Semua angkanya ada di Inspector node Weather, grup "Drought".
## - Hujan lebat: badan air naik melewati tepinya dan meluap ke daratan yang lebih rendah;
##            semua bangunan tersiram. Badan air yang punya Spillway tidak dinaikkan.
## Efek visual ada di node WeatherFX (world.tscn); ikon cuaca diatur di Inspector.

enum Weather { CERAH, KEMARAU, HUJAN }
const NAMES := ["Cloudy", "Drought", "Heavy Rain"]

## Jadwal cuaca dibuat otomatis untuk semua hari (lihat grup "Jadwal otomatis").
## Matikan kalau ingin memakai daftar `schedule` di bawah secara manual.
@export var auto_schedule: bool = true
@export var schedule: Array[Weather] = [
	Weather.CERAH, Weather.CERAH, Weather.CERAH, Weather.CERAH,
	Weather.CERAH, Weather.CERAH, Weather.CERAH, Weather.CERAH,
]  ## cuaca tiap hari (indeks 0 = hari 1); hari di luar daftar = Cerah
@export var icons: Array[Texture2D] = []    ## ikon [Cerah, Kemarau, Hujan lebat] untuk HUD
@export var rain_surge: float = 0.35        ## kenaikan target sumber saat hujan (di atas tepi = meluap)

@export_group("Drought")
## Seberapa banyak sumber air menyusut di kemarau PERTAMA (0 = tidak menyusut, 1 = kering total).
@export_range(0.0, 1.0, 0.05) var drought_severity_start: float = 0.3
## Tambahan keparahan tiap kemarau berikutnya (kemarau ke-2 = start + step, ke-3 = start + 2*step, ...).
@export_range(0.0, 0.5, 0.01) var drought_severity_step: float = 0.05
## Batas keparahan paling tinggi.
@export_range(0.0, 1.0, 0.05) var drought_severity_max: float = 0.8
## Detik sejak awal hari sampai kemarau mencapai puncaknya (air menyusut bertahap selama ini).
@export var drought_ramp_time: float = 20.0
## Badan air lebih kecil dari ini (jumlah petak) dihitung "kecil" dan menyusut lebih parah.
@export var drought_small_body: int = 15
## Pengali keparahan untuk badan air kecil (1.5 = 50% lebih parah).
@export var drought_small_mult: float = 1.5

@export_group("Jadwal otomatis")
## Hari-hari awal selalu Cerah supaya pemain sempat belajar menggali kanal.
@export var calm_days: int = 3
## Peluang kemarau / hujan lebat per hari, naik pelan dari awal ke akhir permainan.
@export_range(0.0, 1.0, 0.01) var drought_chance_start: float = 0.15
@export_range(0.0, 1.0, 0.01) var drought_chance_end: float = 0.35
@export_range(0.0, 1.0, 0.01) var rain_chance_start: float = 0.12
@export_range(0.0, 1.0, 0.01) var rain_chance_end: float = 0.22
## Cuaca ekstrem yang sama paling banyak sekian hari berturut-turut.
@export var max_streak: int = 2

var world
var current: int = Weather.CERAH
var _day_start: float = 0.0
var _t: float = 0.0

func setup(w) -> void:
	world = w
	if auto_schedule:
		schedule = generate_schedule(world.target_days, world.map_seed)

## Jadwal cuaca acak tapi tetap: seed peta yang sama = jadwal yang sama (bisa diulang saat balancing).
## Kurva: tenang di awal, makin sering kemarau/hujan menjelang akhir (seperti Mini Motorways).
func generate_schedule(days: int, seed_value: int) -> Array[Weather]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_value) ^ 0x5eed
	var out: Array[Weather] = []
	var streak := 0
	for d in range(1, days + 1):
		var w: Weather = Weather.CERAH
		if d > calm_days:
			var p: float = clampf(float(d - calm_days - 1) / maxf(1.0, float(days - calm_days - 1)), 0.0, 1.0)
			var pk: float = lerpf(drought_chance_start, drought_chance_end, p)
			var ph: float = lerpf(rain_chance_start, rain_chance_end, p)
			var r := rng.randf()
			if r < pk:
				w = Weather.KEMARAU
			elif r < pk + ph:
				w = Weather.HUJAN
			if w != Weather.CERAH and not out.is_empty() and out[-1] == w and streak >= max_streak:
				w = Weather.CERAH
		streak = streak + 1 if (not out.is_empty() and out[-1] == w) else 1
		out.append(w)
	return out

func weather_for(day: int) -> int:
	return schedule[day - 1] if day >= 1 and day - 1 < schedule.size() else Weather.CERAH

func icon_for(w: int) -> Texture2D:
	return icons[w] if w < icons.size() else null

## Kemarau ke berapa hari ini (1 = kemarau pertama). 0 kalau hari itu bukan kemarau.
func drought_index(day: int) -> int:
	if weather_for(day) != Weather.KEMARAU:
		return 0
	var n := 0
	for d in range(1, day + 1):
		if weather_for(d) == Weather.KEMARAU:
			n += 1
	return n

## Keparahan puncak kemarau di hari itu (0..1).
func drought_severity(day: int) -> float:
	var n := drought_index(day)
	if n == 0:
		return 0.0
	return minf(drought_severity_max, drought_severity_start + drought_severity_step * (n - 1))

## Teks untuk tooltip prakiraan cuaca di HUD.
func describe(day: int) -> String:
	var w := weather_for(day)
	if w == Weather.KEMARAU:
		return "%s (level %d: water sources -%d%%)" % [NAMES[w], drought_index(day), int(drought_severity(day) * 100.0)]
	return NAMES[w]

## 0..1: seberapa jauh kemarau hari ini sudah berjalan menuju puncaknya.
func drought_progress() -> float:
	if drought_ramp_time <= 0.0:
		return 1.0
	return clampf((world.elapsed - _day_start) / drought_ramp_time, 0.0, 1.0)

func _process(delta: float) -> void:
	if world == null or current != Weather.KEMARAU:
		return
	_t += delta
	if _t >= 0.25:  # perbarui target sumber 4x per detik selama kemarau berjalan
		_t = 0.0
		apply_targets()

func start_day(day: int) -> void:
	current = weather_for(day)
	_day_start = world.elapsed
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
				var sev := drought_severity(world.current_day())
				if sim.body_size[id] < drought_small_body:
					sev = minf(1.0, sev * drought_small_mult)
				t = normal * (1.0 - sev * drought_progress())
			Weather.HUJAN:
				t = normal if spill_bodies.has(id) else normal + rain_surge
		sim.body_target[id] = t
