extends "res://showcase/showcase_director.gd"
## SHOWCASE "Game Loop" — video ~10 detik untuk slide THE CORE GAMEPLAY.
## Kota ramai, kamera dekat, HUD disembunyikan (video dipotong persegi untuk slide):
##   Level  : ratakan bukit yang menghalangi jalur kanal (air tidak bisa naik)
##   Dig    : gali kanal panjang dari danau yang melewati beberapa bangunan kehausan sekaligus
##   Fill   : timbun kanal bocor yang membanjiri sebuah rumah, banjirnya berhenti
##   Refill : kamera melebar, cadangan air semua bangunan terisi kembali
## Cara rekam sama: buka showcase/cuplikan_loop.tscn, nyalakan Movie Maker, tekan F6.

@export_group("Game Loop (detik video)")
@export var observe_hold: float = 1.5        ## Observe: tampilan seluruh peta (bangunan kehausan & rumah kebanjiran terlihat)
@export var observe_zoom: float = 0.62       ## zoom tampilan seluruh peta (1 = tampilan awal game)
@export var observe_drift: float = 1.1       ## zoom pelan selama Observe (kamera tidak diam total)
@export var zoom_in_time: float = 1.2        ## waktu kamera masuk dari seluruh peta ke area aksi
@export var loop_level: float = 1.5          ## Level: turunkan bukit
@export var loop_dig: float = 2.5            ## Dig: gali kanal panjang
@export var loop_fill: float = 2.0           ## Fill: timbun kanal bocor
@export var loop_refill: float = 2.8         ## semua cadangan air terisi kembali
@export var loop_zoom: float = 2.2           ## zoom kamera (1 = tampilan awal game)
@export var refill_zoom: float = 2.0         ## zoom tampilan akhir (semua bangunan yang dibantu)
@export var loop_start_water: float = 0.35   ## cadangan air awal bangunan kehausan (0..1)
@export var focus_offset: Vector2 = Vector2(0, -14)  ## geser titik fokus kamera (piksel game); negatif = lebih ke atas
@export var hide_hud: bool = true            ## sembunyikan HUD (video untuk slide)
@export var fill_pan_wait: float = 0.6       ## waktu kamera bergeser ke kanal bocor sebelum Fill (kalau jauh)
@export var loop_dig_len: int = 9            ## panjang jalur Gali yang dicari (petak)
@export var loop_dig_max: int = 11           ## panjang maksimal jalur Gali
@export var thirsty_extra: int = 2           ## bangunan kehausan tambahan di sepanjang jalur Gali
@export var filler_buildings: int = 5        ## bangunan tambahan (sudah teraliri) di sekitar area aksi supaya kota terlihat ramai
@export var filler_radius: float = 120.0     ## jarak maksimal bangunan tambahan dari pusat aksi (piksel game)
@export var flood_demo: bool = true          ## Fill menutup kanal bocor yang membanjiri rumah
@export var flood_drain: float = 0.9         ## detik video genangan surut setelah kanal bocor ditimbun

var path_houses: Array[Vector2i] = []
var flood_house: Vector2i = Vector2i(-1, -1)
var flood_yard: Array[Vector2i] = []

func _enter_tree() -> void:
	super._enter_tree()
	use_lift = false
	use_spill = false
	fill_near_dig = true
	dig_len_goal = loop_dig_len
	dig_len_max = loop_dig_max

func _process(delta: float) -> void:
	super._process(delta)
	# rumah banjir: tampil terancam (cincin merah) tapi tidak menumpuk waktu banjir, jadi cepat pulih setelah Fill
	if flood_house.x >= 0 and W != null and W.buildings.buildings.has(flood_house):
		var b = W.buildings.buildings[flood_house]
		b.flood_time = minf(b.flood_time, 0.9)

func _dig_anchor() -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for c in dig_path:
		sum += W.cell_to_global(c)
		n += 1
	if dig_target.x >= 0:
		sum += W.cell_to_global(dig_target)
		n += 1
	return sum / float(maxi(1, n))

func _thirsty_all() -> Array:
	var out: Array = []
	if dig_target.x >= 0:
		out.append(dig_target)
	out.append_array(path_houses)
	return out

