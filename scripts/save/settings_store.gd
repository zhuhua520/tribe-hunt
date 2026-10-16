extends RefCounted
## 本地设置存档。只记录已经能生效的主音量和窗口模式。

const SCHEMA_VERSION := 1
const SETTINGS_PATH := "user://settings.json"
const TEMP_PATH := "user://settings.json.tmp"
const BACKUP_PATH := "user://settings.json.bak"

const WINDOW_WINDOWED := "windowed"
const WINDOW_FULLSCREEN := "fullscreen"
const WINDOW_MODES: Array[String] = [WINDOW_WINDOWED, WINDOW_FULLSCREEN]

const DEFAULT_MASTER_VOLUME := 1.0
const DEFAULT_WINDOW_MODE := WINDOW_WINDOWED

const _PARSE_OK := 0
const _PARSE_INVALID := 1
const _PARSE_NEWER := 2

static var master_volume: float = DEFAULT_MASTER_VOLUME
static var window_mode: String = DEFAULT_WINDOW_MODE
static var _saved_volume: float = DEFAULT_MASTER_VOLUME
static var _saved_window_mode: String = DEFAULT_WINDOW_MODE
static var _loaded: bool = false
static var _block_save: bool = false


static func load_and_apply() -> void:
	if not _loaded:
		_read_from_disk()
		_loaded = true
	apply()


static func apply() -> void:
	_apply_volume(master_volume)
	_apply_window_mode(window_mode)


static func set_master_volume(value: float, persist: bool = true) -> void:
	master_volume = _read_volume(value)
	_apply_volume(master_volume)
	if persist:
		_save_if_needed()


static func set_window_mode(mode: String, persist: bool = true) -> void:
	window_mode = _read_window_mode(mode)
	_apply_window_mode(window_mode)
	if persist:
		_save_if_needed()


static func _save_if_needed() -> void:
	if is_equal_approx(master_volume, _saved_volume) and window_mode == _saved_window_mode:
		return
	if save():
		_saved_volume = master_volume
		_saved_window_mode = window_mode


static func save() -> bool:
	if _block_save:
		push_warning("SettingsStore: 设置文件版本较新，未覆盖。")
		return false
	var contents := JSON.stringify(_to_dictionary(), "\t") + "\n"
	if not _write_verified(TEMP_PATH, contents):
		push_warning("SettingsStore: 临时文件写入失败。")
		return false
	if FileAccess.file_exists(SETTINGS_PATH) and _parse_text(_read_text(SETTINGS_PATH))["result"] == _PARSE_OK:
		if not _write_verified(BACKUP_PATH, _read_text(SETTINGS_PATH)):
			push_warning("SettingsStore: 备份写入失败。")
			return false
	if not _write_verified(SETTINGS_PATH, contents):
		push_warning("SettingsStore: 设置文件写入失败。")
		_restore_main_from_backup()
		return false
	_remove_file(TEMP_PATH)
	return true


static func _read_from_disk() -> void:
	master_volume = DEFAULT_MASTER_VOLUME
	window_mode = DEFAULT_WINDOW_MODE
	_saved_volume = DEFAULT_MASTER_VOLUME
	_saved_window_mode = DEFAULT_WINDOW_MODE
	_block_save = false
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var parsed: Dictionary = _parse_text(_read_text(SETTINGS_PATH))
	if parsed["result"] == _PARSE_OK:
		_adopt(parsed)
		return
	if parsed["result"] == _PARSE_NEWER:
		_block_save = true
		push_warning("SettingsStore: 设置文件版本较新，改用默认值且不覆盖原文件。")
		return
	push_warning("SettingsStore: 设置文件无法读取，尝试备份。")
	if FileAccess.file_exists(BACKUP_PATH):
		var backup: Dictionary = _parse_text(_read_text(BACKUP_PATH))
		if backup["result"] == _PARSE_OK:
			_adopt(backup)
			return
	push_warning("SettingsStore: 使用默认设置。")


static func _adopt(parsed: Dictionary) -> void:
	master_volume = parsed["master_volume"]
	window_mode = parsed["window_mode"]
	_saved_volume = master_volume
	_saved_window_mode = window_mode


static func _to_dictionary() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"updated_at": Time.get_datetime_string_from_system(true),
		"master_volume": master_volume,
		"window_mode": window_mode,
	}


static func _migrate(data: Dictionary, from_version: int) -> Dictionary:
	var current := data.duplicate(true)
	var version := from_version
	while version < SCHEMA_VERSION:
		version += 1
	current["schema_version"] = SCHEMA_VERSION
	return current


static func _parse_text(text: String) -> Dictionary:
	var failed := {
		"result": _PARSE_INVALID,
		"master_volume": DEFAULT_MASTER_VOLUME,
		"window_mode": DEFAULT_WINDOW_MODE,
	}
	if text.is_empty():
		return failed
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return failed
	var data: Dictionary = parsed
	if not _is_number(data.get("schema_version")):
		return failed
	var version := int(data["schema_version"])
	if version > SCHEMA_VERSION:
		failed["result"] = _PARSE_NEWER
		return failed
	if version < 1:
		return failed
	var migrated := _migrate(data, version)
	return {
		"result": _PARSE_OK,
		"master_volume": _read_volume(migrated.get("master_volume", DEFAULT_MASTER_VOLUME)),
		"window_mode": _read_window_mode(migrated.get("window_mode", DEFAULT_WINDOW_MODE)),
	}


static func _read_volume(value: Variant) -> float:
	if not _is_number(value):
		return DEFAULT_MASTER_VOLUME
	var volume := float(value)
	if not is_finite(volume):
		return DEFAULT_MASTER_VOLUME
	return clampf(volume, 0.0, 1.0)


static func _read_window_mode(value: Variant) -> String:
	if typeof(value) == TYPE_STRING and value in WINDOW_MODES:
		return value
	return DEFAULT_WINDOW_MODE


static func _is_number(value: Variant) -> bool:
	var kind := typeof(value)
	return kind == TYPE_INT or kind == TYPE_FLOAT


static func _apply_volume(volume: float) -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus < 0:
		return
	var clamped := clampf(volume, 0.0, 1.0)
	AudioServer.set_bus_mute(bus, clamped <= 0.0)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(clamped, 0.0001)))


static func _apply_window_mode(mode: String) -> void:
	var target := DisplayServer.WINDOW_MODE_WINDOWED
	if mode == WINDOW_FULLSCREEN:
		target = DisplayServer.WINDOW_MODE_FULLSCREEN
	if DisplayServer.window_get_mode() == target:
		return
	DisplayServer.window_set_mode(target)


static func _read_text(path: String) -> String:
	return FileAccess.get_file_as_string(path)


static func _write_verified(path: String, contents: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(contents)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return false
	if FileAccess.get_file_as_string(path) != contents:
		return false
	return _parse_text(contents)["result"] == _PARSE_OK


static func _restore_main_from_backup() -> void:
	if not FileAccess.file_exists(BACKUP_PATH):
		return
	var backup_text := _read_text(BACKUP_PATH)
	if _parse_text(backup_text)["result"] != _PARSE_OK:
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(backup_text)
	file.close()


static func _remove_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	dir.remove(path.get_file())
