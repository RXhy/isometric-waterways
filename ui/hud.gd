extends CanvasLayer
## HUD permainan (node HUD di world.tscn). Tampilan diatur di scene + ui/hud_theme.tres;
## script ini hanya mengisi angka dan menanggapi tombol.
##   Kiri atas    : cuaca hari ini (ikon besar) + Hari X/45 + prakiraan hari ini | besok
##   Kanan atas   : poin (klik = rincian) | bangunan (terancam) | hancur/batas | jembatan, lalu kolom kecepatan
##   Kiri bawah   : kartu alat 1..7 + tombol Lapisan (overlay) + tombol menu (gerigi)
##   Kanan bawah  : Aliran Air = % bangunan yang sedang mendapat air
##   Dekat kursor : tooltip info petak + pratinjau aksi alat

const TIP_OK := Color(0.55, 0.9, 0.55)
const TIP_BAD := Color(1, 0.55, 0.5)
const TIP_INFO := Color(0.75, 0.76, 0.73)

@onready var btn_pause: Button = $Root/TopRight/Speed/VBox/Pause
@onready var btn_play: Button = $Root/TopRight/Speed/VBox/Play
@onready var btn_fast: Button = $Root/TopRight/Speed/VBox/Fast
@onready var weather_panel: PanelContainer = $Root/TopLeft
@onready var weather_icon: TextureRect = $Root/TopLeft/HBox/WIcon
@onready var day_label: Label = $Root/TopLeft/HBox/VBox/DayRow/Day
@onready var day_bar: ProgressBar = $Root/TopLeft/HBox/VBox/DayRow/DayBar
@onready var fc_icons: Array = [$Root/TopLeft/HBox/VBox/Forecast/T0Icon, $Root/TopLeft/HBox/VBox/Forecast/T1Icon]
@onready var fc_labels: Array = [$Root/TopLeft/HBox/VBox/Forecast/T0, $Root/TopLeft/HBox/VBox/Forecast/T1]
@onready var fc_tomorrow: Array = [$Root/TopLeft/HBox/VBox/Forecast/Sep, $Root/TopLeft/HBox/VBox/Forecast/T1Cap,
	$Root/TopLeft/HBox/VBox/Forecast/T1Icon, $Root/TopLeft/HBox/VBox/Forecast/T1]
@onready var points_button: Button = $Root/TopRight/Stats/HBox/Points
@onready var points_bar: ProgressBar = $Root/TopRight/Stats/HBox/Points/HBox/VBox/Bar
@onready var points_label: Label = $Root/TopRight/Stats/HBox/Points/HBox/VBox/Value
@onready var bld_label: Label = $Root/TopRight/Stats/HBox/Bld/VBox/Value
@onready var bld_sub: Label = $Root/TopRight/Stats/HBox/Bld/VBox/Sub
@onready var ruin_label: Label = $Root/TopRight/Stats/HBox/Ruin/VBox/Value
@onready var bridge_label: Label = $Root/TopRight/Stats/HBox/Bridge/VBox/Value
@onready var bridge_sub: Label = $Root/TopRight/Stats/HBox/Bridge/VBox/Sub
@onready var water_bar: ProgressBar = $Root/WaterPanel/HBox/VBox/Row/Bar
@onready var water_pct: Label = $Root/WaterPanel/HBox/VBox/Row/Pct
@onready var points_popup: PanelContainer = $Root/PointsPopup
@onready var popup_lines: Label = $Root/PointsPopup/VBox/Lines
@onready var tooltip: PanelContainer = $Root/Tooltip
@onready var tip_title: Label = $Root/Tooltip/VBox/Title
@onready var tip_detail: Label = $Root/Tooltip/VBox/Detail
@onready var tip_action: Label = $Root/Tooltip/VBox/Action
@onready var layer_button: Button = $Root/ActionMenu/Tools/LayerButton
@onready var legend: PanelContainer = $Root/Legend
@onready var legend_title: Label = $Root/Legend/VBox/Title
@onready var legend_height: Control = $Root/Legend/VBox/Height
@onready var legend_water: Control = $Root/Legend/VBox/Water
@onready var end_overlay: ColorRect = $Overlay
@onready var pause_menu = $Root/PauseMenu
@onready var end_message: Label = $Overlay/Message
## Urutan sama dengan world.Tool (tombol 1..7). Bendungan sudah dihapus.
@onready var cards: Array = [
	$Root/ActionMenu/Tools/Gali, $Root/ActionMenu/Tools/Ratakan, $Root/ActionMenu/Tools/Timbun,
	$Root/ActionMenu/Tools/Jembatan, $Root/ActionMenu/Tools/Bor,
	$Root/ActionMenu/Tools/Spillway, $Root/ActionMenu/Tools/Kincir,
]

## Skala seluruh UI in-game (1 = ukuran desain). 0.72 = ringkas tapi tetap terbaca di layar desktop 1080p.
@export_range(0.5, 1.2, 0.01) var ui_scale: float = 0.72

var world
var ui_hidden: bool = false  ## H: sembunyikan semua UI (untuk screenshot/trailer atau melihat peta penuh)
var _toast: PanelContainer
var _toast_label: Label
var _toast_tw: Tween

