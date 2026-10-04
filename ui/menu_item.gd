@tool
extends Button
## Satu baris menu utama (scenes/ui/menu_item.tscn).
## Saat disorot, garis "aliran air" (node Marker) memanjang di sebelah kiri teks.

@export var label: String = "Menu":
	set(value):
		label = value
		_apply()
@export var caption: String = "":  ## keterangan kecil di bawah teks (opsional)
	set(value):
		caption = value
		_apply()

var _tween: Tween

func _ready() -> void:
	_apply()
	if Engine.is_editor_hint():
		return
	$Marker.scale.x = 0.0
	mouse_entered.connect(_flow.bind(true))
	mouse_exited.connect(_flow.bind(false))
	focus_entered.connect(_flow.bind(true))
	focus_exited.connect(_flow.bind(false))

func _apply() -> void:
	if not is_node_ready():
		return
	text = label
	$Caption.text = caption
	$Caption.visible = caption != ""

func _flow(on: bool) -> void:
	if disabled:
		return
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property($Marker, "scale:x", 1.0 if on else 0.0, 0.25)
