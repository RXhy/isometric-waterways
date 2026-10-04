extends TileMapLayer
## Lapisan informasi di atas peta (tombol "Lapisan" di HUD):
##   Ketinggian    : warna per tingkat elevasi (0 hijau tua .. 3 jingga)
##   Kedalaman air : biru muda (dangkal) .. biru tua (dalam), diperbarui terus
## Warna ada di assets/placeholder/overlay_tiles.png (indeks 0-3 ketinggian, 4-7 air).

enum Mode { MATI, KETINGGIAN, AIR }
const NAMES := ["Mati", "Ketinggian", "Kedalaman air"]

@export var refresh_interval: float = 0.25  ## detik antar pembaruan mode kedalaman air

var world
var mode: int = Mode.MATI
var _t := 0.0

func setup(w) -> void:
	world = w
	redraw()

func cycle() -> void:
	mode = (mode + 1) % 3
	redraw()

func _process(delta: float) -> void:
	if mode != Mode.AIR:
		return
	_t += delta
	if _t >= refresh_interval:
		_t = 0.0
		redraw()

func redraw() -> void:
	clear()
	if mode == Mode.MATI or world == null:
		return
	for c in world.water.cells:
		var h: int = world.get_elev(c)
		if mode == Mode.KETINGGIAN:
			set_cell(c, 0, Vector2i(h, 0), h)
		else:
			var d: float = world.water.get_depth(c)
			if d < 0.02:
				continue
			set_cell(c, 0, Vector2i(4 + clampi(int(d / 0.2), 0, 3), 0), h)
