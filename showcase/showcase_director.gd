extends Node
## SHOWCASE "Cuplikan Jos" — sutradara otomatis untuk merekam video cuplikan 15 detik WATERWAYS.
## Urutan: Ratakan bukit -> Gali kanal -> Kincir mengangkat air ke dataran tinggi -> Timbun -> Jembatan
##         -> Kemarau (+ Sumur Bor) -> Hujan lebat (+ Spillway) -> hari terakhir & layar kemenangan.
##
## Scene ini TIDAK mengubah game: world.tscn dipakai apa adanya sebagai node anak "Game".
## Script ini menata ~20 bangunan + kanal, lalu "memainkan" semua alat (Gali, Kincir, Jembatan,
## Ratakan, Timbun, Sumur Bor, Spillway) dan memutar cuaca Cerah -> Kemarau -> Hujan Lebat -> Cerah
## sampai ada bangunan yang hancur karena kekeringan dan banjir.
##
## Cara rekam (Godot editor):
##   1. Buka scene res://showcase/cuplikan_jos.tscn
##   2. Nyalakan tombol Movie Maker (ikon roll film di kanan atas editor)
##   3. Tekan F6 (Run Current Scene). Jangan sentuh mouse/keyboard sampai jendela game menutup sendiri.
##   Hasil: file .avi di folder `movie_file` (metadata node root) + markers.json berisi waktu tiap segmen.
##
## Semua durasi & angka bisa diubah di Inspector node root (grup "Timeline" dan "Skenario").

@export_group("Skenario")
@export var map_seed: int = 2026            ## seed peta (lokasi area & bentuk danau). Ganti kalau mau lokasi lain.
@export var building_count: int = 20         ## jumlah bangunan yang ditata (minimal 15)
@export var start_day: int = 6               ## hari yang tampil di awal video
@export var farm_ratio: float = 0.35         ## porsi Ladang vs Rumah
@export var start_points: float = 1480.0     ## poin yang tampil di HUD saat video mulai
@export var drought_victims: int = 3         ## bangunan yang hancur karena kemarau
@export var flood_victims: int = 3           ## bangunan yang hancur karena banjir
@export var drought_severity: float = 0.9    ## keparahan kemarau (0..1)
@export var rain_surge: float = 0.6          ## kenaikan air saat hujan lebat (makin besar makin banjir)

@export_group("Timeline (detik video)")
## Total bagian yang dipakai = intro + ratakan + gali + kincir + timbun + jembatan + kemarau + hujan + menang
@export var warmup_seconds: float = 1.6      ## pemanasan (air mengalir, jalan terbangun) — dipotong otomatis
@export var warmup_speed: float = 6.0
@export var intro_seconds: float = 0.7
@export var level_seconds: float = 1.3       ## Ratakan: turunkan bukit yang menghalangi jalur kanal
@export var dig_seconds: float = 1.8         ## Gali kanal ke rumah yang kehausan
@export var kincir_seconds: float = 2.0      ## Kincir di dataran rendah mengangkat air ke dataran tinggi
@export var fill_seconds: float = 1.0        ## Timbun kanal yang tidak terpakai
@export var bridge_seconds: float = 0.8
@export var drought_seconds: float = 2.7
@export var rain_seconds: float = 2.7
@export var win_seconds: float = 2.3         ## layar kemenangan di akhir
@export var tools_speed: float = 1.0         ## kecepatan game saat demo alat
@export var flow_speed: float = 2.5          ## kecepatan game saat menunggu air mengalir setelah aksi
@export var weather_speed: float = 5.0       ## kecepatan game saat kemarau & hujan
@export var win_points: float = 8650.0       ## poin akhir (>= 8500 = 3 bintang)

@export_group("Tampilan")
@export var show_pointer: bool = true        ## kursor tangan buatan (kursor asli tidak terekam)
@export var pointer_color: Color = Color(1, 1, 1)
@export var action_zoom: float = 2.0         ## zoom saat demo alat (1 = tampilan awal game)
@export var weather_zoom: float = 1.0
@export var win_zoom: float = 0.95

const GALI := 0
const RATAKAN := 1
const TIMBUN := 2
const JEMBATAN := 3
const BOR := 4
const SPILLWAY := 5
const KINCIR := 6

var W  # world.gd (node Game)
var rng := RandomNumberGenerator.new()
var vt: float = 0.0            # waktu video (detik), tidak terpengaruh Engine.time_scale
var cut_start: float = -1.0    # waktu video saat bagian yang dipakai dimulai
var markers: Array = []

# rencana adegan
var plan_buildings: Array[Vector2i] = []
var connected: Dictionary = {}       # bangunan -> jalur kanal (Array[Vector2i])
var dig_target: Vector2i = Vector2i(-1, -1)
var dig_path: Array[Vector2i] = []   # dari dekat air ke samping rumah (urutan drag)
var bor_target: Vector2i = Vector2i(-1, -1)
var bor_cell: Vector2i = Vector2i(-1, -1)
var drought_list: Array[Vector2i] = []   # korban kemarau (sengaja hancur)
var thirsty: Array[Vector2i] = []        # tidak tersambung kanal tapi tidak boleh hancur
var protect_floor: float = 0.0           # >0: bangunan non-korban tidak boleh turun di bawah porsi ini
var fill_stub: Array[Vector2i] = []
var spill_stub: Array[Vector2i] = []
var level_cells: Array[Vector2i] = []   # bukit kecil di jalur Gali (diturunkan dengan Ratakan)
var lift_line: Array[Vector2i] = []     # [kanal rendah (kincir), kanal tinggi x3, rumah di dataran tinggi]
var mesa: Array[Vector2i] = []
# saklar untuk scene turunan (mis. cuplikan_loop)
var use_lift: bool = true
var use_spill: bool = true
var fill_near_dig: bool = false
var dig_len_goal: int = 0   # 0 = jalur Gali terpendek; >0 = pilih jalur yang panjangnya paling dekat dengan angka ini
var dig_len_max: int = 8    # panjang maksimal jalur Gali yang dicari
var dig_source_max: int = 0 # >0: jalur Gali hanya boleh mulai dari danau/kolam alami sebesar ini (petak) atau lebih kecil
var dig_source_min: int = 0 # ukuran minimal danau/kolam sumber jalur Gali (petak)
var _body_size := {}
var stub_anchor: Vector2 = Vector2.INF          # tanah sekitar yang ikut dinaikkan supaya terlihat seperti dataran tinggi
var reserved: Dictionary = {}

