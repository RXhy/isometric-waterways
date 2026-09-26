extends Node2D
## Satu bangunan (Rumah / Ladang). Gambar masih placeholder via _draw();
## nanti bisa diganti Sprite2D tanpa mengubah logika air.

enum Type { RUMAH, LADANG }
enum State { HIDUP, TERANCAM, HANCUR }

const TYPE_DATA := {
	Type.RUMAH: {"name": "Rumah", "max_water": 40.0, "color": Color(0.86, 0.46, 0.32), "height": 14.0},
	Type.LADANG: {"name": "Ladang", "max_water": 28.0, "color": Color(0.93, 0.82, 0.30), "height": 3.0},
}
const THREAT_RATIO := 0.4   # di bawah 40% cadangan air -> Terancam
const REFILL_RATE := 4.0    # isi ulang 4x lebih cepat daripada berkurangnya

var cell: Vector2i
var type: int = Type.RUMAH
var max_water: float = 40.0
var water: float = 40.0
var state: int = State.HIDUP
var _time := 0.0

func setup(c: Vector2i, t: int) -> void:
	cell = c
	type = t
	max_water = TYPE_DATA[t]["max_water"]
	water = max_water

## Dipanggil tiap frame oleh BuildingManager. Mengembalikan true kalau baru saja hancur.
func tick(delta: float, supplied: bool) -> bool:
	if state == State.HANCUR:
		return false
	_time += delta
	if supplied:
		water = min(max_water, water + delta * REFILL_RATE)
	else:
		water = max(0.0, water - delta)

	if water <= 0.0:
		state = State.HANCUR
	elif water / max_water < THREAT_RATIO:
		state = State.TERANCAM
	else:
		state = State.HIDUP
	queue_redraw()
	return state == State.HANCUR

func _draw() -> void:
	var hw := 11.0  # setengah lebar tapak
	var hh := 5.5   # setengah tinggi tapak
	var h: float = TYPE_DATA[type]["height"]
	var col: Color = TYPE_DATA[type]["color"]

	if state == State.HANCUR:
		h = 2.0
		col = Color(0.32, 0.30, 0.30)
	elif state == State.TERANCAM:
		col = col.lerp(Color(0.55, 0.52, 0.48), 0.55)

	var top := PackedVector2Array([Vector2(0, -hh - h), Vector2(hw, -h), Vector2(0, hh - h), Vector2(-hw, -h)])
	var left := PackedVector2Array([Vector2(-hw, -h), Vector2(0, hh - h), Vector2(0, hh), Vector2(-hw, 0)])
	var right := PackedVector2Array([Vector2(0, hh - h), Vector2(hw, -h), Vector2(hw, 0), Vector2(0, hh)])
	draw_colored_polygon(left, col.darkened(0.35))
	draw_colored_polygon(right, col.darkened(0.18))
	draw_colored_polygon(top, col)
	var outline := top.duplicate()
	outline.append(top[0])
	draw_polyline(outline, Color(0, 0, 0, 0.55), 1.0)

	if state == State.HANCUR:
		draw_line(Vector2(-5, -h - 3), Vector2(5, -h + 3), Color(0.1, 0.1, 0.1), 1.5)
		draw_line(Vector2(-5, -h + 3), Vector2(5, -h - 3), Color(0.1, 0.1, 0.1), 1.5)
		return

	# Bar cadangan air
	var bar_y := -h - hh - 7.0
	var ratio := water / max_water
	draw_rect(Rect2(-12, bar_y, 24, 4), Color(0, 0, 0, 0.75))
	var fill := Color(0.30, 0.65, 1.0) if state == State.HIDUP else Color(1.0, 0.55, 0.15)
	draw_rect(Rect2(-11, bar_y + 1, 22.0 * ratio, 2), fill)

	# Tanda peringatan berkedip saat Terancam
	if state == State.TERANCAM and int(_time * 4.0) % 2 == 0:
		draw_circle(Vector2(0, bar_y - 6), 3.5, Color(0.95, 0.15, 0.15))
