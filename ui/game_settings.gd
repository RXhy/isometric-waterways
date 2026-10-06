class_name GameSettings
extends RefCounted
## Pengaturan pemain (volume, layar penuh, tooltip). Disimpan di user://settings.cfg
## dan dipakai menu opsi in-game (scenes/ui/pause_menu.tscn).
## Bus audio "Music" dan "SFX" ada di default_bus_layout.tres: nanti AudioStreamPlayer
## musik pakai bus Music, efek suara pakai bus SFX, supaya slider volumenya berlaku.

const PATH := "user://settings.cfg"

static var data := {
	"vol_master": 0.8,
	"vol_music": 0.8,
	"vol_sfx": 0.8,
	"fullscreen": false,
	"tooltips": true,
}
static var _loaded := false

static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for k in data:
			data[k] = cfg.get_value("game", k, data[k])
	apply()

static func get_value(key: String):
	load_settings()
	return data.get(key)

static func set_value(key: String, value) -> void:
	load_settings()
	data[key] = value
	apply()
	var cfg := ConfigFile.new()
	for k in data:
		cfg.set_value("game", k, data[k])
	cfg.save(PATH)

static func apply() -> void:
	_set_bus("Master", data["vol_master"])
	_set_bus("Music", data["vol_music"])
	_set_bus("SFX", data["vol_sfx"])
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if data["fullscreen"] else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)

static func _set_bus(bus_name: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		return
	AudioServer.set_bus_mute(i, linear <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.001)))
