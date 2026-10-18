extends Control
## Tutorial interaktif (scenes/ui/tutorial.tscn): halaman demi halaman dengan ikon.
## Dibuka dari main menu (TUTORIAL) dan dari menu jeda in-game.
## Navigasi: tombol Sebelumnya/Berikutnya, titik halaman (bisa diklik), panah kiri/kanan, Esc = tutup.
## Isi tutorial ada di PAGES di bawah (judul, isi, ikon).

signal closed

const PAGES := [
	{"title": "1. Your Mission", "icons": ["res://assets/Icon/buildings.png", "res://assets/Icon/warning.png", "res://assets/Icon/destroyed.png"],
	 "body": "Welcome to Waterways! Your job is to keep water flowing to the town's houses and farms. When a new building appears, watch the indicator above it and get water to it quickly. Don't let warning signs pile up, and don't let any building fall to drought."},
	{"title": "2. Digging Canals & Shaping the Land", "icons": ["res://assets/Icon/gali.png", "res://assets/Icon/ratakan.png", "res://assets/Icon/timbun.png"],
	 "body": "How do you move water? Use the Dig tool to carve a canal from the nearest water source to the buildings. Remember: water can't flow from low ground to high ground. If the terrain is in the way, use Level to lower the land by one step. Made a mistake? Use Fill to close a canal you dug."},
	{"title": "3. Crossing Roads", "icons": ["res://assets/Icon/bridges.png"],
	 "body": "As the town grows, roads will appear. You can't dig a canal straight through a road. Instead, build a Bridge on a straight section of road so your canal can flow right underneath it."},
	{"title": "4. Distance & Water Flow", "icons": ["res://assets/Icon/spillway.png", "res://assets/Icon/drill.png"],
	 "body": "Long canals can leave the far end too shallow. Use a Spillway to hold water back for a while before it flows on, keeping the flow steady. If a water source is too far away, build a Drill Well to create your own spring."},
	{"title": "5. Lifting Water to High Ground", "icons": ["res://assets/Icon/kincir.png"],
	 "body": "Some buildings sit on higher ground. Water can't climb on its own, so use a Water Wheel to pump it from low ground up to high ground. Make sure water is flowing through it, or the wheel won't turn!"},
	{"title": "6. Weather & Disasters", "icons": ["res://assets/Icon/berawan.png", "res://assets/Icon/kemarau.png", "res://assets/Icon/rain.png"],
	 "body": "Keep an eye on the weather panel in the top-left corner to see today's and tomorrow's conditions.\n\nCloudy: Water flows normally.\nDrought: Natural water sources evaporate and dry up fast. In times like this, Drill Wells will save you.\nHeavy Rain: Careful! Rain can raise water levels dramatically. If you don't manage it, canals will overflow and cause floods."},
	{"title": "7. Survive!", "icons": ["res://assets/Icon/stars1.png", "res://assets/Icon/buildings.png"],
	 "body": "Your goal is to survive for 45 days. Manage your water wisely and don't let the number of destroyed buildings pass the limit, or you'll lose. Good luck!"},
]

@export var icon_size: float = 34.0
@export var panel_size: Vector2 = Vector2(380, 250)

var page := 0
var _title: Label
var _body: Label
var _icons: HBoxContainer
var _dots: HBoxContainer
var _prev: Button
var _next: Button
var _counter: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = load("res://ui/hud_theme.tres")
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = panel_size
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var m := MarginContainer.new()
	for k in ["left", "right"]:
		m.add_theme_constant_override("margin_" + k, 10)
	for k in ["top", "bottom"]:
		m.add_theme_constant_override("margin_" + k, 6)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	m.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var tt := Label.new()
	tt.text = "WATERWAYS TUTORIAL"
	tt.add_theme_color_override("font_color", Color(0.62, 0.82, 1))
	tt.add_theme_font_size_override("font_size", 9)
	tt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tt)
	_counter = Label.new()
	_counter.add_theme_font_size_override("font_size", 8)
	_counter.add_theme_color_override("font_color", Color(0.7, 0.71, 0.69))
	head.add_child(_counter)
	var close := Button.new()
	close.text = "X"
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Close (Esc)"
	close.pressed.connect(_close)
	head.add_child(close)
	_icons = HBoxContainer.new()
	_icons.alignment = BoxContainer.ALIGNMENT_CENTER
	_icons.add_theme_constant_override("separation", 10)
	v.add_child(_icons)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 12)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	_body = Label.new()
	_body.add_theme_font_size_override("font_size", 8)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(panel_size.x - 24, 0)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_body)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 6)
	v.add_child(nav)
	_prev = Button.new()
	_prev.text = "< Previous"
	_prev.focus_mode = Control.FOCUS_NONE
	_prev.pressed.connect(func(): show_page(page - 1))
	nav.add_child(_prev)
	_dots = HBoxContainer.new()
	_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	_dots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dots.add_theme_constant_override("separation", 3)
	nav.add_child(_dots)
	for i in PAGES.size():
		var d := Button.new()
		d.custom_minimum_size = Vector2(9, 9)
		d.focus_mode = Control.FOCUS_NONE
		d.toggle_mode = true
		d.tooltip_text = PAGES[i]["title"]
		d.pressed.connect(show_page.bind(i))
		for st in [["normal", Color(1, 1, 1, 0.25)], ["hover", Color(1, 1, 1, 0.5)], ["pressed", Color(0.62, 0.82, 1)], ["hover_pressed", Color(0.62, 0.82, 1)]]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = st[1]
			sb.set_corner_radius_all(5)
			d.add_theme_stylebox_override(st[0], sb)
		_dots.add_child(d)
	_next = Button.new()
	_next.focus_mode = Control.FOCUS_NONE
	_next.pressed.connect(func(): _close() if page == PAGES.size() - 1 else show_page(page + 1))
	nav.add_child(_next)
	show_page(0)

func open() -> void:
	show_page(0)
	show()

func show_page(i: int) -> void:
	page = clampi(i, 0, PAGES.size() - 1)
	var p: Dictionary = PAGES[page]
	_title.text = p["title"]
	_body.text = p["body"]
	_counter.text = "%d / %d" % [page + 1, PAGES.size()]
	for c in _icons.get_children():
		c.queue_free()
	for path in p["icons"]:
		var t := TextureRect.new()
		t.texture = load(path)
		t.custom_minimum_size = Vector2(icon_size, icon_size)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if t.texture and t.texture.get_width() > 128:
			t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_icons.add_child(t)
	for k in _dots.get_child_count():
		(_dots.get_child(k) as Button).set_pressed_no_signal(k == page)
	_prev.disabled = page == 0
	_next.text = "Let's Play!" if page == PAGES.size() - 1 else "Next >"

func _close() -> void:
	hide()
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_close()
	elif event.is_action_pressed("ui_right"):
		show_page(page + 1)
	elif event.is_action_pressed("ui_left"):
		show_page(page - 1)
	else:
		return
	get_viewport().set_input_as_handled()
