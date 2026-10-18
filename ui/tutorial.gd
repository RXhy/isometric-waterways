extends Control
## Tutorial interaktif (scenes/ui/tutorial.tscn): halaman demi halaman dengan ikon.
## Dibuka dari main menu (TUTORIAL) dan dari menu jeda in-game.
## Navigasi: tombol Sebelumnya/Berikutnya, titik halaman (bisa diklik), panah kiri/kanan, Esc = tutup.
## Isi tutorial ada di PAGES di bawah (judul, isi, ikon).

signal closed

const PAGES := [
	{"title": "1. Misi Utama", "icons": ["res://assets/Icon/buildings.png", "res://assets/Icon/warning.png", "res://assets/Icon/destroyed.png"],
	 "body": "Selamat datang di Waterways! Tugas utamamu di sini adalah memastikan pasokan air terus mengalir ke pemukiman dan ladang warga. Saat sebuah bangunan muncul, perhatikan indikator di atasnya dan segera penuhi kebutuhan air mereka. Jangan biarkan tanda peringatan muncul atau membiarkan bangunan tersebut hancur karena kekeringan."},
	{"title": "2. Menggali Kanal & Mengatur Daratan", "icons": ["res://assets/Icon/gali.png", "res://assets/Icon/ratakan.png", "res://assets/Icon/timbun.png"],
	 "body": "Bagaimana cara mengalirkan air? Gunakan alat Buldoser untuk menggali kanal dari sumber air terdekat menuju bangunan warga. Ingat, air tidak bisa mengalir dari tempat rendah ke tempat tinggi. Jika daratan menghalangi, gunakan fitur Ratakan untuk menurunkan tanah sebanyak satu tingkat. Sebaliknya, gunakan fitur Timbun jika kamu ingin menutup kembali kanal yang salah gali."},
	{"title": "3. Melewati Jalan Raya", "icons": ["res://assets/Icon/bridges.png"],
	 "body": "Seiring berkembangnya pemukiman, jalan raya akan muncul. Kamu tidak bisa menggali kanal yang memotong jalan raya begitu saja. Sebagai solusinya, kamu bisa membangun Jembatan pada area jalan yang lurus. Ini memungkinkan kanalmu mengalir tepat di bawah jalan raya warga."},
	{"title": "4. Mengelola Jarak & Debit Air", "icons": ["res://assets/Icon/spillway.png", "res://assets/Icon/drill.png"],
	 "body": "Jarak yang terlalu jauh bisa membuat aliran air di ujung kanal menjadi dangkal. Gunakan Spillway untuk menampung volume air sementara waktu sebelum dialirkan ke area selanjutnya, sehingga debit air tetap terjaga. Jika sumber air terlalu jauh untuk dijangkau, kamu bisa membangun Sumur Bor untuk menciptakan mata airmu sendiri."},
	{"title": "5. Mengalirkan Air ke Tempat Tinggi", "icons": ["res://assets/Icon/kincir.png"],
	 "body": "Ada kalanya bangunan berada di dataran yang lebih tinggi. Karena air tidak bisa naik dengan sendirinya, gunakan fasilitas Kincir Air untuk memompa dan memindahkan air dari tempat rendah ke tempat tinggi. Pastikan ada arus air yang mengalir agar kincir dapat berfungsi!"},
	{"title": "6. Cuaca & Bencana", "icons": ["res://assets/Icon/berawan.png", "res://assets/Icon/kemarau.png", "res://assets/Icon/rain.png"],
	 "body": "Selalu pantau indikator cuaca di pojok kiri layar untuk melihat kondisi hari ini dan esok.\n\nCerah: Aliran air berjalan normal.\nKemarau: Air dari sumber alami akan menguap dan mengering dengan cepat. Di saat kritis ini, Sumur Bor akan menjadi penyelamatmu.\nHujan: Hati-hati! Curah hujan dapat menambah volume air secara drastis. Jika tidak dikelola dengan baik, air akan meluap dari kanal dan menyebabkan banjir."},
	{"title": "7. Bertahan Hidup!", "icons": ["res://assets/Icon/stars1.png", "res://assets/Icon/buildings.png"],
	 "body": "Misi utamamu adalah bertahan selama 45 hari. Kelola aliran airmu sebaik mungkin dan jangan sampai jumlah bangunan yang hancur melewati batas maksimal, atau kamu akan kalah. Selamat mengelola air!"},
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
	tt.text = "TUTORIAL WATERWAYS"
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
	close.tooltip_text = "Tutup (Esc)"
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
	_prev.text = "< Sebelumnya"
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
	_next.text = "Mulai Main!" if page == PAGES.size() - 1 else "Berikutnya >"

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