func setup(w) -> void:
	world = w
	for i in cards.size():
		cards[i].pressed.connect(world.set_tool.bind(i))
	pause_menu.setup(world)
	$Root/ActionMenu/Tools/Menu.pressed.connect(pause_menu.open)
	btn_pause.pressed.connect(set_speed.bind(0.0))
	btn_play.pressed.connect(set_speed.bind(1.0))
	btn_fast.pressed.connect(set_speed.bind(2.0))
	points_button.pressed.connect(func(): points_popup.visible = not points_popup.visible)
	layer_button.pressed.connect(_cycle_layer)
	points_popup.hide()
	end_overlay.hide()
	set_speed(1.0)
	_update_legend()
	$Root/DebugHint.visible = world.debug_enabled()
	_make_toast()
	_apply_ui_scale()
	get_viewport().size_changed.connect(_apply_ui_scale)

## Perkecil/perbesar UI tanpa mengubah tata letak: Root diskalakan dan diberi ukuran viewport / skala,
## jadi elemen yang menempel ke kanan/bawah tetap menempel di tepi layar.
func _apply_ui_scale() -> void:
	var root: Control = $Root
	var vs: Vector2 = get_viewport().get_visible_rect().size
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.position = Vector2.ZERO
	root.scale = Vector2(ui_scale, ui_scale)
	root.size = vs / ui_scale

## Posisi layar (viewport) -> koordinat di dalam Root yang diskalakan.
func _to_root(p: Vector2) -> Vector2:
	return p / ui_scale

# --- Sembunyikan UI (tombol H / menu jeda) ---

func _hideable() -> Array:
	return [$Root/TopLeft, $Root/TopRight, $Root/ActionMenu, $Root/WaterPanel,
		$Root/Legend, $Root/DebugHint, $Root/PointsPopup, tooltip]

func toggle_ui() -> void:
	set_ui_hidden(not ui_hidden)

func set_ui_hidden(on: bool) -> void:
	ui_hidden = on
	if on:
		for n in _hideable():
			n.hide()
		toast("UI disembunyikan - tekan H untuk menampilkan")
	else:
		for n in [$Root/TopLeft, $Root/TopRight, $Root/ActionMenu, $Root/WaterPanel]:
			n.show()
		$Root/DebugHint.visible = world.debug_enabled()
		_update_legend()

# --- Pesan singkat di atas layar ---

func _make_toast() -> void:
	_toast = PanelContainer.new()
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label = Label.new()
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_child(_toast_label)
	$Root.add_child(_toast)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.position.y = 40
	_toast.modulate.a = 0.0
	_toast.hide()

## Tampilkan pesan pendek beberapa detik (tetap jalan walau game dijeda).
func toast(text: String, seconds: float = 2.5) -> void:
	if _toast == null:
		return
	_toast_label.text = text
	_toast.show()
	_toast.reset_size()
	_toast.position.x = (_to_root(get_viewport().get_visible_rect().size).x - _toast.size.x) / 2.0
	if _toast_tw:
		_toast_tw.kill()
	_toast_tw = create_tween().set_ignore_time_scale(true)
	_toast_tw.tween_property(_toast, "modulate:a", 1.0, 0.2)
	_toast_tw.tween_interval(seconds)
	_toast_tw.tween_property(_toast, "modulate:a", 0.0, 0.6)
	_toast_tw.tween_callback(_toast.hide)

# --- Kecepatan ---

func set_speed(s: float) -> void:
	Engine.time_scale = s
	btn_pause.set_pressed_no_signal(s == 0.0)
	btn_play.set_pressed_no_signal(s == 1.0)
	btn_fast.set_pressed_no_signal(s == 2.0)

func toggle_pause() -> void:
	set_speed(1.0 if Engine.time_scale == 0.0 else 0.0)

# --- Alat ---

func select_tool(t: int) -> void:
	for i in cards.size():
		cards[i].set_pressed_no_signal(i == t)

# --- Lapisan (overlay) ---

func _cycle_layer() -> void:
	world.overlay_layer.cycle()
	_update_legend()

func _update_legend() -> void:
	if ui_hidden:
		return
	var m: int = world.overlay_layer.mode if world else 0
	layer_button.set_pressed_no_signal(m != 0)
	layer_button.tooltip_text = "Lapisan info: %s (klik untuk ganti)" % (world.overlay_layer.NAMES[m] if world else "")
	legend.visible = m != 0
	legend_height.visible = m == 1
	legend_water.visible = m == 2
	legend_title.text = world.overlay_layer.NAMES[m] if world else ""

# --- Akhir permainan ---

func show_end(text: String) -> void:
	if ui_hidden:
		ui_hidden = false
		$Root/TopLeft.show()
		$Root/TopRight.show()
	end_message.text = text
	end_overlay.show()
	tooltip.hide()
	# layar akhir bersih: sembunyikan toolbar & tab supaya survei tidak tertumpuk
	for n in [$Root/ActionMenu, $Root/WaterPanel, $Root/Legend, $Root/DebugHint, $Root/PointsPopup]:
		n.hide()

