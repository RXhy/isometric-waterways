extends CanvasLayer
## HUD permainan (node HUD di world.tscn). Tampilan diatur di scene + ui/hud_theme.tres;
## script ini hanya mengisi angka dan menanggapi tombol.
##   Kiri atas    : poin (klik = rincian) + bangunan hancur   |  Kanan atas: kecepatan
##   Tab bawah    : hari + prakiraan cuaca 3 hari (di atas toolbar, gaya Terra Nil)
##   Bawah        : kartu alat + tombol Lapisan (overlay) dengan legenda
##   Dekat kursor : tooltip info petak + pratinjau aksi alat

const TIP_OK := Color(0.18, 0.5, 0.2)
const TIP_BAD := Color(0.75, 0.2, 0.15)
const TIP_INFO := Color(0.45, 0.42, 0.38)

@onready var btn_pause: Button = $Root/TopRight/HBox/Pause
@onready var btn_play: Button = $Root/TopRight/HBox/Play
@onready var btn_fast: Button = $Root/TopRight/HBox/Fast
@onready var day_label: Label = $Root/Tabs/DayTab/HBox/Day
@onready var day_bar: ProgressBar = $Root/Tabs/DayTab/HBox/DayBar
@onready var weather_slots: Array = [$Root/Tabs/WeatherTab/Weather/D0, $Root/Tabs/WeatherTab/Weather/D1, $Root/Tabs/WeatherTab/Weather/D2]
@onready var weather_arrows: Array = [$Root/Tabs/WeatherTab/Weather/A1, $Root/Tabs/WeatherTab/Weather/A2]
@onready var points_button: Button = $Root/TopLeft/HBox/Points
@onready var points_bar: ProgressBar = $Root/TopLeft/HBox/Points/HBox/Bar
@onready var points_label: Label = $Root/TopLeft/HBox/Points/HBox/Value
@onready var ruin_label: Label = $Root/TopLeft/HBox/Ruin
@onready var points_popup: PanelContainer = $Root/PointsPopup
@onready var popup_lines: Label = $Root/PointsPopup/VBox/Lines
@onready var tooltip: PanelContainer = $Root/Tooltip
@onready var tip_title: Label = $Root/Tooltip/VBox/Title
@onready var tip_detail: Label = $Root/Tooltip/VBox/Detail
@onready var tip_action: Label = $Root/Tooltip/VBox/Action
@onready var layer_button: Button = $Root/LayerButton
@onready var legend: PanelContainer = $Root/Legend
@onready var legend_title: Label = $Root/Legend/VBox/Title
@onready var legend_height: Control = $Root/Legend/VBox/Height
@onready var legend_water: Control = $Root/Legend/VBox/Water
@onready var end_overlay: ColorRect = $Overlay
@onready var pause_menu = $Root/PauseMenu
@onready var end_message: Label = $Overlay/Message
@onready var cards: Array = [
	$Root/ActionMenu/Tools/Gali, $Root/ActionMenu/Tools/Ratakan, $Root/ActionMenu/Tools/Timbun,
	$Root/ActionMenu/Tools/Jembatan, $Root/ActionMenu/Tools/Bor, $Root/ActionMenu/Tools/Bendungan,
	$Root/ActionMenu/Tools/Spillway, $Root/ActionMenu/Tools/Kincir,
]

var world

func setup(w) -> void:
	world = w
	for i in cards.size():
		cards[i].pressed.connect(world.set_tool.bind(i))
	pause_menu.setup(world)
	$Root/TopRight/HBox/Menu.pressed.connect(pause_menu.open)
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
	var m: int = world.overlay_layer.mode if world else 0
	layer_button.set_pressed_no_signal(m != 0)
	layer_button.tooltip_text = "Lapisan info: %s (klik untuk ganti)" % (world.overlay_layer.NAMES[m] if world else "")
	legend.visible = m != 0
	legend_height.visible = m == 1
	legend_water.visible = m == 2
	legend_title.text = world.overlay_layer.NAMES[m] if world else ""

# --- Akhir permainan ---

func show_end(text: String) -> void:
	end_message.text = text
	end_overlay.show()
	tooltip.hide()

# --- Pembaruan tiap frame ---

func refresh() -> void:
	if world == null:
		return
	var W = world
	var day: int = mini(W.current_day(), W.target_days)
	day_label.text = "Hari %d/%d" % [day, W.target_days]
	day_bar.value = fmod(W.elapsed, W.day_length) / W.day_length
	for i in 3:
		var d: int = W.current_day() + i
		var slot: Control = weather_slots[i]
		var show_slot: bool = d <= W.target_days
		slot.visible = show_slot
		if i > 0:
			weather_arrows[i - 1].visible = show_slot
		if show_slot:
			var wt: int = W.weather.weather_for(d)
			slot.get_node("Icon").texture = W.weather.icon_for(wt)
			slot.get_node("Label").text = "H%d" % d
			slot.tooltip_text = "Hari %d: %s" % [d, W.weather.describe(d)]
	var S = W.score
	points_bar.value = S.progress()
	points_label.text = "%d/%d" % [int(S.total), S.target_points]
	ruin_label.text = "%d/%d" % [W.buildings.destroyed_count, W.damage_quota]
	if points_popup.visible:
		var lines := ""
		for src in S.SOURCES:
			lines += "%s: %d\n" % [src, int(S.by_source.get(src, 0.0))]
		lines += "Hari ini: +%d\n" % int(S.today)
		lines += "Total: %d / %d  (%d%%)" % [int(S.total), S.target_points, int(S.progress() * 100.0)]
		popup_lines.text = lines
	for i in 3:
		cards[i].set_stock(W.shovel)
	cards[3].set_stock(W.roads.bridge_stock)
	cards[4].set_stock(W.facilities.stock[W.facilities.Kind.BOR])
	cards[5].set_stock(W.facilities.stock[W.facilities.Kind.BENDUNGAN])
	cards[6].set_stock(W.facilities.stock[W.facilities.Kind.SPILLWAY])
	cards[7].set_stock(W.facilities.stock[W.facilities.Kind.KINCIR])
	_update_tooltip()

func _mouse_over_ui() -> bool:
	var vp := get_viewport()
	return vp.has_method("gui_get_hovered_control") and vp.gui_get_hovered_control() != null

func _update_tooltip() -> void:
	var cell: Vector2i = world.hover_cell
	if world.game_over or not world.hover_valid or _mouse_over_ui() or pause_menu.visible \
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
	var mp := get_viewport().get_mouse_position()
	var vs := get_viewport().get_visible_rect().size
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
