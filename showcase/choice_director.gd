extends "res://showcase/loop_director.gd"
## SHOWCASE "Pilihan Juri v2" — satu kondisi awal, dua cabang aksi, hasil dari simulasi air.
## Kondisi: 3 rumah kehausan di dekat danau kecil, hari ini Cerah, BESOK KEMARAU. Stok Sumur Bor cuma 1.
##   Cabang A (Kanal): satu kanal panjang dari danau mengaliri ketiga rumah. Risiko: danau kecil
##                     menyusut saat kemarau, kanal ikut kering.
##   Cabang B (Bor)  : sumur bor di samping satu rumah (air tanah, tahan kemarau). Dua rumah lain dikorbankan.
## Hasil TIDAK dipaksa: rumah hancur/selamat murni dari simulasi. Peta, rencana, dan bagian awal
## identik di kedua cabang; hanya aksinya yang berbeda.
## Rekam: buka showcase/cuplikan_pilihan_A.tscn lalu _B.tscn, nyalakan Movie Maker, tekan F6.

@export_group("Pilihan Juri")
@export_enum("A_Kanal", "B_Bor") var branch: int = 0
@export var choice_hold: float = 1.5          ## tahan di kondisi awal setelah zoom (juri membaca keadaan)
@export var dig_drag_time: float = 1.8        ## lama drag Gali (pelan supaya terlihat)
@export var choice_action: float = 5.0        ## aksi + air mengalir / sumur bekerja
@export var action_speed: float = 6.0         ## kecepatan game saat air mengalir setelah aksi
@export var choice_drought: float = 8.0       ## kemarau berjalan (detik video)
@export var drought_game_speed: float = 20.0  ## kecepatan game saat kemarau (7 dtk video x 20 = ~4,5 hari game)
@export var drought_days: int = 6             ## jumlah hari kemarau berturut-turut di jadwal
@export var drought_ramp: float = 4.0         ## detik game tiap pagi sampai kemarau mencapai puncak (kecil = kolam cepat surut lagi)
@export var result_hold: float = 2.2          ## tahan gambar akhir
@export var choice_severity: float = 0.85     ## keparahan kemarau (0..1)
@export var thirsty_water: float = 0.36       ## cadangan awal 3 rumah kehausan (0..1)
@export var background_floor: float = 0.45    ## bangunan lain tidak dibiarkan hancur (fokus ke 3 rumah)
@export var thirsty_floor: float = 0.22       ## sebelum kemarau: 3 rumah boleh menipis sampai sini (tanda "!") tapi belum hancur
@export var drought_ramp_in: float = 1.5      ## detik video kecepatan kemarau naik bertahap (supaya keruntuhan pertama terlihat)
@export var drought_start_speed: float = 5.0  ## kecepatan game di awal kemarau
@export var weather_panel_x: float = 165.0    ## posisi x panel cuaca (piksel game)
@export var small_lake_max: int = 14          ## kanal cabang A harus dari danau kecil (petak); <15 = "badan air kecil" di game (lebih cepat menyusut)
@export var cluster_path_min: int = 6         ## panjang kanal dari kolam ke titik X (petak)
@export var cluster_path_max: int = 10
@export var cluster_path_goal: int = 8
@export var path_extra: int = 2               ## bangunan kehausan tambahan di samping jalur kanal (tidak terjangkau sumur)
@export var small_lake_min: int = 7           ## ...tapi cukup besar untuk mengaliri kanal panjang saat cuaca normal

var bor_side: Vector2i = Vector2i(-1, -1)
var lost_at := {}
var three_guard: Array = []   # rumah yang dijaga thirsty_floor sampai kemarau

func _process(delta: float) -> void:
	super._process(delta)
	if W == null:
		return
	for h in three_guard:
		var b = W.buildings.buildings.get(h)
		if b != null and b.state != 2 and b.water < b.max_water * thirsty_floor:
			b.water = b.max_water * thirsty_floor

func _enter_tree() -> void:
	super._enter_tree()
	flood_demo = false
	dig_source_max = small_lake_max
	dig_source_min = small_lake_min
	drought_victims = 0
	var wm = W.get_node("Weather")
	wm.schedule.clear()
	for d in range(1, W.target_days + 1):
		wm.schedule.append(1 if d > start_day and d <= start_day + drought_days else 0)
	wm.drought_severity_start = choice_severity
	wm.drought_severity_max = maxf(choice_severity, wm.drought_severity_max)
	wm.drought_ramp_time = drought_ramp

