extends Node
## Pemutar semua audio game (autoload "Audio", scene scenes/audio_manager.tscn).
## File audio dan volumenya diatur lewat Inspector di scene itu.
##   Audio.play("ui_click")            -> efek suara sekali (bus SFX)
##   Audio.play_music(bgm_menu)        -> musik loop (bus Music)
##   Audio.start_ambience() / stop_ambience()
##   Audio.set_water_level(0..1), Audio.set_weather(cuaca)  -> volume ambience mengikuti game
## Semua tombol (Button) otomatis berbunyi ui_click saat ditekan.

@export_group("Musik")
@export var bgm_menu: AudioStream
@export var jingle_win: AudioStream
@export var jingle_lose: AudioStream
@export var music_volume_db: float = -6.0
@export var music_fade_time: float = 1.0

@export_group("Ambience (loop)")
@export var amb_water: AudioStream
@export var amb_rain: AudioStream
@export var amb_wind: AudioStream
@export var water_volume_db: float = -8.0     ## volume air saat Aliran Air 100% (0% = hampir hening)
@export var rain_volume_db: float = -6.0
@export var wind_calm_volume_db: float = -20.0  ## angin pelan saat cerah
@export var wind_drought_volume_db: float = -9.0 ## angin kering saat kemarau
@export var wind_drought_pitch: float = 0.85
@export var ambience_fade_speed: float = 1.5  ## seberapa cepat volume ambience berubah (per detik)

@export_group("Efek suara")
@export var ui_click: AudioStream
@export var ui_error: AudioStream
@export var tool_dirt: AudioStream
@export var place_wood: AudioStream
@export var place_stone: AudioStream
@export var bld_warning: AudioStream
@export var bld_destroyed: AudioStream
@export var day_new: AudioStream
@export var land_expand: AudioStream
@export var sfx_volume_db: float = 0.0
@export var click_volume_db: float = -4.0
## Jeda minimal (detik) antar bunyi yang sama, supaya drag panjang / banyak bangunan tidak berisik.
@export var min_interval := {"tool_dirt": 0.07, "bld_warning": 1.2, "ui_click": 0.04, "ui_error": 0.25, "place_stone": 0.05}

const POOL_SIZE := 8
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _last_played := {}
var _music: AudioStreamPlayer
var _music_tw: Tween
var _amb := {}            # nama -> AudioStreamPlayer
var _amb_target := {}     # nama -> volume target (db)
var _amb_on := false
var _water_level := 0.0
var _weather := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_music.finished.connect(_on_music_finished)
	for n in ["water", "rain", "wind"]:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		p.volume_db = -80.0
		add_child(p)
		p.finished.connect(p.play)  # loop untuk semua format (wav/mp3/ogg)
		_amb[n] = p
		_amb_target[n] = -80.0
	_amb["water"].stream = amb_water
	_amb["rain"].stream = amb_rain
	_amb["wind"].stream = amb_wind
	get_tree().node_added.connect(_on_node_added)

func _on_music_finished() -> void:
	if _music.stream == bgm_menu:
		_music.play()  # musik menu diulang; jingle cukup sekali

## Semua tombol berbunyi klik (tombol bisa dikecualikan dengan set_meta("no_click", true)).
func _on_node_added(n: Node) -> void:
	if n is BaseButton and not n.has_meta("no_click"):
		n.pressed.connect(func(): play("ui_click"))

## Mainkan efek suara sekali. pitch_jitter 0.08 = pitch acak ±8%.
func play(sound: String, pitch: float = 1.0, pitch_jitter: float = 0.0, volume_db: float = 0.0) -> void:
	var s: AudioStream = get(sound) as AudioStream
	if s == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_played.get(sound, -100.0) < min_interval.get(sound, 0.0):
		return
	_last_played[sound] = now
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = s
	p.pitch_scale = pitch * (1.0 + randf_range(-pitch_jitter, pitch_jitter))
	p.volume_db = sfx_volume_db + volume_db + (click_volume_db if sound == "ui_click" else 0.0)
	p.play()

# --- Musik ---

func play_music(stream: AudioStream, loop := true) -> void:
	if stream == null or (_music.playing and _music.stream == stream):
		return
	if _music_tw:
		_music_tw.kill()
	_music.stream = stream
	_music.volume_db = -40.0 if loop else music_volume_db
	_music.play()
	if loop:
		_music_tw = create_tween()
		_music_tw.tween_property(_music, "volume_db", music_volume_db, music_fade_time)

func stop_music() -> void:
	if not _music.playing:
		return
	if _music_tw:
		_music_tw.kill()
	_music_tw = create_tween()
	_music_tw.tween_property(_music, "volume_db", -40.0, music_fade_time)
	_music_tw.tween_callback(_music.stop)

## Jingle menang / kalah (sekali, menggantikan musik).
func play_jingle(won: bool) -> void:
	if _music_tw:
		_music_tw.kill()
	_music.stop()
	play_music(jingle_win if won else jingle_lose, false)

# --- Ambience ---

func start_ambience() -> void:
	_amb_on = true
	for n in _amb:
		if _amb[n].stream and not _amb[n].playing:
			_amb[n].volume_db = -80.0
			_amb[n].play()

func stop_ambience() -> void:
	_amb_on = false

## 0..1: persentase bangunan yang teraliri (panel Aliran Air).
func set_water_level(v: float) -> void:
	_water_level = clampf(v, 0.0, 1.0)

## Cuaca: 0 cerah, 1 kemarau, 2 hujan (WeatherManager.Weather).
func set_weather(w: int) -> void:
	_weather = w

func _process(delta: float) -> void:
	if _amb_on:
		# air: tetap terdengar pelan walau belum ada yang teraliri (ada sungai/danau)
		_amb_target["water"] = lerpf(water_volume_db - 14.0, water_volume_db, _water_level)
		_amb_target["rain"] = rain_volume_db if _weather == 2 else -80.0
		_amb_target["wind"] = wind_drought_volume_db if _weather == 1 else wind_calm_volume_db
		_amb["wind"].pitch_scale = move_toward(_amb["wind"].pitch_scale, wind_drought_pitch if _weather == 1 else 1.0, delta * 0.3)
	else:
		for n in _amb_target:
			_amb_target[n] = -80.0
	for n in _amb:
		var p: AudioStreamPlayer = _amb[n]
		# pindah volume di skala linear supaya naik/turun terdengar halus
		var cur := db_to_linear(p.volume_db)
		var tgt := db_to_linear(_amb_target[n])
		p.volume_db = linear_to_db(maxf(move_toward(cur, tgt, delta * ambience_fade_speed * 0.5), 0.0001))
		if not _amb_on and p.playing and p.volume_db <= -79.0:
			p.stop()