# kursor buatan
var ptr_layer: CanvasLayer
var ptr: Node2D
var ptr_from: Vector2
var ptr_to: Vector2
var ptr_t: float = 1.0
var ptr_dur: float = 0.3
var ptr_pos: Vector2               # posisi global (dunia)
var ptr_visible: bool = false
var ptr_pressed: bool = false
var ripples: Array = []            # [{pos, t}]

# drag buatan
var drag_on: bool = false
var drag_axis_fixed: int = -1

# kamera
var cam_base_pos: Vector2
var cam_base_zoom: float = 1.0
var cam_focus: Vector2
var cam_goal_focus: Vector2
var cam_zoom_mul: float = 1.0
var cam_goal_zoom: float = 1.0

func _enter_tree() -> void:
	W = get_node("Game")
	W.map_seed = map_seed
	W.expand_every_days = 0
	W.get_node("BalanceLog").enabled = false
	var bm = W.get_node("Buildings")
	bm.buildings_first_day = 0
	bm.spawn_rate_start = 0.0
	bm.spawn_rate_end = 0.0
	var wm = W.get_node("Weather")
	wm.auto_schedule = false
	wm.schedule.clear()
	for d in range(1, W.target_days + 1):
		var w: int = 0
		if d == start_day + 1:
			w = 1
		elif d == start_day + 2:
			w = 2
		wm.schedule.append(w)
	wm.rain_surge = rain_surge
	wm.drought_severity_start = drought_severity
	wm.drought_severity_max = maxf(drought_severity, wm.drought_severity_max)
	wm.drought_ramp_time = 6.0
	var fm = W.get_node("Facilities")
	fm.start_stock = [3, 1, 3, 3] as Array[int]
	W.get_node("Roads").bridges_start = 3
	process_priority = 1000  # jalan SETELAH world, hud, dll. supaya kursor/kamera buatan menang

func _ready() -> void:
	rng.seed = map_seed
	_make_pointer()
	_run()

# ---------------------------------------------------------------- waktu

func _process(delta: float) -> void:
	var ts: float = maxf(Engine.time_scale, 0.0001)
	var dt: float = delta / ts
	vt += dt
	_update_pointer(dt)
	_update_camera(dt)
	_override_game_cursor()
	if protect_floor > 0.0 and W != null:
		for c in W.buildings.buildings:
			if drought_list.has(c):
				continue
			var b = W.buildings.buildings[c]
			if b.state != 2 and b.water < b.max_water * protect_floor:
				b.water = b.max_water * protect_floor

func _wait(seconds: float) -> void:
	var until: float = vt + seconds
	while vt < until:
		await get_tree().process_frame

func _mark(label: String) -> void:
	var t: float = vt - cut_start if cut_start >= 0.0 else -1.0
	markers.append({"name": label, "t": snappedf(t, 0.001)})
	print("[SHOWCASE] %s  t=%.2f" % [label, t])

# ---------------------------------------------------------------- alur utama

func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_plan_scene()
	_build_scene()
	cam_base_pos = W.camera.position
	cam_base_zoom = W.camera.zoom.x
	cam_focus = cam_base_pos
	cam_goal_focus = cam_base_pos
	# lompat ke hari start_day (cuaca & HUD ikut)
	W.elapsed = float(start_day - 1) * W.day_length + 0.05
	Engine.time_scale = warmup_speed
	await _wait(warmup_seconds)

	# ---- bagian yang dipakai dimulai di sini
	_after_warmup()
	cut_start = vt
	_mark("mulai")
	Engine.time_scale = tools_speed
	_focus_cells(plan_buildings, 0.0, 1.0)
	await _wait(intro_seconds * 0.6)
	# kamera mulai mendekat ke bukit di jalur kanal
	if not level_cells.is_empty():
		_focus_cells(dig_path + [dig_target], 1.0, action_zoom)
	await _wait(intro_seconds * 0.4)

	await _seg_level()
	await _seg_dig()
	await _seg_kincir()
	await _seg_fill()
	await _seg_bridge()
	await _seg_drought()
	await _seg_rain()
	await _seg_win()

	_mark("selesai")
	_save_markers()
	await get_tree().process_frame
	get_tree().quit()

# ---------------------------------------------------------------- segmen

func _seg_level() -> void:
	_mark("ratakan")
	var t0: float = vt
	Engine.time_scale = tools_speed
	if level_cells.size() >= 1:
		_focus_cells(dig_path + [dig_target], 1.0, action_zoom)
		await _drag(RATAKAN, level_cells[0], level_cells[level_cells.size() - 1], false,
			maxf(0.35, level_seconds * 0.4))
	await _wait(maxf(0.05, level_seconds - (vt - t0)))

func _seg_dig() -> void:
	_mark("gali")
	var t0: float = vt
	Engine.time_scale = tools_speed
	if not dig_path.is_empty():
		_focus_cells(dig_path + [dig_target], 1.0, action_zoom)
		await _drag(GALI, dig_path[0], dig_path[dig_path.size() - 1], false, dig_seconds * 0.35)
		ptr_visible = false
		Engine.time_scale = flow_speed
	await _wait(maxf(0.05, dig_seconds - (vt - t0)))

func _seg_kincir() -> void:
	_mark("kincir")
	var t0: float = vt
	Engine.time_scale = tools_speed
	if lift_line.size() >= 5:
		_focus_cells(lift_line, 1.0, action_zoom)
		await _wait(0.25)
		await _click(KINCIR, lift_line[0], _act_place.bind(W.facilities.Kind.KINCIR, lift_line[0], "place_wood"))
		await _wait(0.15)
		ptr_visible = false
		Engine.time_scale = flow_speed
	else:
		var c: Vector2i = _find_cell(_pred_kincir)
		if c.x >= 0:
			_focus_cells([c], 1.0, action_zoom)
			await _click(KINCIR, c, _act_place.bind(W.facilities.Kind.KINCIR, c, "place_wood"))
	await _wait(maxf(0.05, kincir_seconds - (vt - t0)))

