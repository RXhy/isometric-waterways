extends Control
## Layar loading antara main menu dan permainan (scenes/loading.tscn).
## Memuat world.tscn sambil menampilkan peta latar (scenes/loading_map.tscn).

@export_file("*.tscn") var target_scene := "res://world.tscn"
@export var min_time: float = 1.5        ## lama tampil minimal (detik) supaya tidak berkedip
@export var bar_speed: float = 0.8       ## kecepatan isi bar mengejar progres asli (per detik)
@export var pan_speed := Vector2(6, -2)  ## jarak gerak kamera latar (x4 px, bolak-balik)
@export var tips: PackedStringArray = [
	"Build bridges and manage the flow before floods reach the houses!",
	"Water can't flow uphill. Use a Water Wheel to lift it to higher ground.",
	"Spillways drain overflowing canals during heavy rain.",
	"Drill Wells give a permanent water source during droughts.",
	"Check tomorrow's forecast and prepare before the weather changes.",
	"Houses and farms only need water on one of their 8 neighboring tiles.",
]

@onready var bar: ProgressBar = $UI/Bar
@onready var tip: Label = $UI/Tip
@onready var fade: ColorRect = $UI/Fade
@onready var cam: Camera2D = get_node_or_null("Map/Camera2D")

var _t := 0.0
var _shown := 0.0
var _done := false
var _packed: PackedScene
var _start := Vector2.ZERO

func _ready() -> void:
	Engine.time_scale = 1.0
	tip.text = "Tip: " + tips[randi() % tips.size()]
	fade.color.a = 1.0
	create_tween().tween_property(fade, "color:a", 0.0, 0.4)
	_start = cam.position if cam else Vector2.ZERO

func _process(delta: float) -> void:
	_t += delta
	if cam:  # kamera latar bergerak pelan bolak-balik
		cam.position = _start + pan_speed * sin(_t * 0.5) * 4.0
	# muat world setelah layar loading sempat tampil (muat biasa: lebih andal daripada thread)
	if _packed == null and _t > 0.45:
		_packed = load(target_scene)
	var target: float = clampf(_t / min_time, 0.0, 1.0 if _packed != null else 0.85)
	_shown = move_toward(_shown, target, bar_speed * delta)
	bar.value = _shown * 100.0
	if _packed != null and _shown >= 1.0 and not _done:
		_done = true
		var tw := create_tween()
		tw.tween_property(fade, "color:a", 1.0, 0.35)
		tw.tween_callback(func(): get_tree().change_scene_to_packed(_packed))
