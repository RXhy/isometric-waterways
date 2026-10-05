extends Node2D
## Kincir air (scenes/kincir.tscn). Berputar sesuai debit air yang melewati petaknya.
## Animasi ada di node Wheel (AnimatedSprite2D, animasi "putar"); ganti frame-nya
## di SpriteFrames lewat Inspector saat aset final dari artist sudah ada.

@export var max_speed: float = 1.5      ## kecepatan animasi saat debit penuh (1 = fps asli)
@export var idle_tint: Color = Color(0.7, 0.7, 0.7)  ## warna saat kincir diam (tidak ada aliran)

@onready var wheel: AnimatedSprite2D = $Wheel

var power: float = 0.0

func set_power(p: float) -> void:
	power = p
	if p < 0.03:
		wheel.pause()
		wheel.modulate = idle_tint
	else:
		if not wheel.is_playing():
			wheel.play("putar")
		wheel.speed_scale = p * max_speed
		wheel.modulate = Color(1, 1, 1)