func _seg_fill() -> void:
	_mark("timbun")
	var t0: float = vt
	Engine.time_scale = tools_speed
	if fill_stub.size() >= 2:
		_focus_cells(fill_stub, 1.0, action_zoom)
		await _wait(0.15)
		await _drag(TIMBUN, fill_stub[fill_stub.size() - 1], fill_stub[0], false, fill_seconds * 0.35)
	await _wait(maxf(0.05, fill_seconds - (vt - t0)))

func _seg_bridge() -> void:
	_mark("jembatan")
	var t0: float = vt
	Engine.time_scale = tools_speed
	W.set_tool(JEMBATAN)
	var c: Vector2i = _find_cell(_pred_bridge, true)
	if c.x >= 0:
		_focus_cells([c], 1.0, action_zoom)
		await _wait(0.15)
		await _click(JEMBATAN, c, _act_bridge.bind(c))
	await _wait(maxf(0.05, bridge_seconds - (vt - t0)))

func _seg_drought() -> void:
	_new_day(start_day + 1)  # Kemarau
	_mark("kemarau")
	var t0: float = vt
	Engine.time_scale = weather_speed
	_focus_cells(plan_buildings, 0.0, weather_zoom)
	ptr_visible = false
	# semua bangunan mulai menipis cadangan airnya; korban kemarau hampir habis
	for c in W.buildings.buildings:
		var b = W.buildings.buildings[c]
		b.water = b.max_water * (0.75 if thirsty.has(c) else 0.46)
	protect_floor = 0.15
	var victim_water: float = drought_seconds * 0.6 * weather_speed
	for c in drought_list:
		if W.buildings.buildings.has(c):
			W.buildings.buildings[c].water = victim_water
	if bor_target.x >= 0 and W.buildings.buildings.has(bor_target):
		W.buildings.buildings[bor_target].water = W.buildings.buildings[bor_target].max_water * 0.3
	await _wait(drought_seconds * 0.3)
	# Sumur Bor menyelamatkan rumah yang jauh dari air
	if bor_cell.x >= 0:
		_mark("sumur_bor")
		_focus_cells([bor_cell, bor_target], 0.45, weather_zoom * 1.25)
		await _click(BOR, bor_cell, _act_place.bind(W.facilities.Kind.BOR, bor_cell, "place_stone"))
		ptr_visible = false
		_focus_cells(plan_buildings, 0.0, weather_zoom)
	await _wait(maxf(0.05, drought_seconds - (vt - t0)))
	protect_floor = 0.0

func _seg_rain() -> void:
	_new_day(start_day + 2)  # Hujan lebat
	_mark("hujan")
	var t0: float = vt
	Engine.time_scale = weather_speed
	ptr_visible = false
	_focus_cells(plan_buildings, 0.0, weather_zoom)
	for c in W.buildings.buildings:
		W.buildings.buildings[c].flood_limit = 9999.0
	await _wait(rain_seconds * 0.25)
	# bangunan yang paling lama terendam jadi korban banjir
	var flooded: Array = []
	for c in W.buildings.buildings:
		var b = W.buildings.buildings[c]
		if b.state != 2 and b.flood_time > 0.0:
			flooded.append(b)
	flooded.sort_custom(func(x, y) -> bool: return x.flood_time > y.flood_time)
	for i in mini(flood_victims, flooded.size()):
		flooded[i].flood_limit = flooded[i].flood_time + rain_seconds * 0.2 * weather_speed
	if flooded.size() < flood_victims:
		push_warning("Showcase: hanya %d bangunan tergenang" % flooded.size())
	await _wait(rain_seconds * 0.3)
	# Spillway: badan air berhenti meluap
	if spill_stub.size() > 0:
		_mark("spillway")
		var c: Vector2i = spill_stub[0]
		_focus_cells([c], 0.45, weather_zoom * 1.25)
		await _click(SPILLWAY, c, _act_place.bind(W.facilities.Kind.SPILLWAY, c, "place_stone"))
		ptr_visible = false
		_focus_cells(plan_buildings, 0.0, weather_zoom)
	await _wait(maxf(0.05, rain_seconds - (vt - t0)))

## Hari terakhir: poin melewati target 3 bintang -> layar kemenangan asli dari game.
func _seg_win() -> void:
	_mark("menang")
	var t0: float = vt
	ptr_visible = false
	W.set_tool(GALI)
	for c in W.buildings.buildings:
		var b = W.buildings.buildings[c]
		b.water = b.max_water
		b.flood_time = 0.0
	W.score.total = win_points
	W.elapsed = float(W.target_days) * W.day_length - 0.45
	Engine.time_scale = 1.0
	_focus_cells(plan_buildings, 0.0, win_zoom)
	await _wait(maxf(0.05, win_seconds - (vt - t0)))

func _seg_start_vt(label: String) -> float:
	for m in markers:
		if m["name"] == label:
			return float(m["t"]) + cut_start
	return vt

func _new_day(d: int) -> void:
	W.elapsed = float(d - 1) * W.day_length + 0.02

# ---------------------------------------------------------------- aksi pemain buatan

func _act_place(kind: int, c: Vector2i, sfx: String) -> void:
	if W.facilities.place(kind, c):
		Audio.play(sfx)
	else:
		push_warning("Showcase: gagal pasang fasilitas %d di %s" % [kind, str(c)])

func _act_bridge(c: Vector2i) -> void:
	if W.roads.build_bridge(c):
		Audio.play("place_wood")

func _pred_kincir(x: Vector2i) -> bool:
	return W.water.is_channel(x) and W.dug.has(x) and W.facilities.can_place(W.facilities.Kind.KINCIR, x)

func _pred_bridge(x: Vector2i) -> bool:
	return W.grid_data.get(x, -1) == W.TileState.ROAD and W.action_preview(x)[0] > 0

func _click(tool: int, cell: Vector2i, action: Callable) -> void:
	W.set_tool(tool)
	ptr_visible = true
	await _move_pointer(cell, 0.28)
	ptr_pressed = true
	_ripple()
	action.call()
	W.update_hud()
	await _wait(0.12)
	ptr_pressed = false

