extends Node2D
## Kincir air (scenes/kincir.tscn). Berputar sesuai debit air yang melewati petaknya.
## Animasi ada di node Wheel (AnimatedSprite2D, animasi "putar");

@export var max_speed: float = 1.5
@export var base_fps: float = 8.0

@onready var wheel: Sprite2D = $Wheel

var power: float = 0.0
var flow_dir: int = 1
var _anim_timer: float = 0.0
var _frame_index: int = 0

# Mapping arah (0:TL, 1:TR, 2:BL, 3:BR) ke baris dasar varian (0:TR, 1:TL, 2:BL, 3:BR)
const DIR_MAP = {
	1: 0,
	0: 1,
	2: 2,
	3: 3
}

func set_power(p: float, dir: int = -1) -> void:
	power = p
	if dir >= 0:
		flow_dir = dir

func _process(delta: float) -> void:
	var base_row = DIR_MAP.get(flow_dir, 0) * 2
	var is_active = power >= 0.03
	var row = base_row + (1 if is_active else 0)

	if is_active:
		_anim_timer += delta * (power * max_speed * base_fps)
		if _anim_timer >= 1.0:
			_anim_timer = 0.0
			_frame_index = (_frame_index + 1) % 4

	wheel.frame = (row * 4) + _frame_index