## Petak sumur bor di samping rumah ujung kanal (yang paling jauh dari danau).
func _pick_bor_side() -> void:
	if dig_target.x < 0:
		return
	var e: int = W.get_elev(dig_target)
	var best_d := -1
	for s in _sides(dig_target):
		if dig_path.has(s) or not _free_land(s) or W.get_elev(s) != e or _touches_water(s):
			continue
		var shared := false
		for n in _sides(s):
			if n != dig_target and (path_houses.has(n) or W.buildings.has_building(n) or plan_buildings.has(n)):
				shared = true  # sumur hanya boleh mengaliri SATU rumah (rumah target)
		if shared:
			continue
		var d: int = _water_dist(s)
		if d > best_d:
			best_d = d
			bor_side = s

## Drag yang mengikuti sumbu belokan jalur rencana (bukan ditebak dari arah drag).
func _drag_planned(tool: int, path: Array, dur: float) -> void:
	var a: Vector2i = path[0]
	var b: Vector2i = path[path.size() - 1]
	var axis := 0
	for ax in [0, 1]:
		if _drag_cells(a, b, ax) == path:
			axis = ax
	W.set_tool(tool)
	ptr_visible = true
	await _move_pointer(a, 0.35)
	ptr_pressed = true
	_ripple()
	W._start_drag(a, false)
	drag_on = true
	drag_axis_fixed = axis
	# kursor menelusuri jalur (lewat titik belok), bukan garis lurus
	var corner: int = path.size() - 1
	for i in range(1, path.size() - 1):
		var d1: Vector2i = path[i] - path[i - 1]
		var d2: Vector2i = path[i + 1] - path[i]
		if W.cell_to_global(path[i]) - W.cell_to_global(path[i - 1]) != W.cell_to_global(path[i + 1]) - W.cell_to_global(path[i]):
			corner = i
			break
	var seg1: float = dur * float(corner) / float(path.size() - 1)
	_set_pointer_target(W.cell_to_global(path[corner]), seg1)
	await _wait(seg1)
	_set_pointer_target(W.cell_to_global(b), dur - seg1)
	await _wait(dur - seg1 + 0.1)
	_apply_drag()
	drag_on = false
	W._finish_drag()
	ptr_pressed = false
	_ripple()
	await _wait(0.1)

## Rencana "klaster": 3 rumah kehausan mengelilingi satu titik X. Kanal (A) dari kolam kecil berakhir
## di X; sumur bor (B) dipasang tepat di X. Jadi kedua opsi menyasar 3 rumah yang sama.
func _plan_cluster() -> void:
	if dig_target.x >= 0:
		reserved.erase(dig_target)
		plan_buildings.erase(dig_target)
	for c in dig_path:
		reserved.erase(c)
	dig_path.clear()
	dig_target = Vector2i(-1, -1)
	path_houses.clear()
	var r: Rect2i = W.unlocked_area
	var sources: Array[Vector2i] = []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var t := Vector2i(x, y)
			if _free_land(t) and W.get_elev(t) <= 2 and _is_source(t) and _small_source(t):
				sources.append(t)
	var center: Vector2 = W.camera.position
	var best_score := INF
	var best_path: Array[Vector2i] = []
	var best_houses: Array[Vector2i] = []
	for t in sources:
		var e: int = W.get_elev(t)
		for yy in range(t.y - 18, t.y + 19):
			for xx in range(t.x - 9, t.x + 10):
				var X := Vector2i(xx, yy)
				if not _free_land(X) or W.get_elev(X) != e or _touches_water(X) or not W.in_diamond(X, W.unlock_r - 2):
					continue
				for axis in [0, 1]:
					var p := _drag_cells(t, X, axis)
					if p.size() < cluster_path_min or p.size() > cluster_path_max:
						continue
					var ok := true
					for i in p.size():
						var c: Vector2i = p[i]
						if not _free_land(c) or W.get_elev(c) != e or (i > 0 and _is_source(c)):
							ok = false
							break
					if not ok:
						continue
					var arrive: Vector2i = p[p.size() - 2]
					var houses: Array[Vector2i] = []
					for sd in _sides(X):
						if sd == arrive or p.has(sd):
							continue
						if not _free_land(sd) or W.get_elev(sd) != e or _touches_water(sd):
							continue
						var own: Array = []
						own.append_array(p)
						own.append_array(houses)
						own.append(sd)
						for s2 in _sides(X):
							own.append(s2)
						if _near_reserved(sd, own):
							continue
						houses.append(sd)
					if houses.size() < 3:
						continue
					var score: float = absf(float(p.size() - cluster_path_goal)) * 10.0 + W.cell_to_global(X).distance_to(center) * 0.01
					if score < best_score:
						best_score = score
						best_path = p
						best_houses = houses
	if best_path.is_empty():
		return
	dig_path = best_path
	bor_side = best_path[best_path.size() - 1]
	dig_target = best_houses[0]
	for i in range(1, best_houses.size()):
		path_houses.append(best_houses[i])
	for c in dig_path:
		reserved[c] = true
	for h in best_houses:
		reserved[h] = true
		plan_buildings.append(h)
	print("[SHOWCASE] klaster: titik X=%s jalur=%d rumah=%s" % [str(bor_side), dig_path.size(), str(best_houses)])
	# bangunan kehausan tambahan di samping jalur kanal, jauh dari titik X (tidak terjangkau sumur)
	var X: Vector2i = bor_side
	var near_x: Array = W.world.get_surrounding_cells(X)
	var added := 0
	for i in range(dig_path.size() - 3, 0, -1):
		if added >= path_extra:
			break
		var pc: Vector2i = dig_path[i]
		for sd in _sides(pc):
			if dig_path.has(sd) or near_x.has(sd) or sd == X or not _free_land(sd) or W.get_elev(sd) != W.get_elev(pc) or _touches_water(sd):
				continue
			var own: Array = []
			own.append_array(dig_path)
			own.append(sd)
			var near_bad := false
			for n in W.world.get_surrounding_cells(sd):
				if reserved.has(n) and not own.has(n):
					near_bad = true
			if near_bad:
				continue
			path_houses.append(sd)
			plan_buildings.append(sd)
			reserved[sd] = true
			added += 1
			break
	print("[SHOWCASE] klaster: bangunan di jalur kanal = %d" % added)

