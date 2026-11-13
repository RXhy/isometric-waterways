extends Control
## Menu utama. Tampilan ada di scene (scenes/main_menu*.tscn); script ini hanya mengatur alur.
## Node penting dicari lewat nama unik (%NewGame, %Menu, ...).
## Latar: scenes/menu_map.tscn (peta diorama khusus menu).

const GAME_SCENE := "res://scenes/loading.tscn"
const TUTORIAL_SCENE := preload("res://scenes/ui/tutorial.tscn")

## Geser pandangan kamera (px, + = pulau bergeser ke kiri) supaya pulau tidak tertutup UI varian ini.
## 0 = posisi bawaan menu_map (pulau di tengah area kanan, untuk panel kiri).
@export var map_shift: float = 0.0

@onready var btn_new: Button = %NewGame
@onready var btn_load: Button = %LoadGame
@onready var btn_tutorial: Button = %Tutorial
@onready var btn_exit: Button = %Exit
@onready var exit_dialog: Control = %ExitDialog
@onready var fade: ColorRect = %Fade
var tutorial: Control

func _ready() -> void:
	btn_new.pressed.connect(_on_new_game)
	btn_load.pressed.connect(_on_load_game)
	tutorial = TUTORIAL_SCENE.instantiate()
	$UI.add_child(tutorial)
	$UI.move_child(tutorial, %Fade.get_index())  # di bawah layar fade
	tutorial.closed.connect(_close_dialogs)
	btn_tutorial.pressed.connect(func():
		_open(tutorial)
		tutorial.open())
	btn_exit.pressed.connect(func(): _open(exit_dialog))
	%ExitDialog/VBox/Buttons/Yes.pressed.connect(func(): get_tree().quit())
	%ExitDialog/VBox/Buttons/No.pressed.connect(_close_dialogs)
	# Load Game belum aktif sampai sistem simpan dibuat
	btn_load.disabled = true
	Engine.time_scale = 1.0
	Audio.play_music(Audio.bgm_menu)
	var cam := get_node_or_null("Background/Camera2D") as Camera2D
	if cam:
		cam.offset.x = map_shift
	_close_dialogs()
	_build_survey_panel()
	fade.color.a = 1.0
	create_tween().tween_property(fade, "color:a", 0.0, 0.6)

func _on_new_game() -> void:
	fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var t := create_tween()
	t.tween_property(fade, "color:a", 1.0, 0.2)
	t.tween_callback(func(): get_tree().change_scene_to_file(GAME_SCENE))

func _on_load_game() -> void:
	pass  # belum ada sistem simpan/muat

func _open(dialog: Control) -> void:
	_close_dialogs()
	dialog.show()
	%Menu.modulate.a = 0.4

func _close_dialogs() -> void:
	tutorial.hide()
	exit_dialog.hide()
	%Menu.modulate.a = 1.0
	btn_new.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and exit_dialog.visible:
		_close_dialogs()

# --- Mode Survei (lihat survey/survey_mode.gd) ---

## Pojok kanan bawah: tombol MODE SURVEI, atau panel status pemain kalau sesi survei sedang berjalan.
func _build_survey_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "SurveyPanel"
	panel.theme = Survey.make_theme()
	panel.add_theme_stylebox_override("panel", Survey._box(Color(Survey.C_BG, 0.92), Survey.C_YELLOW if Survey.active else Color(1, 1, 1, 0.3), 1, 6))
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -8
	panel.offset_bottom = -8
	$UI.add_child(panel)
	$UI.move_child(panel, %Fade.get_index())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	if not Survey.active:
		var b := Button.new()
		b.text = "MODE SURVEI  (playtest)"
		b.pressed.connect(Survey.open_profile)
		v.add_child(b)
		return
	var title := Label.new()
	title.text = "MODE SURVEI · %s · %s" % [Survey.player.get("id", ""), Survey.player.get("nama", "")]
	title.add_theme_color_override("font_color", Survey.C_YELLOW)
	v.add_child(title)
	var info := Label.new()
	var n := Survey.finished_count()
	info.text = ("Permainan selesai: %d" % n) if n > 0 else "Buka TUTORIAL dulu (opsional), lalu Mulai Main."
	info.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	v.add_child(info)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	v.add_child(h)
	var play := Button.new()
	play.text = "Mulai Main" if n == 0 else "Main Lagi"
	play.pressed.connect(_on_new_game)
	h.add_child(play)
	var form := Button.new()
	form.text = "Isi Survei"
	form.disabled = not Survey.can_fill_survey()
	form.tooltip_text = "Bisa diisi setelah minimal 1 permainan selesai (menang/kalah)."
	form.pressed.connect(Survey.open_form)
	h.add_child(form)
	var cancel := Button.new()
	cancel.text = "Batalkan"
	cancel.tooltip_text = "Batalkan sesi pemain ini tanpa mengisi survei."
	cancel.pressed.connect(func():
		if cancel.get_meta("armed", false):
			Survey.cancel()
			get_tree().reload_current_scene()
		else:
			cancel.set_meta("armed", true)
			cancel.text = "Yakin batal?")
	h.add_child(cancel)
