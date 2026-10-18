extends Control
## Layar loading antara main menu dan permainan (scenes/loading.tscn).
## Memuat world.tscn sambil menampilkan peta latar (scenes/loading_map.tscn).

@export_file("*.tscn") var target_scene := "res://world.tscn"
@export var fade_out_time: float = 0.25  ## lama layar memudar ke game
@export_range(0.0, 1.0) var fade_peak_alpha: float = 0.9  ## kegelapan maksimal saat transisi (1 = hitam penuh, makin kecil makin terang)
@export var fade_in_time: float = 0.2    ## lama loading memudar ke gelap sebelum masuk game
@export var min_time: float = 4.0        ## LAMA LOADING (detik): bar air terisi penuh dalam waktu ini. Ubah angka ini untuk mengatur durasi.
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
	if _packed != null and _shown >= 1.0 and not _done:
		_done = true
		set_process(false)
		_enter_game()

## Layar menghitam, game dibuat DI BAWAH layar hitam (loading tetap di atas), lalu hitam memudar
## langsung ke game. Tidak ada pergantian scene yang menampakkan layar abu.
func _enter_game() -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(fade, "color:a", fade_peak_alpha, fade_in_time)
	for n in $UI.get_children():  # isi loading ikut memudar supaya tidak tiba-tiba hilang
		if n != fade:
			tw.tween_property(n, "modulate:a", 0.0, fade_in_time)
	await tw.finished
	# isi loading sudah memudar habis: sembunyikan SEMUA isi loading (logo, bar, tip, bayangan) supaya
	# saat hitam memudar yang terlihat hanya game, bukan loading screen
	for n in $UI.get_children():
		if n != fade:
			n.hide()
	if is_instance_valid($Map):
		$Map.queue_free()
	var world := _packed.instantiate()
	var tree := get_tree()
	tree.root.add_child(world)
	tree.current_scene = world
	await tree.process_frame
	await tree.process_frame
	var out := create_tween()
	out.tween_property(fade, "color:a", 0.0, fade_out_time)
	await out.finished
	queue_free()
