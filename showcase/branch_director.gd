extends "res://showcase/showcase_director.gd"
## SHOWCASE "Pilihan Juri" — satu kondisi awal, dua cabang aksi.
## Kondisi: satu rumah kehausan jauh dari danau, cuaca Cerah, besok Kemarau.
##   Cabang A (GALI): kanal dari danau ke rumah. Cepat, tapi ikut kering saat danau menyusut.
##   Cabang B (BOR) : sumur bor di samping rumah. Air tanah, tidak terpengaruh kemarau.
## Hasil TIDAK dipaksa: rumah hancur/selamat murni dari simulasi air game.
## Seed, rencana peta, dan bagian awal identik di kedua cabang; hanya aksinya yang beda.
## Rekam: buka showcase/cuplikan_cabang_A.tscn lalu _B.tscn, nyalakan Movie Maker, tekan F6.

@export_group("Pilihan Juri")
@export_enum("A_Gali", "B_Bor") var branch: int = 0
@export var choice_intro: float = 2.0     ## kondisi awal (sama di kedua cabang)
@export var choice_action: float = 3.0    ## aksi + air mengalir sampai cadangan rumah penuh
@export var choice_drought: float = 6.5   ## kemarau berjalan (danau menyusut)
@export var choice_hold: float = 1.5      ## tahan gambar akhir (rumah hancur / selamat)
@export var choice_zoom: float = 1.9
@export var drought_game_speed: float = 9.0 ## kecepatan game saat kemarau (supaya hasil terlihat < 7 dtk)
@export var background_floor: float = 0.3   ## bangunan lain tidak dibiarkan hancur (fokus ke rumah target)

var bor_side: Vector2i = Vector2i(-1, -1)
var destroyed_at: float = -1.0

func _enter_tree() -> void:
	drought_victims = 0
	building_count = 12
	drought_severity = 1.0   # kemarau berat: setara kemarau akhir permainan di danau kecil
	super._enter_tree()
	use_lift = false
	use_spill = false
	fill_near_dig = false

## Petak tanah di samping rumah target untuk sumur bor (sama di kedua cabang,
## supaya rencana peta identik walau aksinya berbeda).
func _pick_bor_side() -> void:
	if dig_target.x < 0:
		return
	var e: int = W.get_elev(dig_target)
	var best_d := -1
	for s in _sides(dig_target):
		if dig_path.has(s) or not _free_land(s) or W.get_elev(s) != e or _touches_water(s):
			continue
		var d: int = _water_dist(s)
		if d > best_d:  # sisi yang paling jauh dari kanal/danau, supaya jelas airnya dari sumur
			best_d = d
			bor_side = s

func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_plan_scene()
	# tanpa bukit dan tanpa demo bor bawaan: hanya satu keputusan untuk satu rumah
	level_cells.clear()
	if bor_cell.x >= 0:
		reserved.erase(bor_cell)
	bor_cell = Vector2i(-1, -1)
	bor_target = Vector2i(-1, -1)
	_pick_bor_side()
	if dig_target.x < 0 or dig_path.is_empty() or bor_side.x < 0:
		push_error("Pilihan Juri: tidak menemukan rumah target / petak sumur. Ganti map_seed. (rumah=%s jalur=%d sumur=%s)" % [
			str(dig_target), dig_path.size(), str(bor_side)])
		get_tree().quit()
		return
	reserved[bor_side] = true
	drought_list = [dig_target] as Array[Vector2i]  # hanya rumah target yang boleh hancur
	_build_scene()
	W.dig_pending[bor_side] = true
	cam_base_pos = W.camera.position
	cam_base_zoom = W.camera.zoom.x
	W.elapsed = float(start_day - 1) * W.day_length + 0.05
	Engine.time_scale = warmup_speed
	await _wait(warmup_seconds)

	_after_warmup()
	W.dig_pending.erase(bor_side)
	var target = W.buildings.buildings.get(dig_target)
	if target != null:
		target.water = target.max_water * 0.35
	var frame: Array = dig_path.duplicate()
	frame.append(dig_target)
	frame.append(bor_side)
	_focus_cells(frame, 1.0, choice_zoom)
	cam_focus = cam_goal_focus
	cam_zoom_mul = choice_zoom
	protect_floor = background_floor
	cut_start = vt
	_mark("kondisi")
	Engine.time_scale = 1.0
	await _wait(choice_intro)

	# ---- titik cabang
	_mark("aksi")
	var t0: float = vt
	if branch == 0:
		await _drag(GALI, dig_path[0], dig_path[dig_path.size() - 1], false, 0.8)
	else:
		await _wait(0.2)
		await _click(BOR, bor_side, _act_place.bind(W.facilities.Kind.BOR, bor_side, "place_stone"))
	ptr_visible = false
	await _wait(0.15)
	# air mengalir; cadangan rumah dibiarkan terisi alami
	Engine.time_scale = flow_speed
	while vt - t0 < choice_action:
		if target != null and target.water >= target.max_water - 0.5 and vt - t0 > choice_action * 0.6:
			break
		await get_tree().process_frame
	await _wait(maxf(0.0, choice_action - (vt - t0)))

	# ---- kemarau
	_new_day(start_day + 1)
	_mark("kemarau")
	t0 = vt
	Engine.time_scale = drought_game_speed
	while vt - t0 < choice_drought:
		if target != null and target.state == 2 and destroyed_at < 0.0:
			destroyed_at = vt - cut_start
			print("[SHOWCASE] rumah target hancur t=%.2f" % destroyed_at)
		await get_tree().process_frame
	if target != null and target.state != 2 and branch == 0:
		push_warning("Pilihan Juri: rumah cabang A belum hancur — naikkan choice_drought atau drought_game_speed")

	_mark("hasil")
	Engine.time_scale = 1.0
	await _wait(choice_hold)
	_mark("selesai")
	_save_branch()
	await get_tree().process_frame
	get_tree().quit()

func _save_branch() -> void:
	_save_markers()
	var path: String = str(get_meta("movie_file", ""))
	var mpath: String = path.get_base_dir().path_join("markers.json")
	var f := FileAccess.open(mpath, FileAccess.READ)
	if f == null:
		return
	var info: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	f = FileAccess.open(mpath, FileAccess.WRITE)
	if f == null:
		return
	var target = W.buildings.buildings.get(dig_target)
	info["branch"] = ["A_Gali", "B_Bor"][branch]
	info["target_destroyed"] = target != null and target.state == 2
	info["destroyed_at"] = snappedf(destroyed_at, 0.01)
	info["target_water_end"] = snappedf(target.water if target != null else -1.0, 0.1)
	f.store_string(JSON.stringify(info, "  "))
	f.close()