# --- Pembaruan tiap frame ---

func refresh() -> void:
	if world == null:
		return
	var W = world
	var day: int = mini(W.current_day(), W.target_days)
	day_label.text = "Hari %d/%d" % [day, W.target_days]
	day_bar.value = fmod(W.elapsed, W.day_length) / W.day_length
	var today: int = W.current_day()
	var wt0: int = W.weather.weather_for(today)
	weather_icon.texture = W.weather.icon_for(wt0)
	fc_icons[0].texture = weather_icon.texture
	fc_labels[0].text = W.weather.NAMES[wt0]
	var has_tomorrow: bool = today + 1 <= W.target_days
	for n in fc_tomorrow:
		n.visible = has_tomorrow
	var tip := "Hari ini: %s" % W.weather.describe(today)
	if has_tomorrow:
		var wt1: int = W.weather.weather_for(today + 1)
		fc_icons[1].texture = W.weather.icon_for(wt1)
		fc_labels[1].text = W.weather.NAMES[wt1]
		tip += "\nBesok: %s" % W.weather.describe(today + 1)
	if today + 2 <= W.target_days:
		tip += "\nLusa: %s" % W.weather.describe(today + 2)
	weather_panel.tooltip_text = tip
	var S = W.score
	points_bar.value = S.progress()
	points_label.text = "%d/%d" % [int(S.total), S.next_threshold()]
	points_button.tooltip_text = "Bintang %d/3  |  1: %d  2: %d  3: %d poin" % [S.stars(), S.target_points, S.star2_points, S.star3_points]
	ruin_label.text = "Hancur %d/%d" % [W.buildings.destroyed_count, W.damage_quota]
	var alive := 0
	var threatened := 0
	var watered := 0
	for c in W.buildings.buildings:
		var b = W.buildings.buildings[c]
		if b.state == b.State.HANCUR:
			continue
		alive += 1
		if b.state == b.State.TERANCAM:
			threatened += 1
		if b.has_water:
			watered += 1
	bld_label.text = "Bangunan %d" % alive
	bld_sub.text = "(terancam %d)" % threatened
	bld_sub.add_theme_color_override("font_color", TIP_BAD if threatened > 0 else TIP_INFO)
	bridge_label.text = "Jembatan %d" % W.roads.bridge_stock
	bridge_sub.text = "(aktif %d)" % S.working_bridges()
	var flow: float = float(watered) / alive if alive > 0 else 0.0
	water_bar.value = flow
	water_pct.text = "%d%%" % roundi(flow * 100.0)
	if points_popup.visible:
		var lines := ""
		for src in S.SOURCES:
			lines += "%s: %d\n" % [src, int(S.by_source.get(src, 0.0))]
		lines += "Hari ini: +%d\n" % int(S.today)
		lines += "Calon bonus malam ini: %d bangunan\n" % S.bonus_buildings()
		lines += "Total: %d  |  Bintang %d/3\n" % [int(S.total), S.stars()]
		lines += "Bintang 1/2/3: %d / %d / %d" % [S.target_points, S.star2_points, S.star3_points]
		popup_lines.text = lines
	for i in 3:
		cards[i].set_stock(W.shovel)
	cards[3].set_stock(W.roads.bridge_stock)
	cards[4].set_stock(W.facilities.stock[W.facilities.Kind.BOR])
	cards[5].set_stock(W.facilities.stock[W.facilities.Kind.SPILLWAY])
	cards[6].set_stock(W.facilities.stock[W.facilities.Kind.KINCIR])
	_update_tooltip()

func _mouse_over_ui() -> bool:
	var vp := get_viewport()
	return vp.has_method("gui_get_hovered_control") and vp.gui_get_hovered_control() != null

func _update_tooltip() -> void:
	var cell: Vector2i = world.hover_cell
	if ui_hidden or world.game_over or not world.hover_valid or _mouse_over_ui() or pause_menu.visible \
			or not (GameSettings.get_value("tooltips") or world.dragging):
		tooltip.hide()
		return
	var info: Dictionary = world.tile_info(cell)
	tip_title.text = info["title"]
	tip_detail.text = info["detail"]
	tip_detail.visible = info["detail"] != ""
	tip_action.text = info["action"]
	tip_action.add_theme_color_override("font_color", TIP_OK if info["ok"] > 0 else (TIP_BAD if info["ok"] < 0 else TIP_INFO))
	tooltip.show()
	tooltip.reset_size()
	var mp := _to_root(get_viewport().get_mouse_position())
	var vs := _to_root(get_viewport().get_visible_rect().size)
	var pos := mp + Vector2(12, 14)
	if pos.x + tooltip.size.x > vs.x - 4:
		pos.x = mp.x - tooltip.size.x - 8
	if pos.y + tooltip.size.y > vs.y - 72:
		pos.y = mp.y - tooltip.size.y - 8
	tooltip.position = pos

func _unhandled_input(event: InputEvent) -> void:
	# klik di luar popup poin menutupnya
	if points_popup.visible and event is InputEventMouseButton and event.pressed:
		points_popup.hide()
