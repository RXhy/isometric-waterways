extends Node2D
## Satu bangunan (Rumah / Ladang). Tampilan ada di scenes/building.tscn;
## script ini hanya mengatur data air/banjir dan menyalakan/mematikan node.

enum Type { RUMAH, LADANG }
enum State { HIDUP, TERANCAM, HANCUR }

const TYPE_DATA := {
	Type.RUMAH: {"name": "Rumah", "max_water": 40.0},
	Type.LADANG: {"name": "Ladang", "max_water": 28.0},
}
const THREAT_RATIO := 0.4   # di bawah 40% cadangan air -> Terancam
const REFILL_RATE := 4.0    # isi ulang 4x lebih cepat daripada berkurangnya

@export var flood_limit: float = 6.0  ## detik tergenang banjir sampai bangunan tenggelam

@onready var rumah: Sprite2D = $Rumah
@onready var ladang: Sprite2D = $Ladang
@onready var ruin: Sprite2D = $Reruntuhan
@onready var bar: Node2D = $Bar
@onready var fill: ColorRect = $Bar/Fill
@onready var fill_low: ColorRect = $Bar/FillLow
@onready var warning: Sprite2D = $Peringatan

var cell: Vector2i
var type: int = Type.RUMAH
var max_water: float = 40.0
var water: float = 40.0
var flood_time: float = 0.0
var state: int = State.HIDUP
var _time := 0.0
var _bar_width := 22.0

func setup(c: Vector2i, t: int) -> void:
	cell = c
	type = t
	max_water = TYPE_DATA[t]["max_water"]
	water = max_water

func _ready() -> void:
	_bar_width = fill.size.x
	_refresh()

## Dipanggil tiap frame oleh BuildingManager. Mengembalikan true kalau baru saja hancur.
func tick(delta: float, supplied: bool, flooded: bool = false) -> bool:
	if state == State.HANCUR:
		return false
	_time += delta
	if supplied:
		water = min(max_water, water + delta * REFILL_RATE)
	else:
		water = max(0.0, water - delta)
	flood_time = flood_time + delta if flooded else max(0.0, flood_time - delta)

	if water <= 0.0 or flood_time >= flood_limit:
		state = State.HANCUR
	elif water / max_water < THREAT_RATIO or flood_time > 0.0:
		state = State.TERANCAM
	else:
		state = State.HIDUP
	_refresh()
	return state == State.HANCUR

func _refresh() -> void:
	var alive := state != State.HANCUR
	rumah.visible = alive and type == Type.RUMAH
	ladang.visible = alive and type == Type.LADANG
	ruin.visible = not alive
	bar.visible = alive
	var ratio := water / max_water
	fill.size.x = _bar_width * ratio
	fill_low.size.x = _bar_width * ratio
	fill.visible = state == State.HIDUP
	fill_low.visible = state == State.TERANCAM
	warning.visible = state == State.TERANCAM and int(_time * 4.0) % 2 == 0
