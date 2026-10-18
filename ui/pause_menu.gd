extends Control
## Menu opsi in-game (scenes/ui/pause_menu.tscn): dibuka lewat tombol roda gigi di kanan atas atau Esc.
## Game dijeda selama menu terbuka; kecepatan sebelumnya dikembalikan saat ditutup.

@onready var main_list: Control = $Panel/VBox/Main
@onready var settings_list: Control = $Panel/VBox/Settings
@onready var title: Label = $Panel/VBox/Title
@onready var vol_master: HSlider = $Panel/VBox/Settings/Master/Slider
@onready var vol_music: HSlider = $Panel/VBox/Settings/Music/Slider
@onready var vol_sfx: HSlider = $Panel/VBox/Settings/SFX/Slider
@onready var fullscreen: CheckButton = $Panel/VBox/Settings/Fullscreen
@onready var tooltips: CheckButton = $Panel/VBox/Settings/Tooltips

var world
var _prev_speed: float = 1.0
var tutorial: Control

func setup(w) -> void:
	world = w
	hide()
	$Panel/VBox/Main/Resume.pressed.connect(close)
	$Panel/VBox/Main/Restart.pressed.connect(_restart)
	$Panel/VBox/Main/Options.pressed.connect(_show_settings)
	$Panel/VBox/Main/MainMenu.pressed.connect(_to_menu)
	$Panel/VBox/Settings/Back.pressed.connect(_show_main)
	# tombol sembunyikan UI (dibuat di kode supaya scene menu tidak perlu diubah)
	var hide_ui: Button = $Panel/VBox/Main/Options.duplicate(0)  # salin gaya tombol, tanpa sinyal
	hide_ui.name = "HideUI"
	hide_ui.text = "Hide UI (H)"
	main_list.add_child(hide_ui)
	main_list.move_child(hide_ui, $Panel/VBox/Main/Options.get_index() + 1)
	hide_ui.pressed.connect(func():
		close()
		world.hud.set_ui_hidden(true))
	# tombol tutorial (halaman tutorial ditaruh di layer HUD supaya ukurannya penuh)
	var tut_btn: Button = $Panel/VBox/Main/Options.duplicate(0)
	tut_btn.name = "Tutorial"
	tut_btn.text = "Tutorial"
	main_list.add_child(tut_btn)
	main_list.move_child(tut_btn, $Panel/VBox/Main/Resume.get_index() + 1)
	tutorial = preload("res://scenes/ui/tutorial.tscn").instantiate()
	tutorial.hide()
	world.hud.add_child.call_deferred(tutorial)
	tut_btn.pressed.connect(func(): tutorial.open())
	vol_master.value = GameSettings.get_value("vol_master")
	vol_music.value = GameSettings.get_value("vol_music")
	vol_sfx.value = GameSettings.get_value("vol_sfx")
	fullscreen.button_pressed = DisplayServer.window_get_mode() >= DisplayServer.WINDOW_MODE_FULLSCREEN
	tooltips.button_pressed = GameSettings.get_value("tooltips")
	vol_master.value_changed.connect(func(v): GameSettings.set_value("vol_master", v))
	vol_music.value_changed.connect(func(v): GameSettings.set_value("vol_music", v))
	vol_sfx.value_changed.connect(func(v): GameSettings.set_value("vol_sfx", v))
	fullscreen.toggled.connect(func(on): GameSettings.set_value("fullscreen", on))
	tooltips.toggled.connect(func(on): GameSettings.set_value("tooltips", on))

func open() -> void:
	if visible:
		return
	world.cancel_drag()
	_prev_speed = Engine.time_scale
	Engine.time_scale = 0.0
	_show_main()
	show()

func close() -> void:
	if not visible:
		return
	hide()
	world.hud.set_speed(_prev_speed)

## Esc: dari Pengaturan kembali ke daftar utama, dari daftar utama menutup menu.
func back() -> void:
	if settings_list.visible:
		_show_main()
	else:
		close()

func _show_main() -> void:
	title.text = "Paused"
	main_list.show()
	settings_list.hide()

func _show_settings() -> void:
	title.text = "Settings"
	main_list.hide()
	settings_list.show()

func _restart() -> void:
	world.balance_log.log_end("DITINGGALKAN", "main ulang")
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()

func _to_menu() -> void:
	world.balance_log.log_end("DITINGGALKAN", "kembali ke menu")
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(world.MENU_SCENE)
