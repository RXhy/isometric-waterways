extends Node2D
## Satu bangunan (Rumah / Ladang). Tampilan ada di scenes/building.tscn;
## script ini hanya mengatur data air/banjir dan menyalakan/mematikan node.

enum Type { RUMAH, LADANG }
enum State { HIDUP, TERANCAM, HANCUR }

const TYPE_DATA := {
	Type.RUMAH: {"name": "House", "max_water": 40.0},
	Type.LADANG: {"name": "Farm", "max_water": 28.0},
}
const THREAT_RATIO := 0.4   # di bawah 40% cadangan air -> Terancam
const REFILL_RATE := 4.0    # isi ulang 4x lebih cepat daripada berkurangnya

@export var flood_limit: float = 6.0  ## detik tergenang banjir sampai bangunan tenggelam
## Sprite rumah (assets/placeholder/building.png, 8 frame) dan ladang (farm.png, 8 frame): satu varian dipakai.
## Rumah: frame `house_frame` = pintu menghadap kanan-bawah; dibalik (flip) untuk menghadap kiri-bawah.
@export var house_frame: int = 1
@export var farm_frame: int = 4

@onready var rumah: Sprite2D = $Rumah
@onready var ladang: Sprite2D = $Ladang
@onready var ruin: Sprite2D = $Reruntuhan
@onready var ring: TextureProgressBar = $Ring
@onready var warning: Sprite2D = $Peringatan

## Warna cincin timer air: aman / terancam / hampir habis (bisa diubah di Inspector)
@export var ring_ok: Color = Color(0.3, 0.65, 1.0)
@export var ring_warn: Color = Color(1.0, 0.62, 0.15)
@export var ring_danger: Color = Color(0.9, 0.2, 0.2)

var cell: Vector2i
var _face_check := 0.0
var type: int = Type.RUMAH
var max_water: float = 40.0
var water: float = 40.0
var flood_time: float = 0.0
var state: int = State.HIDUP
var has_water: bool = false  ## hasil tick terakhir: sedang mendapat air? (untuk panel Aliran Air)
var _time := 0.0

func setup(c: Vector2i, t: int) -> void:
	cell = c
	type = t
	max_water = TYPE_DATA[t]["max_water"]
	water = max_water

func _ready() -> void:
	_refresh()

## Dipanggil tiap frame oleh BuildingManager. Mengembalikan true kalau baru saja hancur.
func tick(delta: float, supplied: bool, flooded: bool = false) -> bool:
	if state == State.HANCUR:
		return false
	_time += delta
	has_water = supplied
	if supplied:
		water = min(max_water, water + delta * REFILL_RATE)
	else:
		water = max(0.0, water - delta)
	flood_time = flood_time + delta if flooded else max(0.0, flood_time - delta)

	if water <= 0.0 or flood_time >= flood_limit:
		state = State.HANCUR
	elif water / max_water < THREAT_RATIO or flood_time > 0.0:
		if state == State.HIDUP:
			Audio.play("bld_warning")  # baru saja terancam
		state = State.TERANCAM
	else:
		state = State.HIDUP
	_refresh()
	return state == State.HANCUR

func _refresh() -> void:
	var alive := state != State.HANCUR
	if _time >= _face_check:
		_face_check = _time + 0.5
		_update_facing()
	rumah.visible = alive and type == Type.RUMAH
	ladang.visible = alive and type == Type.LADANG
	ruin.visible = not alive
	ring.visible = alive
	var ratio := water / max_water
	ring.value = ratio
	if state == State.HIDUP:
		ring.tint_progress = ring_ok
	else:
		ring.tint_progress = ring_danger if ratio < 0.2 or flood_time > 0.0 else ring_warn
	# tanda seru berkedip di tengah cincin saat terancam (kekeringan atau banjir)
	warning.visible = state == State.TERANCAM and int(_time * 4.0) % 2 == 0

## Rumah menghadap jalan di sebelahnya (atau kanal, kalau belum ada jalan).
## Sumbu kiri-atas/kanan-bawah -> menghadap kanan-bawah; sumbu kanan-atas/kiri-bawah -> menghadap kiri-bawah.
func _update_facing() -> void:
	rumah.frame = house_frame
	ladang.frame = farm_frame
	var w = get_parent().world if get_parent() and "world" in get_parent() else null
	if w == null:
		return
	var sides := [TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE,
		TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE]
	for pass_i in 2:
		for i in 4:
			var n: Vector2i = w.world.get_neighbor_cell(cell, sides[i])
			var hit: bool = w.roads.is_road(n) if pass_i == 0 else w.water.is_channel(n)
			if hit:
				rumah.flip_h = i == 1 or i == 3  # kiri-bawah / kanan-atas
				return
