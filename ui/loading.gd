extends Control
## Layar loading antara main menu dan permainan (scenes/loading.tscn).
## Memuat world.tscn sambil menampilkan peta latar (scenes/loading_map.tscn).

@export_file("*.tscn") var target_scene := "res://world.tscn"
@export var fade_out_time: float = 0.25  ## lama layar memudar ke game
@export_range(0.0, 1.0) var fade_peak_alpha: float = 0.9  ## kegelapan maksimal saat transisi (1 = hitam penuh, makin kecil makin terang)
@export var fade_in_time: float = 0.2    ## lama loading memudar ke gelap sebelum masuk game
@export var min_time: float = 4.0        ## LAMA LOADING (detik): bar air terisi penuh dalam waktu ini. Ubah angka ini untuk mengatur durasi.
@export_range(0.0, 1.0) var prebuild_at: float = 0.6  ## KAPAN game dibangun diam-diam di balik loading (0.6 = di 60% waktu loading). Rasa "nyendat" sekali terjadi di titik ini, bukan saat transisi. 1.0 = di akhir (transisi akan terasa berhenti sebentar)
@export var bar_speed: float = 2.0       ## kecepatan isi bar mengejar progres asli (per detik)
@export var pan_speed := Vector2(6, -2)  ## jarak gerak kamera latar (x4 px, bolak-balik)
@export var tips: PackedStringArray = [
	"Build bridges and manage the flow before floods reach the houses!",
	"Water can't flow uphill. Use a Water Wheel to lift it to higher ground.",
	"Spillways drain overflowing canals during heavy rain.",
	"Drill Wells give a permanent water source during droughts.",
	"Check tomorrow's forecast and prepare before the weather changes.",
	"Houses and farms only need water on one of their 8 neighboring tiles.",
]

@onready var bar = $UI/Bar
@onready var tip: Label = $UI/Tip
@onready var fade: ColorRect = $UI/Fade
@onready var cam: Camera2D = get_node_or_null("Map/Camera2D")

var _t := 0.0
var _shown := 0.0
var _done := false
var _packed: PackedScene
var _start := Vector2.ZERO
var _world: Node            # game yang sudah dibangun tapi masih disembunyikan
var _hidden_layers: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # jangan menelan klik ke game di bawahnya
	Engine.time_scale = 1.0
	tip.text = "Tip: " + tips[randi() % tips.size()]
	fade.color.a = 1.0
	create_tween().tween_property(fade, "color:a", 0.0, 0.2)
	_start = cam.position if cam else Vector2.ZERO

func _process(delta: float) -> void:
	_t += delta
	if cam:  # kamera latar bergerak pelan bolak-balik
		cam.position = _start + pan_speed * sin(_t * 0.5) * 4.0
	# muat world setelah layar loading sempat tampil (muat biasa: lebih andal daripada thread)
	if _packed == null and _t > 0.25:
		_packed = load(target_scene)
	var target: float = clampf(_t / min_time, 0.0, 1.0 if _packed != null else 0.85)
	_shown = move_toward(_shown, target, bar_speed * delta)
	bar.value = _shown * 100.0
	if _world == null and _packed != null and _t >= min_time * prebuild_at:
		_prebuild()
	if _world != null and _shown >= 1.0 and not _done:
		_done = true
		set_process(false)
		_enter_game()

## Bangun game di balik loading: disembunyikan & dibekukan (tidak jalan, tidak terlihat), kamera latar loading tetap aktif.
## Dengan begitu saat loading selesai, tidak ada proses berat lagi: transisi langsung memudar ke game tanpa jeda.
func _prebuild() -> void:
	_world = _packed.instantiate()
	_world.process_mode = Node.PROCESS_MODE_DISABLED
	if _world is CanvasItem:
		_world.hide()
	get_tree().root.add_child(_world)  # _ready game jalan di sini (sekali nyendat)
	for c in _world.get_children():
		if c is CanvasLayer and c.visible:
			_hidden_layers.append(c)
			c.hide()
	if cam:
		cam.make_current()  # game tadi merebut kamera; kembalikan ke kamera latar loading

## Layar menggelap, isi loading memudar, lalu di puncak gelap game langsung ditampilkan (sudah siap) dan hitam memudar ke game.
func _enter_game() -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(fade, "color:a", fade_peak_alpha, fade_in_time)
	for n in $UI.get_children():  # isi loading ikut memudar supaya tidak tiba-tiba hilang
		if n != fade:
			tw.tween_property(n, "modulate:a", 0.0, fade_in_time)
	await tw.finished
	for n in $UI.get_children():
		if n != fade:
			n.hide()
	if is_instance_valid($Map):
		$Map.queue_free()
	# tampilkan game (instan, tanpa jeda), langsung mulai memudar
	if _world is CanvasItem:
		_world.show()
	for c in _hidden_layers:
		c.show()
	_world.process_mode = Node.PROCESS_MODE_INHERIT
	var wcam := _world.get_node_or_null("Camera2D") as Camera2D
	if wcam:
		wcam.make_current()
	get_tree().current_scene = _world
	var out := create_tween()
	out.tween_property(fade, "color:a", 0.0, fade_out_time)
	await out.finished
	queue_free()