func _frame_cells() -> Array:
	var cells: Array = []
	cells.append_array(dig_path)
	cells.append_array(_thirsty_all())
	# kanal bocor ikut dibingkai hanya kalau dekat; kalau jauh, kamera bergeser saat segmen Fill
	if not fill_stub.is_empty() and not _fill_needs_pan(cells):
		cells.append_array(fill_stub)
		if flood_house.x >= 0:
			cells.append(flood_house)
	return cells

func _fill_needs_pan(cells: Array) -> bool:
	if fill_stub.is_empty() or cells.is_empty():
		return false
	var a := Vector2.ZERO
	for c in cells:
		a += W.cell_to_global(c)
	a /= float(cells.size())
	var b: Vector2 = W.cell_to_global(fill_stub[fill_stub.size() / 2])
	return a.distance_to(b) > 230.0 / maxf(1.0, loop_zoom)

## Bangunan kehausan tambahan tepat di samping jalur Gali (bagian akhir, setelah bukit).
func _plan_path_houses() -> void:
	if dig_target.x < 0:
		return
	for i in range(dig_path.size() - 2, 3, -1):
		if path_houses.size() >= thirsty_extra:
			break
		var pc: Vector2i = dig_path[i]
		for s in _sides(pc):
			if dig_path.has(s) or not _free_land(s) or W.get_elev(s) != W.get_elev(pc) or _touches_water(s):
				continue
			if _near_reserved(s, dig_path):
				continue
			var far := true
			for o in _thirsty_all():
				if W.iso_distance(s, o) < 2:
					far = false
			if not far:
				continue
			path_houses.append(s)
			plan_buildings.append(s)
			reserved[s] = true
			break
	print("[SHOWCASE] loop: panjang Gali = %d, bangunan di jalur Gali = %s" % [dig_path.size(), str(path_houses)])

## Kanal bocor: 3 petak kanal dari danau yang lebih rendah 1 tingkat dari danau,
## berakhir di samping rumah yang juga lebih rendah -> air meluap dan membanjiri rumah.
func _plan_flood() -> void:
	var dirs := [TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE,
		TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE]
	var opp := {dirs[0]: dirs[1], dirs[1]: dirs[0], dirs[2]: dirs[3], dirs[3]: dirs[2]}
	var r: Rect2i = W.unlocked_area
	var anchor: Vector2 = _dig_anchor()
	var best: Array[Vector2i] = []
	var best_e := 0
	var best_score := -INF
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var t := Vector2i(x, y)
			if not _free_land(t) or not W.in_diamond(t, W.unlock_r - 2):
				continue
			for d in dirs:
				var back: Vector2i = W.world.get_neighbor_cell(t, opp[d])
				if W.grid_data.get(back, -1) != W.TileState.WATER or not W.is_in_active_area(back):
					continue
				var e: int = W.get_elev(back)
				if e < 1:
					continue
				var cells: Array[Vector2i] = [t]
				var cur: Vector2i = t
				for i in 3:
					cur = W.world.get_neighbor_cell(cur, d)
					cells.append(cur)
				var ok := true
				for i in cells.size():
					var c: Vector2i = cells[i]
					if not _free_land(c) or not W.in_diamond(c, W.unlock_r - 2) \
							or W.get_elev(c) < e - 1 or W.get_elev(c) > e or _near_reserved(c, cells):
						ok = false
						break
					if i > 0 and _touches_water(c):
						ok = false
						break
				if not ok:
					continue
				var dist: float = W.cell_to_global(cells[2]).distance_to(anchor)
				if dist < 60.0:
					continue  # jangan menumpuk dengan jalur Gali
				var score: float = -dist + rng.randf() * 4.0
				if score > best_score:
					best_score = score
					best = cells
					best_e = e
	if best.is_empty():
		push_warning("Showcase loop: tidak menemukan tempat kanal bocor, Fill memakai kanal buntu biasa")
		return
	for c in fill_stub:
		reserved.erase(c)
	fill_stub.clear()
	for i in 3:
		fill_stub.append(best[i])
	flood_house = best[3]
	# halaman rumah ikut rendah supaya genangan banjir terlihat di sekitar rumah
	var yard: Array[Vector2i] = [flood_house]
	var hy: float = W.cell_to_global(flood_house).y
	for src in [flood_house, best[2]]:
		for n in _sides(src):
			if yard.size() >= 4:
				break
			if best.has(n) or yard.has(n) or not _free_land(n) or _touches_water(n):
				continue
			if W.cell_to_global(n).y < hy - 1.0:
				continue  # petak di belakang rumah tertutup sprite bangunan, tidak dipakai
			var mine: Array = []
			mine.append_array(best)
			mine.append_array(yard)
			mine.append(n)
			if _near_reserved(n, mine):
				continue
			yard.append(n)
	var low: Array[Vector2i] = []
	low.append_array(best)
	for c in yard:
		if not low.has(c):
			low.append(c)
	_flatten(low, best_e - 1)
	# tanah di sekeliling dibuat setinggi danau supaya banjir tidak melebar ke mana-mana
	for c in low:
		for n in _sides(c):
			if low.has(n) or not _free_land(n):
				continue
			if W.get_elev(n) < best_e:
				W.set_elev(n, best_e)
	for c in low:
		reserved[c] = true
	flood_yard = yard
	print("[SHOWCASE] loop: halaman banjir = %s" % str(yard))
	plan_buildings.append(flood_house)
	print("[SHOWCASE] loop: kanal bocor %s -> rumah banjir %s (danau elevasi %d)" % [str(fill_stub), str(flood_house), best_e])

