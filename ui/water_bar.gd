extends Control
## Loading bar bergaya aliran air game: kanal batu yang terisi air mengalir dari kiri ke kanan.
## Gambar kilau memakai assets/Tiles/waterflow.png (sama seperti air di game). Dipakai scenes/loading.tscn.

@export_range(0.0, 100.0) var value: float = 0.0:
	set(v):
		value = v
		queue_redraw()
@export var flow_speed: float = 40.0     ## kecepatan gerak air ke kanan (px/detik)
@export var sparkle_fps: float = 4.0     ## kecepatan animasi kilau (sama dengan waterflow_fps di game)
@export var bank_color := Color(0.36, 0.24, 0.2)      ## tepi kanal
@export var bank_light := Color(0.52, 0.38, 0.3)
@export var bed_color := Color(0.16, 0.12, 0.12)      ## dasar kanal yang masih kering
@export var water_color := Color(0.22, 0.47, 0.66)
@export var water_light := Color(0.3, 0.62, 0.84)
@export var foam_color := Color(0.85, 0.95, 1.0)
@export var bank_width: int = 2

var _tex: Texture2D = preload("res://assets/Tiles/waterflow.png")
var _t := 0.0

func _ready() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	var b := float(bank_width)
	draw_rect(Rect2(0, 0, w, h), bank_color)
	draw_rect(Rect2(0, 0, w, 1), bank_light)
	var inner := Rect2(b, b, w - b * 2.0, h - b * 2.0)
	draw_rect(inner, bed_color)
	var fill := inner.size.x * clampf(value / 100.0, 0.0, 1.0)
	if fill < 1.0:
		return
	var water := Rect2(inner.position, Vector2(fill, inner.size.y))
	draw_rect(water, water_color)
	draw_rect(Rect2(water.position, Vector2(fill, 2)), water_light)
	# garis arus bergerak ke kanan
	var off := fmod(_t * flow_speed, 22.0)
	for row in 3:
		var y := water.position.y + 2.0 + row * 2.0
		if y + 1.0 > water.end.y:
			break
		var x := water.position.x - 22.0 + fmod(off + row * 8.0, 22.0)
		while x < water.end.x:
			var x0 := maxf(x, water.position.x)
			var x1 := minf(x + 7.0, water.end.x)
			if x1 > x0:
				draw_rect(Rect2(x0, y, x1 - x0, 1), water_light.lightened(0.15))
			x += 22.0
	# kilau dari waterflow.png (4 frame), ikut bergerak ke kanan
	var frame := int(_t * sparkle_fps) % 4
	var shift := fmod(_t * flow_speed * 0.6, 32.0)
	var i := 0
	var x := water.position.x - 32.0 + shift
	while x < water.end.x:
		var row := (i * 11 + 5) % 100
		var x0 := maxf(x, water.position.x)
		var x1 := minf(x + 32.0, water.end.x)
		if x1 > x0:
			var src := Rect2(frame * 32 + (x0 - x), row * 32 + 10, x1 - x0, minf(water.size.y, 12.0))
			draw_texture_rect_region(_tex, Rect2(x0, water.position.y, x1 - x0, src.size.y), src)
		x += 32.0
		i += 1
	# busa di ujung air
	draw_rect(Rect2(water.end.x - 2.0, water.position.y, 2, water.size.y), foam_color)
