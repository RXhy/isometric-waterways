extends Control
## Menu utama. Tampilan ada di scene (scenes/main_menu*.tscn); script ini hanya mengatur alur.
## Node penting dicari lewat nama unik (%NewGame, %Menu, ...), jadi tiap varian layout
## bebas menata posisinya sendiri asalkan nama unik itu ada.
## Latar: scenes/menu_map.tscn (peta diorama khusus menu).

const GAME_SCENE := "res://world.tscn"

## Geser pandangan kamera (px, + = pulau bergeser ke kiri) supaya pulau tidak tertutup UI varian ini.
## 0 = posisi bawaan menu_map (pulau di tengah area kanan, untuk panel kiri).
@export var map_shift: float = 0.0

@onready var btn_new: Button = %NewGame
@onready var btn_load: Button = %LoadGame
@onready var btn_tutorial: Button = %Tutorial
@onready var btn_exit: Button = %Exit
@onready var tutorial_panel: Control = %TutorialPanel
@onready var exit_dialog: Control = %ExitDialog
@onready var fade: ColorRect = %Fade

func _ready() -> void:
	btn_new.pressed.connect(_on_new_game)
	btn_load.pressed.connect(_on_load_game)
	btn_tutorial.pressed.connect(func(): _open(tutorial_panel))
	btn_exit.pressed.connect(func(): _open(exit_dialog))
	%TutorialPanel/VBox/Close.pressed.connect(_close_dialogs)
	%ExitDialog/VBox/Buttons/Yes.pressed.connect(func(): get_tree().quit())
	%ExitDialog/VBox/Buttons/No.pressed.connect(_close_dialogs)
	# Load Game belum aktif sampai sistem simpan dibuat
	btn_load.disabled = true
	Engine.time_scale = 1.0
	var cam := get_node_or_null("Background/Camera2D") as Camera2D
	if cam:
		cam.offset.x = map_shift
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
	%Menu.modulate.a = 0.4

func _close_dialogs() -> void:
	tutorial_panel.hide()
	exit_dialog.hide()
	%Menu.modulate.a = 1.0
	btn_new.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and (tutorial_panel.visible or exit_dialog.visible):
		_close_dialogs()
