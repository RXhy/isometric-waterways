extends Button
## Satu baris menu utama gaya "panel gelap" (scenes/ui/menu_item_dark.tscn).
## Teks bisa berupa gambar dari artist (label_texture, mis. assets/ui/NEW GAME.png);
## kalau kosong, dipakai teks biasa (properti text).
## Saat disorot / fokus: bar (assets/ui/Rectangle 3.png) + panah (assets/ui/Polygon 1.png).

## Gambar teks tombol. Ukuran tampil = setengah ukuran gambar (aset dibuat untuk layar 1280x720,
## game memakai viewport 640x360).
@export var label_texture: Texture2D:
	set(value):
		label_texture = value
		_apply()

@onready var arrow: Control = $Arrow
@onready var text_img: TextureRect = $TextImage

func _ready() -> void:
	_apply()
	arrow.visible = false
	mouse_entered.connect(_hl.bind(true))
	mouse_exited.connect(func(): _hl(has_focus()))
	focus_entered.connect(_hl.bind(true))
	focus_exited.connect(_hl.bind(false))

func _apply() -> void:
	if not is_node_ready():
		return
	text_img.texture = label_texture
	text_img.visible = label_texture != null
	if label_texture:
		var sz: Vector2 = label_texture.get_size() * 0.5
		text_img.size = sz
		text_img.position = Vector2(get_theme_stylebox("normal").content_margin_left, (size.y - sz.y) / 2.0)
		add_theme_color_override("font_color", Color(0, 0, 0, 0))
		add_theme_color_override("font_hover_color", Color(0, 0, 0, 0))
		add_theme_color_override("font_focus_color", Color(0, 0, 0, 0))
		add_theme_color_override("font_pressed_color", Color(0, 0, 0, 0))
		add_theme_color_override("font_hover_pressed_color", Color(0, 0, 0, 0))
		add_theme_color_override("font_disabled_color", Color(0, 0, 0, 0))
	text_img.modulate = Color(0.55, 0.55, 0.55) if disabled else Color.WHITE

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready() and label_texture:
		text_img.position.y = (size.y - text_img.size.y) / 2.0

func _hl(on: bool) -> void:
	arrow.visible = on and not disabled
	if on and not disabled and not has_focus():
		grab_focus()  # hanya satu baris yang tersorot (mouse & keyboard sama)
