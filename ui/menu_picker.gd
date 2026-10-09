extends Control
## Layar DEBUG pemilih layout main menu (scenes/debug/menu_picker.tscn), muncul paling awal
## saat game dijalankan dari editor. Pilihan terakhir diingat dan disorot.
## Di build release (export) layar ini dilewati: langsung ke varian tersimpan / default.
## Tombol: klik kartu atau tekan 1 / 2 / 3, Enter = pakai pilihan yang disorot.

@onready var cards: Array = [$UI/Center/VBox/Cards/A, $UI/Center/VBox/Cards/B, $UI/Center/VBox/Cards/C]

var _selected := 0

func _ready() -> void:
	if not OS.is_debug_build():
		get_tree().change_scene_to_file.call_deferred(MenuChoice.scene_path())
		return
	_selected = MenuChoice.saved_index()
	var cam := get_node_or_null("Map/Camera2D") as Camera2D
	if cam:
		cam.offset.x = 107.0  # pulau di tengah layar
	for i in cards.size():
		var v: Dictionary = MenuChoice.VARIANTS[i]
		var card: Button = cards[i]
		card.get_node("VBox/Thumb").texture = load(v["thumb"])
		card.get_node("VBox/Name").text = "%d.  %s" % [i + 1, v["name"]]
		card.get_node("VBox/Desc").text = v["desc"]
		card.pressed.connect(_open.bind(i))
		card.mouse_entered.connect(_highlight.bind(i))
	_highlight(_selected)

func _highlight(i: int) -> void:
	_selected = i
	for k in cards.size():
		cards[k].set_pressed_no_signal(k == i)

func _open(i: int) -> void:
	MenuChoice.choose(i)
	get_tree().change_scene_to_file(MenuChoice.scene_path())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1: _open(0)
			KEY_2: _open(1)
			KEY_3: _open(2)
			KEY_ENTER, KEY_KP_ENTER: _open(_selected)
			KEY_LEFT: _highlight(maxi(_selected - 1, 0))
			KEY_RIGHT: _highlight(mini(_selected + 1, cards.size() - 1))