func _drag(tool: int, a: Vector2i, b: Vector2i, right: bool, dur: float) -> void:
	W.set_tool(tool)
	ptr_visible = true
	await _move_pointer(a, 0.28)
	ptr_pressed = true
	_ripple()
	var d: Vector2 = W.world.map_to_local(b) - W.world.map_to_local(a)
	var u: int = int(round((d.x / 16.0 + d.y / 8.0) / 2.0))
	var v: int = int(round((d.x / 16.0 - d.y / 8.0) / 2.0))
	drag_axis_fixed = 0 if absi(u) >= absi(v) else 1
	W._start_drag(a, right)
	drag_on = true
	_set_pointer_target(W.cell_to_global(b), dur)
	await _wait(dur + 0.1)
	_apply_drag()
	drag_on = false
	W._finish_drag()
	ptr_pressed = false
	_ripple()
	await _wait(0.1)

func _apply_drag() -> void:
	if not W.dragging:
		return
	W.drag_axis = drag_axis_fixed
	W._update_drag(W.pick_cell(ptr_pos))

# ---------------------------------------------------------------- kursor buatan

func _make_pointer() -> void:
	ptr_layer = CanvasLayer.new()
	ptr_layer.layer = 90
	add_child(ptr_layer)
	ptr = Node2D.new()
	ptr.set_script(_pointer_script())
	ptr.set("dir", self)
	ptr_layer.add_child(ptr)

func _pointer_script() -> GDScript:
	var s := GDScript.new()
	s.source_code = """extends Node2D
var dir
func _process(_d: float) -> void:
	queue_redraw()
func _draw() -> void:
	if dir == null:
		return
	var ct: Transform2D = dir.get_viewport().get_canvas_transform()
	for r in dir.ripples:
		var k: float = clampf(r["t"] / 0.35, 0.0, 1.0)
		var p: Vector2 = ct * r["pos"]
		draw_arc(p, 3.0 + 9.0 * k, 0.0, TAU, 24, Color(1, 1, 1, 0.9 * (1.0 - k)), 1.2)
	if not dir.ptr_visible or not dir.show_pointer:
		return
	var p0: Vector2 = ct * dir.ptr_pos
	var sc: float = 0.85 if dir.ptr_pressed else 1.0
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(0, 11), Vector2(3, 8.4), Vector2(5.2, 12.6),
		Vector2(7.0, 11.8), Vector2(4.9, 7.7), Vector2(8.4, 7.7)])
	for i in pts.size():
		pts[i] = p0 + pts[i] * sc
	var sh := PackedVector2Array()
	for q in pts:
		sh.append(q + Vector2(0.8, 0.8))
	draw_colored_polygon(sh, Color(0, 0, 0, 0.35))
	draw_colored_polygon(pts, dir.pointer_color)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, Color(0.08, 0.1, 0.16), 0.9)
"""
	s.reload()
	return s

func _set_pointer_target(g: Vector2, dur: float) -> void:
	ptr_from = ptr_pos
	ptr_to = g
	ptr_t = 0.0
	ptr_dur = maxf(dur, 0.01)

func _move_pointer(cell: Vector2i, dur: float) -> void:
	if ptr_pos == Vector2.ZERO:
		var vr: Rect2 = get_viewport().get_visible_rect()
		ptr_pos = W.get_viewport().get_canvas_transform().affine_inverse() * (vr.size * Vector2(0.75, 0.7))
	_set_pointer_target(W.cell_to_global(cell), dur)
	await _wait(dur + 0.02)

func _update_pointer(dt: float) -> void:
	if ptr_t < 1.0:
		ptr_t = minf(1.0, ptr_t + dt / ptr_dur)
		var e: float = ptr_t * ptr_t * (3.0 - 2.0 * ptr_t)
		ptr_pos = ptr_from.lerp(ptr_to, e)
	for r in ripples:
		r["t"] += dt
	ripples = ripples.filter(func(r) -> bool: return r["t"] < 0.35)
	if drag_on:
		_apply_drag()

func _ripple() -> void:
	ripples.append({"pos": ptr_pos, "t": 0.0})

## Sorotan petak & tooltip game mengikuti kursor buatan, bukan mouse asli.
func _override_game_cursor() -> void:
	if W == null or W.hud == null:
		return
	W.hud.tooltip.hide()
	W.hud.points_popup.hide()
	if drag_on:
		_apply_drag()
	var show: bool = ptr_visible and show_pointer and not W.dragging and not W.game_over
	W.cursor.visible = show
	if show:
		var cell: Vector2i = W.pick_cell(ptr_pos)
		if W.grid_data.has(cell):
			W.cursor.position = W.cell_to_global(cell)
			var ok: int = W.action_preview(cell)[0]
			W.cursor.modulate = W.cursor_ok if ok > 0 else (W.cursor_bad if ok < 0 else W.cursor_info)
		else:
			W.cursor.visible = false

# ---------------------------------------------------------------- kamera

func _focus_cells(cells: Array, weight: float, zoom_mul: float) -> void:
	if cells.is_empty():
		return
	var sum := Vector2.ZERO
	for c in cells:
		sum += W.cell_to_global(c)
	var center: Vector2 = sum / float(cells.size())
	cam_goal_focus = cam_base_pos.lerp(center, weight)
	cam_goal_zoom = zoom_mul

func _update_camera(dt: float) -> void:
	if W == null or cam_base_zoom <= 0.0 or cut_start < 0.0:
		return
	var k: float = 1.0 - exp(-3.2 * dt)
	cam_focus = cam_focus.lerp(cam_goal_focus, k)
	cam_zoom_mul = lerpf(cam_zoom_mul, cam_goal_zoom, k)
	var z: float = cam_base_zoom * cam_zoom_mul
	W.camera.zoom = Vector2(z, z)
	W.camera.position = cam_focus
	W.target_zoom = z
	W._pan_goal_on = false

# ---------------------------------------------------------------- perencanaan peta

func _is_land(c: Vector2i) -> bool:
	var t: int = W.grid_data.get(c, -1)
	return t == W.TileState.DIRT or t == W.TileState.GRASS

