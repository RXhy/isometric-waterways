extends Control
## Panel akhir permainan (menang / kalah). Dibangun dari gambar di assets/ui/Win & Lose.
## Posisi diukur dari Win_layout.png / Lose_layout.png (layar 640x360). Atur angka di Inspector
## scenes/ui/end_panel.tscn kalau ada yang kurang pas.

signal play_again
signal main_menu

const DIR := "res://assets/ui/Win & Lose/"
@export var asset_scale: float = 0.625            ## gambar dibuat untuk layar 1024 px -> 640 px
@export var panel_center := Vector2(320, 178)
@export var star_on: Texture2D = preload("res://assets/Icon/stars1.png")
@export var star_off: Texture2D = preload("res://assets/ui/Win & Lose/no_star.png")
@export var star_size: float = 28.0
@export var star_gap: float = 51.0
## y tiap elemen (layar 640x360): [judul, bintang, label hancur, tombol]
@export var win_rows := Vector4(115, 155, 192, 236)
@export var lose_rows := Vector4(120, 0, 172, 232)
@export var button_x := Vector2(236, 389)         ## x tengah tombol kiri (Play Again) & kanan (Main Menu)
@export var count_offset := Vector2(47, 0)        ## posisi angka di kotak "Building Destroyed" relatif ke tengah label
@export var count_font_size: int = 9

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	hide()

func _tex(n: String) -> Texture2D:
	return load(DIR + n + ".png")

func _add_rect(tex: Texture2D, center: Vector2, size := Vector2.ZERO) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size = size if size != Vector2.ZERO else tex.get_size() * asset_scale
	r.position = (center - r.size / 2.0).round()
	add_child(r)
	return r

func _add_button(normal: String, hover: String, center: Vector2) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = _tex(normal)
	b.texture_hover = _tex(hover)
	b.texture_pressed = _tex(hover)
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.size = b.texture_normal.get_size() * asset_scale
	b.position = (center - b.size / 2.0).round()
	add_child(b)
	return b

## won: menang/kalah, stars: 0-3, destroyed: jumlah bangunan hancur.
func open(won: bool, stars: int, destroyed: int) -> void:
	for c in get_children():
		c.queue_free()
	var rows: Vector4 = win_rows if won else lose_rows
	_add_rect(_tex("panel"), panel_center)
	_add_rect(_tex("COMPLETE" if won else "fail"), Vector2(panel_center.x, rows.x))
	if won:
		for i in 3:
			var cx := panel_center.x + (i - 1) * star_gap
			_add_rect(star_on if i < stars else star_off, Vector2(cx, rows.y), Vector2(star_size, star_size))
	var lbl_center := Vector2(panel_center.x, rows.z)
	_add_rect(_tex("Bld_destroyed_count"), lbl_center)
	var n := Label.new()
	n.text = str(destroyed)
	n.add_theme_font_size_override("font_size", count_font_size)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	n.size = Vector2(20, 14)
	n.position = (lbl_center + count_offset - n.size / 2.0).round()
	add_child(n)
	_add_button("play again_non_hover", "play again_hover", Vector2(button_x.x, rows.w)).pressed.connect(func(): play_again.emit())
	_add_button("mainmenu_non_hover", "mainmenu_hover", Vector2(button_x.y, rows.w)).pressed.connect(func(): main_menu.emit())
	show()