func _setup_weather_panel() -> void:
	var root: Control = W.hud.get_node("Root")
	for ch in root.get_children():
		if ch is CanvasItem:
			ch.visible = ch.name == "TopLeft"
	(root.get_node("TopLeft") as Control).position.x = weather_panel_x

func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_plan_scene()
	# hanya satu keputusan: tanpa bukit, tanpa kanal buntu, tanpa demo bor bawaan
	level_cells.clear()
	for c in fill_stub:
		reserved.erase(c)
	fill_stub.clear()
	if bor_cell.x >= 0:
		reserved.erase(bor_cell)
	bor_cell = Vector2i(-1, -1)
	bor_target = Vector2i(-1, -1)
	_plan_cluster()
	if dig_target.x < 0 or path_houses.size() < 2 or bor_side.x < 0:
		push_error("Pilihan Juri: rencana tidak lengkap (rumah=%s jalur=%d tambahan=%d sumur=%s). Ganti map_seed." % [
			str(dig_target), dig_path.size(), path_houses.size(), str(bor_side)])
		get_tree().quit()
		return
	reserved[bor_side] = true
	_plan_fillers()
	var three: Array[Vector2i] = []
	for h in _thirsty_all():
		three.append(h)
	# 3 rumah dikecualikan dari protect_floor umum; sebelum kemarau dijaga thirsty_floor (tidak hancur duluan)
	drought_list = three
	three_guard = three.duplicate()
	W.dig_pending[bor_side] = true  # sebelum bangunan muncul, supaya jalan tidak lewat petak sumur
	_build_scene()
	cam_base_pos = W.camera.position
	cam_base_zoom = W.camera.zoom.x
	W.elapsed = float(start_day - 1) * W.day_length + 0.05
	Engine.time_scale = warmup_speed
	await _wait(warmup_seconds)

	_after_warmup()
	_setup_weather_panel()
	for h in three:
		var b = W.buildings.buildings.get(h)
		if b != null:
			b.water = b.max_water * thirsty_water
	protect_floor = background_floor
	var szs: Array = []
	for n in W.world.get_surrounding_cells(dig_path[0]):
		if W.water.body_of.has(n):
			szs.append(_body_size.get(W.water.body_of[n], -1))
	print("[SHOWCASE] kolam sumber (petak): %s" % str(szs))
	print("[SHOWCASE] pilihan: jalur=%d rumah=%s sumur=%s bangunan=%d" % [
		dig_path.size(), str(three), str(bor_side), W.buildings.buildings.size()])

	# ---- KONDISI (identik di kedua cabang): seluruh peta -> zoom ke 3 rumah + danau
	var frame: Array = []
	frame.append_array(dig_path)
	frame.append_array(three)
	frame.append(bor_side)
	cam_goal_focus = cam_base_pos
	cam_focus = cam_base_pos
	cam_zoom_mul = observe_zoom
	cam_goal_zoom = observe_zoom
	cut_start = vt
	_mark("kondisi")
	Engine.time_scale = 1.0
	var t0: float = vt
	while vt - t0 < observe_hold:
		var k: float = (vt - t0) / maxf(0.01, observe_hold)
		cam_zoom_mul = lerpf(observe_zoom, observe_zoom * observe_drift, k)
		cam_goal_zoom = cam_zoom_mul
		await get_tree().process_frame
	var from_pos: Vector2 = cam_focus
	var from_zoom: float = cam_zoom_mul
	_focus_cells(frame, 1.0, loop_zoom)
	var to_pos: Vector2 = cam_goal_focus + focus_offset
	t0 = vt
	while vt - t0 < zoom_in_time:
		var u: float = clampf((vt - t0) / maxf(0.01, zoom_in_time), 0.0, 1.0)
		u = u * u * (3.0 - 2.0 * u)
		cam_zoom_mul = exp(lerpf(log(from_zoom), log(loop_zoom), u))
		cam_focus = from_pos.lerp(to_pos, u)
		cam_goal_zoom = cam_zoom_mul
		cam_goal_focus = cam_focus
		await get_tree().process_frame
	cam_zoom_mul = loop_zoom
	cam_goal_zoom = loop_zoom
	cam_focus = to_pos
	cam_goal_focus = to_pos
	await _wait(choice_hold)

	# ---- TITIK CABANG
	_mark("aksi")
	t0 = vt
	if branch == 0:
		await _drag_planned(GALI, dig_path, dig_drag_time)
	else:
		await _wait(0.3)
		var fm = W.facilities
		print("[SHOWCASE] cek sumur: stok=%d jalan=%s main=%s tipe=%d bangunan=%s" % [fm.stock[fm.Kind.BOR],
			str(W.roads.is_road(bor_side)), str(W.is_playable(bor_side)), int(W.grid_data.get(bor_side, -1)),
			str(W.buildings.has_building(bor_side))])
		await _click(BOR, bor_side, _act_place.bind(W.facilities.Kind.BOR, bor_side, "place_stone"))
	ptr_visible = false
	Engine.time_scale = action_speed
	await _wait(maxf(0.05, choice_action - (vt - t0)))

	for h in three:
		var b = W.buildings.buildings.get(h)
		if b != null:
			print("[SHOWCASE] sebelum kemarau %s: air=%.1f/%.0f teraliri=%s" % [str(h), b.water, b.max_water, str(b.has_water)])
	# ---- KEMARAU: kamera sedikit melebar supaya danau yang menyusut terlihat
	_new_day(start_day + 1)
	three_guard.clear()
	_mark("kemarau")
	_focus_cells(frame, 1.0, loop_zoom * 0.85)
	cam_goal_focus += focus_offset
	t0 = vt
	Engine.time_scale = drought_start_speed
	while vt - t0 < choice_drought:
		var ru: float = clampf((vt - t0) / maxf(0.01, drought_ramp_in), 0.0, 1.0)
		Engine.time_scale = lerpf(drought_start_speed, drought_game_speed, ru * ru * (3.0 - 2.0 * ru))
		for h in three:
			var b = W.buildings.buildings.get(h)
			if b != null and b.state == 2 and not lost_at.has(h):
				lost_at[h] = snappedf(vt - cut_start, 0.01)
				print("[SHOWCASE] rumah %s hancur t=%.2f" % [str(h), vt - cut_start])
		await get_tree().process_frame

	_mark("hasil")
	Engine.time_scale = 1.0
	# kamera kembali dekat ke 3 rumah supaya hasilnya jelas
	_focus_cells(frame, 1.0, loop_zoom)
	cam_goal_focus += focus_offset
	await _wait(result_hold)
	_mark("selesai")
	var alive := 0
	for h in three:
		var b = W.buildings.buildings.get(h)
		if b != null and b.state != 2:
			alive += 1
	print("[SHOWCASE] HASIL cabang %s: selamat %d dari %d" % [["A_Kanal", "B_Bor"][branch], alive, three.size()])
	_save_markers()
	await get_tree().process_frame
	get_tree().quit()
