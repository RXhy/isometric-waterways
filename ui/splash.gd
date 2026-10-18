extends Control
## Boot splash WATERWAYS (scenes/splash.tscn): layar pembuka sebelum main menu.
## Urutan: tetes air jatuh -> riak isometrik -> logo "terisi air" dari bawah ke atas -> tagline -> masuk menu.
## Klik / tombol apa saja = lewati. Semua waktu & warna bisa diatur di Inspector node Splash.

@export_file("*.tscn") var next_scene := "res://scenes/main_menu.tscn"
@export var logo: Texture2D = preload("res://assets/ui/Main Menu/logo_fiks_hd-export-export.png")
@export_group("Waktu (detik)")
@export var drop_times := PackedFloat32Array([0.5, 0.95, 1.3])  ## kapan tiap tetes jatuh
@export var drop_fall_time: float = 0.42
@export var reveal_start: float = 1.25    ## logo mulai terisi air
@export var reveal_time: float = 1.5      ## lama logo terisi penuh
@export var tagline_time: float = 2.7     ## tagline muncul
@export var hold_until: float = 4.4       ## mulai memudar ke menu
@export var leave_fade: float = 0.5
@export_group("Tampilan")
@export var bg_top := Color(0.04, 0.07, 0.1)
@export var bg_bottom := Color(0.09, 0.2, 0.26)
@export var water_color := Color(0.45, 0.82, 0.95)
@export var logo_width: float = 400.0
@export var logo_center := Vector2(320, 138)
@export var tagline: String = "Guide the water. Save the city."
@export var credit: String = "Ayam Renang"

var _t := 0.0
var _ripples: Array = []     # {pos, born, size}
var _drops_done := {}
var _bubbles: Array = []
var _fx: Control            # lapisan efek (tetes, riak, gelembung) di atas latar, di bawah logo
var _tw_reveal: Tween
var _logo: TextureRect
var _tag: Label
var _credit: Label
var _fade: ColorRect
var _leaving := false
var _impact := Vector2(320, 276)