## Genangan di halaman rumah surut setelah sumber bocornya ditimbun (dipercepat supaya muat di video).
func _drain_flood(dur: float) -> void:
	var cells: Array = []
	cells.append_array(flood_yard)
	cells.append_array(fill_stub)
	var start := {}
	for c in cells:
		start[c] = W.water.get_depth(c)
	var t0: float = vt
	while vt - t0 < dur:
		var k: float = 1.0 - (vt - t0) / dur
		for c in cells:
			if W.water.depth.has(c):
				W.water.depth[c] = minf(W.water.depth[c], float(start[c]) * k)
		await get_tree().process_frame
	for c in cells:
		W.water.depth.erase(c)

## Bangunan tambahan di samping kanal yang sudah ada, dekat pusat aksi (sudah teraliri, cincin biru).
func _plan_fillers() -> void:
	var anchor: Vector2 = _dig_anchor()
	var canal := {}
	for b in connected:
		for c in connected[b]:
			canal[c] = true
	var cand: Array = []
	for c in canal:
		for s in _sides(c):
			if not _free_land(s) or W.get_elev(s) > W.get_elev(c) or canal.has(s):
				continue
			var d: float = W.cell_to_global(s).distance_to(anchor)
			if d > filler_radius:
				continue
			cand.append([d, s])
	cand.sort_custom(func(a, b) -> bool: return a[0] < b[0])
	var added := 0
	for item in cand:
		if added >= filler_buildings:
			break
		var s: Vector2i = item[1]
		if reserved.has(s):
			continue
		var ok := true
		for o in plan_buildings:
			if W.iso_distance(s, o) < 2:
				ok = false
				break
		if not ok:
			continue
		# jangan menempel jalur Gali / kanal bocor (supaya tidak ikut "terselamatkan")
		for n in W.world.get_surrounding_cells(s):
			if dig_path.has(n) or fill_stub.has(n) or flood_yard.has(n) or level_cells.has(n):
				ok = false
		if not ok:
			continue
		plan_buildings.append(s)
		reserved[s] = true
		added += 1
	print("[SHOWCASE] loop: bangunan tambahan = %d" % added)

