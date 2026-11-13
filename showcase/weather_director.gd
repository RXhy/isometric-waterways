extends "res://showcase/showcase_director.gd"
## SHOWCASE "Cuaca" — video 5 detik per cuaca untuk slide pitching. Pilih cuaca di `weather_mode`:
##   Cerah      : air mengalir lancar, cadangan air bangunan terisi, kincir berputar.
##   Kemarau    : danau & kanal menyusut, cadangan air menipis, beberapa bangunan kekeringan lalu hancur.
##   Hujan lebat: danau meluap ke kanal & daratan, bangunan/ladang kebanjiran lalu hancur.
## Kota diisi 15-20 bangunan. HUD disembunyikan kecuali panel cuaca (kiri atas).
## Cara rekam: buka showcase/cuplikan_cuaca_<cuaca>.tscn, nyalakan Movie Maker, tekan F6.

enum Mode { CERAH, KEMARAU, HUJAN }

@export_group("Cuaca")
@export var weather_mode: Mode = Mode.KEMARAU
@export var clip_seconds: float = 5.0        ## panjang video (detik)
@export var view_zoom: float = 1.2           ## zoom kamera (1 = tampilan awal game)
@export var zoom_drift: float = 1.08         ## zoom pelan sepanjang video
@export var speed_cerah: float = 1.5         ## kecepatan game saat Cerah
@export var speed_kemarau: float = 5.5       ## kecepatan game saat Kemarau (jangan sampai melewati 1 hari = 30 dtk game)
@export var speed_hujan: float = 5.0         ## kecepatan game saat Hujan lebat
@export var victims: int = 4                 ## bangunan yang hancur (Kemarau / Hujan)
@export var victim_times: Array[float] = [2.2, 2.8, 3.4, 4.0]  ## detik video saat tiap korban hancur
@export var drought_ramp: float = 12.0       ## detik game sampai kemarau mencapai puncak (danau menyusut bertahap)
@export var flood_surge: float = 0.8         ## kenaikan air saat hujan lebat (makin besar makin banjir)
@export var cerah_refill: int = 4            ## Cerah: bangunan yang cadangan airnya terlihat terisi kembali
@export var kincir_count: int = 2            ## Cerah: kincir yang dipasang di kanal
@export var show_weather_panel: bool = true  ## tampilkan panel cuaca HUD (ikon + Hari)
@export var weather_panel_x: float = 148.0   ## posisi x panel cuaca (piksel game); 148 = tetap terlihat di potongan persegi

var focus_center: Vector2

func _enter_tree() -> void:
	super._enter_tree()
	use_lift = false
	use_spill = false
	W.damage_quota = 999  # video tidak boleh berakhir kalah
	drought_victims = victims if weather_mode == Mode.KEMARAU else 0
	flood_victims = victims if weather_mode == Mode.HUJAN else 0
	var wm = W.get_node("Weather")
	wm.schedule.clear()
	for d in range(1, W.target_days + 1):
		wm.schedule.append(int(weather_mode) if d == start_day + 1 else 0)
	wm.rain_surge = flood_surge
	wm.drought_ramp_time = drought_ramp

