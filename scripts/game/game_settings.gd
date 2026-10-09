class_name GameSettings
extends RefCounted
## Player settings that outlive a run: which sounds are on. Saved to user://settings.cfg and
## applied to the audio buses (default_bus_layout.tres: Music, SFX, Voice).
## Main calls load_and_apply() at startup; the pause menu calls set_enabled().

const PATH := "user://settings.cfg"
## Setting key -> audio bus it switches.
const BUSES := {"music": &"Music", "sfx": &"SFX", "voice": &"Voice"}

static var _values: Dictionary = {"music": true, "sfx": true, "voice": true}
static var _loaded: bool = false


static func load_and_apply() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for key in _values:
			_values[key] = bool(cfg.get_value("audio", key, true))
	_loaded = true
	for key in _values:
		_apply(key)


static func is_enabled(key: String) -> bool:
	if not _loaded:
		load_and_apply()
	return _values.get(key, true)


## Turns one sound channel on or off, applies it, and saves. Returns true if the save worked.
static func set_enabled(key: String, on: bool) -> bool:
	if not _values.has(key):
		return false
	_values[key] = on
	_apply(key)
	var cfg := ConfigFile.new()
	for k in _values:
		cfg.set_value("audio", k, _values[k])
	return cfg.save(PATH) == OK


static func _apply(key: String) -> void:
	var bus := AudioServer.get_bus_index(BUSES[key])
	if bus >= 0:
		AudioServer.set_bus_mute(bus, not _values[key])
