extends Control
## Dasar layar Mode Survei (profil & kuesioner): latar, panel, dan pembuat isian.
## Layar 640x360 (lihat project.godot), jadi isian dibuat ringkas dan dibagi per halaman.

var theme_res: Theme
var body: VBoxContainer       # isi halaman yang sedang tampil
var title_lbl: Label
var sub_lbl: Label
var error_lbl: Label
var nav: HBoxContainer

func build_frame(title: String) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme_res = Survey.make_theme()
	theme = theme_res
	var bg := ColorRect.new()
	bg.color = Survey.C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var stripe := ColorRect.new()  # pita ombak tipis di bawah, warna game
	stripe.color = Survey.C_BROWN
	stripe.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	stripe.offset_top = -4
	add_child(stripe)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for k in ["left", "right"]:
		m.add_theme_constant_override("margin_" + k, 18)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 10)
	add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	m.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	title_lbl = Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Survey.C_YELLOW)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_lbl)
	sub_lbl = Label.new()
	sub_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	sub_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(sub_lbl)
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.15)
	line.custom_minimum_size = Vector2(0, 1)
	v.add_child(line)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 5)
	scroll.add_child(body)
	error_lbl = Label.new()
	error_lbl.add_theme_color_override("font_color", Color("FF8A80"))
	error_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(error_lbl)
	nav = HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	v.add_child(nav)

func clear_body() -> void:
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	error_lbl.text = ""

func clear_nav() -> void:
	for c in nav.get_children():
		nav.remove_child(c)
		c.queue_free()

func add_nav_button(text: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(90, 20)
	if primary:
		b.add_theme_stylebox_override("normal", Survey._box(Survey.C_YELLOW, Survey.C_YELLOW, 1, 3))
		b.add_theme_stylebox_override("hover", Survey._box(Color("FFD46B"), Color("FFD46B"), 1, 3))
		b.add_theme_color_override("font_color", Survey.C_BG)
		b.add_theme_color_override("font_hover_color", Survey.C_BG)
	b.pressed.connect(cb)
	nav.add_child(b)
	return b

func add_spacer_nav() -> void:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(s)

func add_note(text: String, color := Color(1, 1, 1, 0.65)) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", color)
	body.add_child(l)
	return l

func add_section(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Survey.C_YELLOW)
	body.add_child(l)

## Baris "label | isian" dengan lebar label tetap.
func add_row(label: String, field: Control, label_w := 300.0) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(label_w, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(field)
	body.add_child(h)

func make_option(items: Array, value := "") -> OptionButton:
	var o := OptionButton.new()
	o.add_item("— pilih —")
	o.set_item_disabled(0, true)
	for it in items:
		o.add_item(str(it))
	o.select(0)
	for i in o.item_count:
		if o.get_item_text(i) == value:
			o.select(i)
	o.get_popup().theme = theme_res
	return o

func option_value(o: OptionButton) -> String:
	return "" if o.selected <= 0 else o.get_item_text(o.selected)

## Deretan tombol pilihan (seperti radio). Mengembalikan HBox; nilai terpilih lewat chosen(box).
func make_choice(labels: Array, values: Array, current := "", min_w := 22.0) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for i in labels.size():
		var b := Button.new()
		b.text = str(labels[i])
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(min_w, 18)
		b.set_meta("value", str(values[i]))
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.focus_mode = Control.FOCUS_NONE
		if str(values[i]) == current and current != "":
			b.button_pressed = true
		h.add_child(b)
	h.set_meta("group", group)
	return h

func chosen(h: HBoxContainer) -> String:
	var g: ButtonGroup = h.get_meta("group")
	var b := g.get_pressed_button()
	return "" if b == null else str(b.get_meta("value"))

func make_text(placeholder: String, value := "", h := 30.0) -> TextEdit:
	var t := TextEdit.new()
	t.placeholder_text = placeholder
	t.text = value
	t.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	t.custom_minimum_size = Vector2(0, h)
	t.scroll_fit_content_height = false
	return t

func make_check(text: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		c.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	c.add_theme_color_override("font_pressed_color", Survey.C_CREAM)
	c.add_theme_color_override("font_hover_pressed_color", Survey.C_CREAM)
	return c

func show_error(msg: String) -> void:
	error_lbl.text = msg
