extends Control
## Menu utama bergaya Mini Motorways: panel menu minimalis di kiri,
## peta game yang hidup (world.tscn dalam mode demo) di belakangnya.
## Semua tampilan ada di scenes/main_menu.tscn; script ini hanya mengatur alur.

const GAME_SCENE := "res://world.tscn"

@onready var btn_new: Button = $UI/LeftPanel/Menu/NewGame
@onready var btn_load: Button = $UI/LeftPanel/Menu/LoadGame
@onready var btn_tutorial: Button = $UI/LeftPanel/Menu/Tutorial
@onready var btn_exit: Button = $UI/LeftPanel/Menu/Exit
@onready var tutorial_panel: Control = $UI/TutorialPanel
@onready var exit_dialog: Control = $UI/ExitDialog
@onready var fade: ColorRect = $UI/Fade

func _ready() -> void:
	btn_new.pressed.connect(_on_new_game)
	btn_load.pressed.connect(_on_load_game)
	btn_tutorial.pressed.connect(func(): _open(tutorial_panel))
	btn_exit.pressed.connect(func(): _open(exit_dialog))
	$UI/TutorialPanel/VBox/Close.pressed.connect(_close_dialogs)
	$UI/ExitDialog/VBox/Buttons/Yes.pressed.connect(func(): get_tree().quit())
	$UI/ExitDialog/VBox/Buttons/No.pressed.connect(_close_dialogs)
	# Load Game belum aktif sampai sistem simpan dibuat
	btn_load.disabled = true
	Engine.time_scale = 1.0
	_close_dialogs()
	fade.color.a = 1.0
	create_tween().tween_property(fade, "color:a", 0.0, 0.6)

func _on_new_game() -> void:
	fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var t := create_tween()
	t.tween_property(fade, "color:a", 1.0, 0.4)
	t.tween_callback(func(): get_tree().change_scene_to_file(GAME_SCENE))

func _on_load_game() -> void:
	pass  # TODO: sistem simpan/muat

func _open(dialog: Control) -> void:
	_close_dialogs()
	dialog.show()
	$UI/LeftPanel/Menu.modulate.a = 0.4

func _close_dialogs() -> void:
	tutorial_panel.hide()
	exit_dialog.hide()
	$UI/LeftPanel/Menu.modulate.a = 1.0
	btn_new.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and (tutorial_panel.visible or exit_dialog.visible):
		_close_dialogs()
