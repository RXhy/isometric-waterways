extends Button
## Satu baris menu utama gaya "panel gelap" (scenes/ui/menu_item_dark.tscn).
## Saat disorot / fokus: bar abu-abu transparan + panah putih di kiri teks (lihat main UI.jpeg).

@onready var arrow: Control = $Arrow

func _ready() -> void:
	arrow.visible = false
	mouse_entered.connect(_hl.bind(true))
	mouse_exited.connect(func(): _hl(has_focus()))
	focus_entered.connect(_hl.bind(true))
	focus_exited.connect(_hl.bind(false))

func _hl(on: bool) -> void:
	arrow.visible = on and not disabled
	if on and not disabled and not has_focus():
		grab_focus()  # hanya satu baris yang tersorot (mouse & keyboard sama)
