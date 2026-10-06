@tool
extends Button
## Kartu alat di panel aksi (scenes/ui/tool_card.tscn).
## Ikon, judul, dan tombol pintas diatur per kartu lewat Inspector; tampilan kartu
## (bingkai normal/hover/terpilih) memakai gambar di assets/placeholder/ui/.

@export var icon_texture: Texture2D:
	set(value):
		icon_texture = value
		_apply()
@export var title: String = "Alat":
	set(value):
		title = value
		_apply()
@export var hotkey: String = "1":
	set(value):
		hotkey = value
		_apply()
@export var show_title: bool = false:  ## tampilkan nama alat di kartu (default: nama muncul di tooltip saat hover, gaya Terra Nil)
	set(value):
		show_title = value
		_apply()
@export var show_stock: bool = false:  ## tampilkan lencana stok (untuk alat yang jumlahnya terbatas)
	set(value):
		show_stock = value
		_apply()

func _ready() -> void:
	_apply()

func _apply() -> void:
	if not is_node_ready():
		return
	$Icon.texture = icon_texture
	$Title.text = title
	$Title.visible = show_title
	$Hotkey.text = hotkey
	tooltip_text = "%s  [%s]" % [title, hotkey]
	$Stock.visible = show_stock

## Dipanggil HUD untuk memperbarui angka stok. Kartu meredup kalau stok habis.
func set_stock(n: int) -> void:
	$Stock.text = str(n)
	$Stock.visible = show_stock
	$Icon.modulate = Color(1, 1, 1) if n > 0 else Color(0.45, 0.45, 0.45)
	$Stock.modulate = Color(1, 1, 1) if n > 0 else Color(1, 0.75, 0.7)