func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_plan_scene()
	_build_scene()
	cam_base_pos = W.camera.position
	cam_base_zoom = W.camera.zoom.x
	if weather_mode == Mode.CERAH:
		_place_kincir()
	W.elapsed = float(start_day - 1) * W.day_length + 0.05
	Engine.time_scale = warmup_speed
	await _wait(warmup_seconds)

	_after_warmup()
	_setup_hud()
	# kamera: pusat semua bangunan, zoom pelan
	var sum := Vector2.ZERO
	for c in W.buildings.buildings:
		sum += W.cell_to_global(c)
	focus_center = sum / float(maxi(1, W.buildings.buildings.size()))
	cam_goal_focus = focus_center
	cam_focus = focus_center
	cam_zoom_mul = view_zoom
	cam_goal_zoom = view_zoom
	ptr_visible = false
	print("[SHOWCASE] cuaca=%s bangunan=%d" % [Mode.keys()[weather_mode], W.buildings.buildings.size()])

	match weather_mode:
		Mode.CERAH:
			_prep_cerah()
		Mode.KEMARAU:
			_new_day(start_day + 1)
			_prep_kemarau()
		Mode.HUJAN:
			_new_day(start_day + 1)
			for c in W.buildings.buildings:
				W.buildings.buildings[c].flood_limit = 9999.0
			Engine.time_scale = speed_hujan
	cut_start = vt
	_mark(Mode.keys()[weather_mode].to_lower())

	var next_victim := 0
	while vt - cut_start < clip_seconds:
		var t: float = vt - cut_start
		var k: float = t / clip_seconds
		cam_goal_zoom = lerpf(view_zoom, view_zoom * zoom_drift, k)
		cam_zoom_mul = cam_goal_zoom
		if weather_mode == Mode.HUJAN and next_victim < mini(victims, victim_times.size()) \
				and t >= victim_times[next_victim]:
			if _flood_victim():
				_mark("hancur_banjir")
			next_victim += 1
		await get_tree().process_frame

	_mark("selesai")
	print("[SHOWCASE] hancur=%d" % W.buildings.destroyed_count)
	_save_markers()
	await get_tree().process_frame
	get_tree().quit()

## Hanya panel cuaca (ikon + Hari) yang tampil, digeser supaya ikut terlihat di potongan persegi.
func _setup_hud() -> void:
	var root: Control = W.hud.get_node("Root")
	if not show_weather_panel:
		root.visible = false
		return
	for ch in root.get_children():
		if ch is CanvasItem:
			ch.visible = ch.name == "TopLeft"
	var p: Control = root.get_node("TopLeft")
	p.position.x = weather_panel_x

func _place_kincir() -> void:
	var placed: Array[Vector2i] = []
	for i in kincir_count:
		var c: Vector2i = _find_cell(func(x: Vector2i) -> bool:
			if not _pred_kincir(x):
				return false
			for o in placed:
				if W.iso_distance(x, o) < 4:
					return false
			return true, true)
		if c.x < 0:
			break
		_act_place(W.facilities.Kind.KINCIR, c, "place_wood")
		placed.append(c)

func _sorted_by_center(list: Array) -> Array:
	var out: Array = list.duplicate()
	out.sort_custom(func(a, b) -> bool:
		return W.cell_to_global(a).distance_to(focus_center) < W.cell_to_global(b).distance_to(focus_center))
	return out

func _prep_cerah() -> void:
	Engine.time_scale = speed_cerah
	# beberapa bangunan dekat tengah mulai setengah kosong lalu terisi kembali (air mengalir lancar)
	var cand: Array = []
	for c in connected:
		cand.append(c)
	var n := 0
	for c in _sorted_by_center(cand):
		if n >= cerah_refill:
			break
		var b = W.buildings.buildings.get(c)
		if b != null:
			b.water = b.max_water * 0.45
			n += 1

func _prep_kemarau() -> void:
	Engine.time_scale = speed_kemarau
	protect_floor = 0.12  # bukan korban: menipis sampai cincin merah tapi tidak hancur
	for c in W.buildings.buildings:
		var b = W.buildings.buildings[c]
		b.water = b.max_water * 0.6
	# korban kemarau habis airnya bergiliran pada victim_times (air turun 1/detik game)
	var list: Array = _sorted_by_center(drought_list)
	for i in list.size():
		var b = W.buildings.buildings.get(list[i])
		if b == null:
			continue
		var tv: float = victim_times[mini(i, victim_times.size() - 1)]
		b.water = minf(b.max_water, tv * speed_kemarau)

## Hujan: bangunan tergenang paling lama (dekat tengah layar) hancur karena banjir.
func _flood_victim() -> bool:
	var best = null
	var best_score := -INF
	for c in W.buildings.buildings:
		var b = W.buildings.buildings[c]
		if b.state == 2 or b.flood_time <= 0.0:
			continue
		var s: float = b.flood_time - W.cell_to_global(c).distance_to(focus_center) * 0.02
		if s > best_score:
			best_score = s
			best = b
	if best == null:
		push_warning("Showcase cuaca: belum ada bangunan tergenang untuk dihancurkan")
		return false
	best.flood_limit = best.flood_time  # hancur pada tick berikutnya
	return true