const SHADER := """
shader_type canvas_item;
uniform float reveal : hint_range(0.0, 1.0) = 0.0;
uniform vec3 foam_color = vec3(0.85, 0.96, 1.0);
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float amp = 0.035;
	float wave = sin(UV.x * 28.0 + TIME * 5.0) * amp + sin(UV.x * 11.0 - TIME * 3.0) * amp * 0.6;
	float edge = mix(1.0 + amp * 2.0, -amp * 2.0, reveal) + wave * (1.0 - reveal * 0.6);
	float d = UV.y - edge;
	float vis = step(0.0, d);
	float foam = smoothstep(0.07, 0.0, d) * vis;
	c.rgb = mix(c.rgb, foam_color, foam * 0.85);
	c.a *= vis;
	COLOR = c;
}
"""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# latar gradien
	var g := Gradient.new()
	g.set_color(0, bg_top)
	g.set_color(1, bg_bottom)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	var bg := TextureRect.new()
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_fx = Control.new()
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	# gelembung melayang pelan
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 16:
		_bubbles.append({"x": rng.randf_range(20, 620), "y": rng.randf_range(0, 360), "s": rng.randf_range(0.6, 1.8),
			"v": rng.randf_range(6, 16), "ph": rng.randf_range(0, TAU)})
	# logo + shader air
	_logo = TextureRect.new()
	_logo.texture = logo
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := logo_width * logo.get_height() / logo.get_width()
	_logo.size = Vector2(logo_width, h)
	_logo.position = (logo_center - _logo.size / 2.0).round()
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("reveal", 0.0)
	_logo.material = mat
	add_child(_logo)
	# teks
	_tag = _make_label(tagline, 11, Color(0.82, 0.93, 0.97), Vector2(320, logo_center.y + h / 2.0 + 22))
	_credit = _make_label(credit, 7, Color(0.55, 0.7, 0.76), Vector2(320, 338))
	_tag.modulate.a = 0.0
	_credit.modulate.a = 0.0
	# layar gelap untuk fade masuk / keluar
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 0.5)
	# animasi logo terisi air
	_tw_reveal = create_tween()
	var tw := _tw_reveal
	tw.tween_interval(reveal_start)
	tw.tween_method(func(v: float): mat.set_shader_parameter("reveal", v), 0.0, 1.0, reveal_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var tw2 := create_tween()
	tw2.tween_interval(tagline_time)
	tw2.tween_property(_tag, "modulate:a", 1.0, 0.6)
	tw2.parallel().tween_property(_credit, "modulate:a", 0.85, 0.9)

func _make_label(text: String, size: int, color: Color, center: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	l.add_theme_constant_override("outline_size", 2)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(500, 18)
	l.position = (center - l.size / 2.0).round()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

func _process(delta: float) -> void:
	_t += delta
	# riak saat tetes menyentuh air
	for i in drop_times.size():
		if _t >= drop_times[i] + drop_fall_time and not _drops_done.has(i):
			_drops_done[i] = true
			_ripples.append({"pos": _impact, "born": _t, "size": 70.0 + i * 20.0})
	# riak kecil susulan selama logo terisi
	if _t > reveal_start and _t < reveal_start + reveal_time and int(_t * 5.0) != int((_t - delta) * 5.0):
		_ripples.append({"pos": _impact + Vector2(randf_range(-110, 110), randf_range(-8, 14)), "born": _t, "size": randf_range(24, 44)})
	if _t >= hold_until and not _leaving:
		_leave(leave_fade)
	_fx.queue_redraw()

func _draw_fx() -> void:
	# cahaya lembut di belakang logo, makin terang saat logo terisi
	var glow := clampf((_t - reveal_start) / (reveal_time + 0.6), 0.0, 1.0)
	for i in 6:
		var r := 150.0 - i * 20.0
		_fx.draw_circle(logo_center, r, Color(water_color.r, water_color.g, water_color.b, 0.018 * glow))
	# gelembung
	for b in _bubbles:
		var y: float = fposmod(b["y"] - _t * b["v"], 380.0) - 10.0
		var x: float = b["x"] + sin(_t * 0.8 + b["ph"]) * 6.0
		_fx.draw_circle(Vector2(x, y), b["s"], Color(0.7, 0.92, 1.0, 0.25))
	# riak isometrik (elips 2:1)
	for r in _ripples:
		var age: float = _t - r["born"]
		var life := 1.5
		if age > life:
			continue
		var k := age / life
		var rad: float = r["size"] * (1.0 - pow(1.0 - k, 2.0))
		_fx.draw_set_transform(r["pos"], 0.0, Vector2(1.0, 0.5))
		_fx.draw_arc(Vector2.ZERO, rad, 0.0, TAU, 56, Color(water_color.r, water_color.g, water_color.b, 0.7 * (1.0 - k)), 1.5)
		if rad > 14.0:
			_fx.draw_arc(Vector2.ZERO, rad * 0.62, 0.0, TAU, 40, Color(0.85, 0.97, 1.0, 0.4 * (1.0 - k)), 1.0)
		_fx.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# tetes air jatuh
	for i in drop_times.size():
		var s: float = _t - drop_times[i]
		if s >= 0.0 and s < drop_fall_time:
			var k := s / drop_fall_time
			var y: float = lerpf(-12.0, _impact.y, k * k)
			var p := Vector2(_impact.x, y)
			_fx.draw_line(p + Vector2(0, -9.0 * k), p, Color(water_color.r, water_color.g, water_color.b, 0.35), 1.0)
			_fx.draw_circle(p, 2.6, water_color)
			_fx.draw_circle(p + Vector2(-0.8, -0.8), 0.9, Color(1, 1, 1, 0.9))

func _unhandled_input(event: InputEvent) -> void:
	if _leaving:
		return
	if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
		get_viewport().set_input_as_handled()
		_leave(0.25)

func _leave(time: float) -> void:
	_leaving = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, time)
	tw.tween_callback(func(): get_tree().change_scene_to_file(next_scene))