func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_plan_scene()
	_plan_path_houses()
	if flood_demo:
		_plan_flood()
	_plan_fillers()
	for c in flood_yard:
		W.dig_pending[c] = true
	_build_scene()
	cam_base_pos = W.camera.position
	cam_base_zoom = W.camera.zoom.x
	W.elapsed = float(start_day - 1) * W.day_length + 0.05
	Engine.time_scale = warmup_speed
	await _wait(warmup_seconds)

	_after_warmup()
	for c in flood_yard:
		W.dig_pending.erase(c)
	if hide_hud:
		W.hud.get_node("Root").visible = false
	var thirsty_list: Array = _thirsty_all()
	for h in thirsty_list:
		var b = W.buildings.buildings.get(h)
		if b != null:
			b.water = b.max_water * loop_start_water
	protect_floor = 0.12  # bangunan kehausan tidak boleh hancur sebelum kanal selesai
	var frame: Array = _frame_cells()
	print("[SHOWCASE] loop: Fill perlu geser kamera = %s, bangunan total = %d" % [
		str(_fill_needs_pan(frame)), W.buildings.buildings.size()])
	# OBSERVE: mulai dari seluruh peta
	cam_goal_focus = cam_base_pos
	cam_focus = cam_base_pos
	cam_zoom_mul = observe_zoom
	cam_goal_zoom = observe_zoom
	cut_start = vt
	_mark("observe")
	Engine.time_scale = 1.0
	var obs_t0: float = vt
	while vt - obs_t0 < observe_hold:
		# zoom pelan dan rata (linear), bukan lompatan
		var k: float = (vt - obs_t0) / maxf(0.01, observe_hold)
		cam_goal_zoom = lerpf(observe_zoom, observe_zoom * observe_drift, k)
		cam_zoom_mul = cam_goal_zoom
		await get_tree().process_frame
	# masuk ke area aksi
	_mark("zoom_in")
	var from_pos: Vector2 = cam_focus
	var from_zoom: float = cam_zoom_mul
	_focus_cells(frame, 1.0, loop_zoom)
	var to_pos: Vector2 = cam_goal_focus + focus_offset
	var zi_t0: float = vt
	while vt - zi_t0 < zoom_in_time:
		var u: float = clampf((vt - zi_t0) / maxf(0.01, zoom_in_time), 0.0, 1.0)
		u = u * u * (3.0 - 2.0 * u)  # ease in-out
		# zoom diinterpolasi di skala log supaya kecepatannya terasa rata
		cam_zoom_mul = exp(lerpf(log(from_zoom), log(loop_zoom), u))
		cam_focus = from_pos.lerp(to_pos, u)
		cam_goal_zoom = cam_zoom_mul
		cam_goal_focus = cam_focus
		await get_tree().process_frame
	cam_zoom_mul = loop_zoom
	cam_goal_zoom = loop_zoom
	cam_focus = to_pos
	cam_goal_focus = to_pos

	# LEVEL
	_mark("level")
	var t0: float = vt
	if level_cells.size() >= 1:
		await _drag(RATAKAN, level_cells[0], level_cells[level_cells.size() - 1], false, 0.6)
	await _wait(maxf(0.05, loop_level - (vt - t0)))

	# DIG
	_mark("dig")
	t0 = vt
	if not dig_path.is_empty():
		await _drag(GALI, dig_path[0], dig_path[dig_path.size() - 1], false, 1.0)
	await _wait(maxf(0.05, loop_dig - (vt - t0)))

	# FILL
	_mark("fill")
	if flood_house.x >= 0:
		var dd: Array = []
		for c in flood_yard:
			dd.append(snappedf(W.water.get_depth(c), 0.01))
		print("[SHOWCASE] loop: kedalaman banjir sebelum Fill = %s" % str(dd))
	t0 = vt
	if _fill_needs_pan(_frame_cells()):
		var fc: Array = []
		fc.append_array(fill_stub)
		if flood_house.x >= 0:
			fc.append(flood_house)
		_focus_cells(fc, 1.0, loop_zoom)
		await _wait(fill_pan_wait)
	if fill_stub.size() >= 2:
		await _drag(TIMBUN, fill_stub[fill_stub.size() - 1], fill_stub[0], false, 0.55)
	if flood_house.x >= 0:
		_drain_flood(flood_drain)  # berjalan bersamaan dengan sisa segmen
	await _wait(maxf(0.05, loop_fill - (vt - t0)))

	# REFILL: kamera melebar ke semua bangunan yang dibantu, cadangan air naik sampai penuh
	_mark("refill")
	ptr_visible = false
	var wide: Array = []
	wide.append_array(thirsty_list)
	wide.append_array(dig_path)
	if flood_house.x >= 0:
		wide.append(flood_house)
	_focus_cells(wide, 1.0, refill_zoom)
	var need: float = 0.0
	for h in thirsty_list:
		var b = W.buildings.buildings.get(h)
		if b != null:
			need = maxf(need, (b.max_water - b.water) / 4.0)  # REFILL_RATE = 4/detik
	Engine.time_scale = clampf(need / maxf(0.5, loop_refill - 0.6), 0.6, 4.0)
	await _wait(loop_refill)

	_mark("selesai")
	_save_markers()
	await get_tree().process_frame
	get_tree().quit()