func _free_land(c: Vector2i) -> bool:
	return _is_land(c) and W.is_playable(c) and not reserved.has(c) and not W.roads.is_road(c) \
		and not W.buildings.has_building(c) and not W.facilities.has_facility(c)

func _sides(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for s in [TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE,
			TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE]:
		out.append(W.world.get_neighbor_cell(c, s))
	return out

func _touches_water(c: Vector2i) -> bool:
	for n in W.world.get_surrounding_cells(c):
		if W.grid_data.get(n, -1) == W.TileState.WATER:
			return true
	for s in [TileSet.CELL_NEIGHBOR_TOP_CORNER, TileSet.CELL_NEIGHBOR_BOTTOM_CORNER,
			TileSet.CELL_NEIGHBOR_LEFT_CORNER, TileSet.CELL_NEIGHBOR_RIGHT_CORNER]:
		if W.grid_data.get(W.world.get_neighbor_cell(c, s), -1) == W.TileState.WATER:
			return true
	return false

## Titik awal kanal: daratan bebas yang bersebelahan (sisi) dengan air alami / kanal galian
## yang permukaannya cukup tinggi supaya air mengalir masuk.
func _is_source(c: Vector2i) -> bool:
	var e: int = W.get_elev(c)
	for n in _sides(c):
		var t: int = W.grid_data.get(n, -1)
		if t == W.TileState.WATER and W.is_in_active_area(n) and W.get_elev(n) >= e:
			return true
		if t == W.TileState.CANAL and W.dug.has(n) and W.get_elev(n) == e and not W.roads.bridges.has(n):
			return true
	return false

## BFS dari semua titik sumber. Hasil: {cell: parent} (parent = Vector2i(-9999,-9999) untuk sumber).
func _canal_field(blocked: Dictionary) -> Dictionary:
	var parent := {}
	var dist := {}
	var queue: Array[Vector2i] = []
	var r: Rect2i = W.active_area
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			if _free_land(c) and not blocked.has(c) and _is_source(c):
				parent[c] = Vector2i(-9999, -9999)
				dist[c] = 0
				queue.append(c)
	var i := 0
	while i < queue.size():
		var cur: Vector2i = queue[i]
		i += 1
		if int(dist[cur]) >= 7:
			continue
		for n in _sides(cur):
			if parent.has(n) or blocked.has(n) or not _free_land(n):
				continue
			if W.get_elev(n) != W.get_elev(cur):
				continue
			parent[n] = cur
			dist[n] = int(dist[cur]) + 1
			queue.append(n)
	return {"parent": parent, "dist": dist}

func _path_from(field: Dictionary, start: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var parent: Dictionary = field["parent"]
	var c: Vector2i = start
	while true:
		out.append(c)
		var p: Vector2i = parent[c]
		if p.x == -9999:
			break
		c = p
	return out  # dari samping bangunan menuju air

func _best_canal(field: Dictionary, b: Vector2i) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	var dist: Dictionary = field["dist"]
	for s in _sides(b):
		if dist.has(s) and W.get_elev(s) >= W.get_elev(b):
			var p := _path_from(field, s)
			if best.is_empty() or p.size() < best.size():
				best = p
	return best

func _plan_scene() -> void:
	_plan_lift()
	var field := _canal_field({})
	var dist: Dictionary = field["dist"]
	# kandidat bangunan: daratan bebas, tidak menempel air, punya kanal 2..6 petak ke air
	var cand: Array[Vector2i] = []
	var r: Rect2i = W.unlocked_area
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			if not _free_land(c) or _touches_water(c) or not W.in_diamond(c, W.unlock_r - 1):
				continue
			var best := 99
			for s in _sides(c):
				if dist.has(s) and W.get_elev(s) >= W.get_elev(c):
					best = mini(best, int(dist[s]) + 1)
			if best >= 2 and best <= 6:
				cand.append(c)
	# acak deterministik
	for i in range(cand.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Vector2i = cand[i]
		cand[i] = cand[j]
		cand[j] = tmp
	for c in cand:
		if plan_buildings.size() >= building_count:
			break
		var ok := true
		for o in plan_buildings:
			if W.iso_distance(c, o) < 3:
				ok = false
				break
		if ok:
			plan_buildings.append(c)
	if plan_buildings.size() < building_count:
		# tambahan: bangunan yang jauh dari air (tetap valid, cocok untuk korban kemarau / sumur bor)
		var r2: Rect2i = W.unlocked_area
		for y in range(r2.position.y, r2.end.y):
			for x in range(r2.position.x, r2.end.x):
				var c := Vector2i(x, y)
				if plan_buildings.size() >= building_count:
					break
				if not _free_land(c) or _touches_water(c) or not W.in_diamond(c, W.unlock_r - 1):
					continue
				var ok2 := true
				for o in plan_buildings:
					if W.iso_distance(c, o) < 3:
						ok2 = false
						break
				if ok2:
					plan_buildings.append(c)
	print("[SHOWCASE] bangunan direncanakan: %d (kandidat dekat air %d)" % [plan_buildings.size(), cand.size()])
	for b in plan_buildings:
		reserved[b] = true

	# target Gali: rumah dengan jalur drag lurus/L dari dekat air ke sampingnya
	_pick_dig_target()
	# sumur bor: rumah tanpa kanal + petak tanah bebas di sampingnya
	for b in plan_buildings:
		if b == dig_target or b == _lift_house() or bor_target.x >= 0:
			continue
		for s in _sides(b):
			if _free_land(s) and W.get_elev(s) == W.get_elev(b) and not _touches_water(s):
				bor_target = b
				bor_cell = s
				reserved[s] = true
				break
	# kanal untuk sisanya, kecuali korban kemarau (yang paling jauh dari air)
	var others: Array[Vector2i] = []
	for b in plan_buildings:
		if b != dig_target and b != bor_target and b != _lift_house():
			others.append(b)
	others.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _water_dist(a) > _water_dist(b))
	for i in others.size():
		if drought_list.size() < drought_victims:
			drought_list.append(others[i])
			continue
		var f := _canal_field(_reserved_except([]))
		var p := _best_canal(f, others[i])
		if p.is_empty():
			thirsty.append(others[i])  # tidak bisa dialiri kanal
			continue
		connected[others[i]] = p
		for c in p:
			reserved[c] = true
			W.dug[c] = true  # sementara, supaya kanal berikutnya bisa menyambung
	for b in connected:
		for c in connected[b]:
			W.dug.erase(c)
	# kanal buntu untuk Timbun, kanal lurus dari danau untuk Spillway, petak untuk Ratakan
	if use_spill:
		spill_stub = _straight_stub(3, true)
		if spill_stub.is_empty():
			spill_stub = _synth_stub(3, W.camera.position)
		for c in spill_stub:
			reserved[c] = true
	if fill_near_dig and dig_target.x >= 0:
		stub_anchor = W.cell_to_global(dig_target)
	fill_stub = _straight_stub(3, false)
	if fill_stub.is_empty():
		fill_stub = _synth_stub(3, W.camera.position if stub_anchor == Vector2.INF else stub_anchor)
	stub_anchor = Vector2.INF
	for c in fill_stub:
		reserved[c] = true
	print("[SHOWCASE] tersambung=%d kemarau=%d gali=%s bor=%s spill=%d timbun=%d ratakan=%d" % [
		connected.size(), drought_list.size(), str(dig_target), str(bor_cell),
		spill_stub.size(), fill_stub.size(), level_cells.size()])

func _lift_house() -> Vector2i:
	return lift_line[4] if lift_line.size() >= 5 else Vector2i(-1, -1)

## Dataran tinggi buatan untuk demo Kincir: kanal rendah di tepi danau (tempat kincir),
## lalu 3 petak kanal kering di dataran +1 dan sebuah rumah di ujungnya.
func _plan_lift() -> void:
	if not use_lift:
		return
	var dirs := [TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE,
		TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE]
	var opp := {dirs[0]: dirs[1], dirs[1]: dirs[0], dirs[2]: dirs[3], dirs[3]: dirs[2]}
	var r: Rect2i = W.unlocked_area
	var best: Array[Vector2i] = []
	var best_score := -INF
	var center: Vector2 = W.camera.position
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var t := Vector2i(x, y)
			if not _free_land(t) or not W.in_diamond(t, W.unlock_r - 2) or W.get_elev(t) > 2:
				continue
			var e: int = W.get_elev(t)
			for d in dirs:
				var back: Vector2i = W.world.get_neighbor_cell(t, opp[d])
				if W.grid_data.get(back, -1) != W.TileState.WATER or W.get_elev(back) < e:
					continue
				var p: Array[Vector2i] = [t]
				var cur: Vector2i = t
				var ok := true
				for i in 4:
					cur = W.world.get_neighbor_cell(cur, d)
					if not _free_land(cur) or W.get_elev(cur) != e or not W.in_diamond(cur, W.unlock_r - 1):
						ok = false
						break
					if i >= 1 and _touches_water(cur):
						ok = false
						break
					p.append(cur)
				if not ok:
					continue
				# petak kanal tinggi pertama tidak boleh bersebelahan sisi dengan air selain lewat p[0]
				for n in _sides(p[1]):
					if n != p[0] and W.water.is_channel(n):
						ok = false
				if not ok:
					continue
				var score: float = -W.cell_to_global(p[2]).distance_to(center) + rng.randf() * 20.0
				if score > best_score:
					best_score = score
					best = p
	lift_line = best
	if lift_line.size() < 5:
		push_warning("Showcase: tidak menemukan tempat dataran tinggi untuk demo Kincir")
		lift_line = []
		return
	var e2: int = W.get_elev(lift_line[0])
	for c in lift_line:
		reserved[c] = true
	plan_buildings.append(lift_line[4])
	# tanah di sekeliling ikut naik supaya terlihat seperti dataran tinggi
	for i in range(1, 5):
		for n in W.world.get_surrounding_cells(lift_line[i]):
			if _free_land(n) and W.get_elev(n) == e2 and not _touches_water(n) and not mesa.has(n):
				mesa.append(n)
				reserved[n] = true
	print("[SHOWCASE] dataran kincir: %s (+%d petak sekitar)" % [str(lift_line), mesa.size()])

func _reserved_except(keep: Array) -> Dictionary:
	var out := {}
	for c in plan_buildings:
		out[c] = true
	for c in dig_path:
		out[c] = true
	if bor_cell.x >= 0:
		out[bor_cell] = true
	for c in keep:
		out.erase(c)
	return out

func _water_dist(c: Vector2i) -> int:
	var d: int = W.water_distance(c, 14)
	return 99 if d < 0 else d

func _pick_dig_target() -> void:
	_search_dig(true)
	if dig_target.x < 0:
		_search_dig(false)
	if dig_target.x < 0:
		_synth_dig()
	if dig_target.x < 0:
		push_warning("Showcase: tidak menemukan rumah untuk demo Gali/Ratakan")
		return
	_make_ridge()

## Cadangan: cari tepi danau yang punya `total` petak tanah berurutan lurus menjauhi air,
## lalu ratakan medan di bawahnya ke ketinggian permukaan air. Tidak bergantung pada
## kebetulan bentuk peta. Mengembalikan {"cells": [...], "e": elevasi} atau {}.
func _synth_line(total: int, anchor: Vector2, strict: bool) -> Dictionary:
	var dirs := [TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE,
		TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE]
	var opp := {dirs[0]: dirs[1], dirs[1]: dirs[0], dirs[2]: dirs[3], dirs[3]: dirs[2]}
	var r: Rect2i = W.unlocked_area
	var best: Dictionary = {}
	var best_score := -INF
	var n_shore := 0
	var n_line := 0
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
				if e > 2:
					continue
				n_shore += 1
				var side_wet := false
				for sd in dirs:
					if sd == d or sd == opp[d]:
						continue
					var sn: Vector2i = W.world.get_neighbor_cell(t, sd)
					if W.water.is_channel(sn) or W.grid_data.get(sn, -1) == W.TileState.WATER:
						side_wet = true
				if side_wet:
					continue
				var p: Array[Vector2i] = [t]
				var cur: Vector2i = t
				var ok := true
				for i in total - 1:
					cur = W.world.get_neighbor_cell(cur, d)
					if not _free_land(cur) or not W.in_diamond(cur, W.unlock_r - 2) or _touches_water(cur):
						ok = false
						break
					if strict and _near_reserved(cur, p):
						ok = false
						break
					p.append(cur)
				if not ok or (strict and _near_reserved(t, p)):
					continue
				n_line += 1
				var cost := 0
				for c in p:
					cost += absi(W.get_elev(c) - e)
				var mid: Vector2 = W.cell_to_global(p[p.size() / 2])
				var score: float = -float(cost) * 30.0 - mid.distance_to(anchor) * 0.1 + rng.randf() * 5.0
				if score > best_score:
					best_score = score
					best = {"cells": p, "e": e}
	print("[SHOWCASE] synth_line(%d, strict=%s): tepi=%d jalur=%d" % [total, str(strict), n_shore, n_line])
	return best

func _flatten(cells: Array, e: int) -> void:
	for c in cells:
		if W.get_elev(c) != e:
			W.set_elev(c, e)

## Rumah + jalur Gali buatan: 5 petak kanal dari tepi danau, rumah di ujungnya.
func _synth_dig() -> void:
	var line: Dictionary = _synth_line(6, W.camera.position, true)
	if line.is_empty():
		line = _synth_line(6, W.camera.position, false)
	if line.is_empty():
		return
	var cells: Array = line["cells"]
	var e: int = line["e"]
	_flatten(cells, e)
	var house: Vector2i = cells[5]
	var p: Array[Vector2i] = []
	for i in 5:
		p.append(cells[i])
	dig_target = house
	dig_path = p
	if not plan_buildings.has(house):
		plan_buildings.append(house)
	reserved[house] = true
	# petak di sekeliling rumah ikut rata (tempat sumur bor / halaman)
	for s in _sides(house):
		if _free_land(s) and not _touches_water(s) and not p.has(s):
			_flatten([s], e)
	print("[SHOWCASE] jalur Gali buatan: %s -> rumah %s (elevasi %d)" % [str(p), str(house), e])

## Kanal buntu (Timbun / Spillway) buatan bila pencarian biasa tidak menemukan apa pun.
func _synth_stub(n: int, anchor: Vector2) -> Array[Vector2i]:
	var line: Dictionary = _synth_line(n, anchor, true)
	if line.is_empty():
		line = _synth_line(n, anchor, false)
	var out: Array[Vector2i] = []
	if line.is_empty():
		return out
	_flatten(line["cells"], line["e"])
	for c in line["cells"]:
		out.append(c)
	return out

func _search_dig(strict: bool) -> void:
	var best_len := 99
	for b in plan_buildings:
		if b == _lift_house():
			continue
		var e: int = W.get_elev(b)
		for s in _sides(b):
			if not _free_land(s) or W.get_elev(s) != e or _touches_water(s):
				continue
			# cari titik awal T dekat air dalam radius kecil
			for y in range(s.y - 16, s.y + 17):
				for x in range(s.x - 8, s.x + 9):
					var t := Vector2i(x, y)
					if not _free_land(t) or W.get_elev(t) != e or not _is_source(t):
						continue
					if dig_source_max > 0 and not _small_source(t):
						continue
					for axis in [0, 1]:
						var p := _drag_cells(t, s, axis)
						if p.size() < 3 or p.size() > dig_len_max or e > 2:
							continue
						var score_len: int = p.size() if dig_len_goal <= 0 else absi(p.size() - dig_len_goal)
						if score_len >= best_len:
							continue
						var ok := true
						for c in p:
							if not _free_land(c) or W.get_elev(c) != e or c == b:
								ok = false
								break
							if strict and c != t and _is_source(c):
								ok = false  # biar air masuk dari ujung saja (terlihat mengalir)
								break
						if ok:
							best_len = score_len
							dig_target = b
							dig_path = p

## Titik awal kanal yang hanya bersebelahan dengan danau/kolam alami kecil (<= dig_source_max petak).
func _small_source(t: Vector2i) -> bool:
	if _body_size.is_empty():
		for c in W.water.body_of:
			var id = W.water.body_of[c]
			_body_size[id] = int(_body_size.get(id, 0)) + 1
	var found := false
	for n in W.world.get_surrounding_cells(t):
		if not W.water.body_of.has(n):
			continue
		var sz: int = int(_body_size[W.water.body_of[n]])
		if sz > dig_source_max or sz < dig_source_min:
			return false
		found = true
	return found

func _make_ridge() -> void:
	if dig_target.x >= 0:
		for c in dig_path:
			reserved[c] = true
		# bukit kecil (2-3 petak) di tengah jalur: harus diratakan dulu sebelum digali
		var last: int = maxi(1, mini(3, dig_path.size() - 2))
		var ridge: Array[Vector2i] = []
		for i in range(1, last + 1):
			ridge.append(dig_path[i])
		var straight := false
		for axis in [0, 1]:
			if _drag_cells(ridge[0], ridge[ridge.size() - 1], axis) == ridge:
				straight = true
		if not straight:
			ridge = [dig_path[1]] as Array[Vector2i]
		level_cells = ridge

## Petak yang dilewati drag world.gd dari a ke b dengan sumbu pertama `axis`.
func _drag_cells(a: Vector2i, b: Vector2i, axis: int) -> Array[Vector2i]:
	var keep_axis: int = W.drag_axis
	W.drag_axis = axis
	var p: Array[Vector2i] = W._drag_path(a, b)
	W.drag_axis = keep_axis
	if p.is_empty() or p[p.size() - 1] != b:
		return []
	return p

func _straight_stub(n: int, need_straight_from_water: bool) -> Array[Vector2i]:
	var dirs := [TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE,
		TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE]
	var opp := {dirs[0]: dirs[1], dirs[1]: dirs[0], dirs[2]: dirs[3], dirs[3]: dirs[2]}
	var r: Rect2i = W.unlocked_area
	var best: Array[Vector2i] = []
	var best_score := -1.0
	var center: Vector2 = W.camera.position if stub_anchor == Vector2.INF else stub_anchor
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var t := Vector2i(x, y)
			if not _free_land(t) or not W.in_diamond(t, W.unlock_r - 2):
				continue
			for d in dirs:
				var back: Vector2i = W.world.get_neighbor_cell(t, opp[d])
				if W.grid_data.get(back, -1) != W.TileState.WATER or W.get_elev(back) < W.get_elev(t):
					continue
				var side_wet := false
				for sd in dirs:
					if sd == d or sd == opp[d]:
						continue
					if W.water.is_channel(W.world.get_neighbor_cell(t, sd)):
						side_wet = true
				if side_wet:
					continue
				var p: Array[Vector2i] = [t]
				var cur: Vector2i = t
				var ok := true
				for i in n - 1:
					cur = W.world.get_neighbor_cell(cur, d)
					if not _free_land(cur) or W.get_elev(cur) != W.get_elev(t) or _near_reserved(cur, p):
						ok = false
						break
					p.append(cur)
				if not ok or _near_reserved(t, p):
					continue
				var score: float = 1000.0 - W.cell_to_global(t).distance_to(center)
				if need_straight_from_water:
					score += rng.randf() * 50.0
				if score > best_score:
					best_score = score
					best = p
	return best

func _near_reserved(c: Vector2i, own: Array) -> bool:
	for n in W.world.get_surrounding_cells(c):
		if reserved.has(n) and not own.has(n):
			return true
	return false

func _level_strip(n: int) -> Array[Vector2i]:
	var dirs := [TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE]
	var r: Rect2i = W.unlocked_area
	var best: Array[Vector2i] = []
	var best_d := INF
	var center: Vector2 = W.camera.position
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var t := Vector2i(x, y)
			if not _free_land(t) or W.get_elev(t) >= 3 or not W.in_diamond(t, W.unlock_r - 2):
				continue
			for d in dirs:
				var p: Array[Vector2i] = [t]
				var cur: Vector2i = t
				var ok := not _touches_water(t)
				for i in n - 1:
					cur = W.world.get_neighbor_cell(cur, d)
					if not _free_land(cur) or W.get_elev(cur) != W.get_elev(t) or _touches_water(cur) \
							or _near_reserved(cur, p):
						ok = false
						break
					p.append(cur)
				if not ok or _near_reserved(t, p):
					continue
				var dd: float = W.cell_to_global(t).distance_to(center)
				if dd < best_d:
					best_d = dd
					best = p
	return best

func _find_cell(pred: Callable, near_center: bool = false) -> Vector2i:
	var r: Rect2i = W.unlocked_area
	var best := Vector2i(-1, -1)
	var best_d := INF
	var center: Vector2 = W.camera.position
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			if not W.is_playable(c) or not pred.call(c):
				continue
			var dd: float = W.cell_to_global(c).distance_to(center) if near_center else 0.0
			if best.x < 0 or dd < best_d:
				best = c
				best_d = dd
	return best

# ---------------------------------------------------------------- membangun adegan

func _build_scene() -> void:
	# kanal yang sudah ada (seolah digali pemain di hari-hari sebelumnya)
	for b in connected:
		for c in connected[b]:
			W.dug[c] = true
			W.set_base(c, W.TileState.CANAL)
	for c in spill_stub:
		W.dug[c] = true
		W.set_base(c, W.TileState.CANAL)
	for c in fill_stub:
		W.dug[c] = true
		W.set_base(c, W.TileState.CANAL)
	# bukit kecil di jalur Gali
	for c in level_cells:
		W.set_elev(c, W.get_elev(c) + 1)
	# dataran tinggi + kanal untuk demo Kincir
	if lift_line.size() >= 5:
		var e: int = W.get_elev(lift_line[0])
		for c in mesa:
			W.set_elev(c, e + 1)
		for i in range(1, 5):
			W.set_elev(lift_line[i], e + 1)
		for i in range(0, 4):
			W.dug[lift_line[i]] = true
			W.set_base(lift_line[i], W.TileState.CANAL)
	# petak yang nanti dipakai demo dikunci sementara supaya jalan tidak lewat situ
	for c in dig_path:
		W.dig_pending[c] = true
	for c in level_cells:
		W.dig_pending[c] = true
	if bor_cell.x >= 0:
		W.dig_pending[bor_cell] = true
	# bangunan: yang tersambung dulu, supaya jalan rapi
	var order: Array[Vector2i] = []
	for b in plan_buildings:
		if connected.has(b):
			order.append(b)
	for b in plan_buildings:
		if not connected.has(b):
			order.append(b)
	for b in order:
		var typ: int = 1 if rng.randf() < farm_ratio else 0
		W.buildings._spawn(b, typ)
	for c in W.buildings.buildings:
		W.buildings.buildings[c].flood_limit = 9999.0

func _after_warmup() -> void:
	for c in dig_path:
		W.dig_pending.erase(c)
	for c in level_cells:
		W.dig_pending.erase(c)
	if bor_cell.x >= 0:
		W.dig_pending.erase(bor_cell)
	for c in W.buildings.buildings:
		var b = W.buildings.buildings[c]
		b.water = b.max_water
		b.flood_time = 0.0
	for h in [dig_target, _lift_house()]:
		if h.x >= 0 and W.buildings.buildings.has(h):
			W.buildings.buildings[h].water = W.buildings.buildings[h].max_water * 0.32
	W.score.total = start_points
	W.shovel_left = {GALI: W.dig_per_day, RATAKAN: W.level_per_day, TIMBUN: W.fill_per_day}
	W.update_hud()

func _save_markers() -> void:
	var path: String = str(get_meta("movie_file", "")) if has_meta("movie_file") else ""
	var dir: String = path.get_base_dir() if path != "" else ProjectSettings.globalize_path("user://")
	var f := FileAccess.open(dir.path_join("markers.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"cut_start": snappedf(cut_start, 0.001), "markers": markers,
			"buildings": W.buildings.buildings.size(), "destroyed": W.buildings.destroyed_count,
			"plan": {"dig_path": dig_path.size(), "ridge": level_cells.size(), "lift": lift_line.size(),
				"fill": fill_stub.size(), "spill": spill_stub.size(), "bor": bor_cell.x >= 0,
				"drought": drought_list.size(), "connected": connected.size()}}, "  "))
		f.close()
	print("[SHOWCASE] bangunan=%d hancur=%d" % [W.buildings.buildings.size(), W.buildings.destroyed_count])
