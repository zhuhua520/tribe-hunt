extends RefCounted
## 玩家进度存档（默认 user://progress.json），与 settings.json 分开。
## 写入顺序：写临时文件并回读校验 → 主文件改名为备份 → 临时文件改名为主文件。
## 任一步中断时，主文件或备份至少保留一份上次的有效进度；读取时主文件无效会退回备份。

enum LoadStatus { OK, MISSING, RESTORED_FROM_BACKUP, CORRUPT, NEWER_VERSION }

const SCHEMA_VERSION := 1
const MAX_ITEM_COUNT := 999999
const MAX_ID_LENGTH := 128
const DEFAULT_SCENE_ID := "village"
const DEFAULT_ENTRY_ID := "default"
## 只有安全点场景可以作为继续位置。
const SAFE_SCENES := {
	"village": "res://scenes/village/village.tscn",
}

var main_path: String
var temp_path: String
var backup_path: String
var corrupt_path: String
## 仅测试用：备份已改名、临时文件尚未提交时模拟提交失败。
var fail_commit_after_backup: bool = false


func _init(path: String = "user://progress.json") -> void:
	main_path = path
	temp_path = path + ".tmp"
	backup_path = path + ".bak"
	corrupt_path = path + ".corrupt"


## 返回 {status, data, warnings}。data 已通过校验，可直接使用；失败时为 null。
func load_data(known_item_ids: Array) -> Dictionary:
	var warnings := PackedStringArray()
	if FileAccess.file_exists(main_path):
		var main := parse_text(FileAccess.get_file_as_string(main_path), known_item_ids, warnings)
		if main.status != LoadStatus.CORRUPT:
			return _result(main.status, main.data, warnings)
		warnings.append("主进度文件无法读取，尝试备份")
	if FileAccess.file_exists(backup_path):
		var backup := parse_text(FileAccess.get_file_as_string(backup_path), known_item_ids, warnings)
		if backup.status == LoadStatus.OK:
			return _result(LoadStatus.RESTORED_FROM_BACKUP, backup.data, warnings)
		if backup.status == LoadStatus.NEWER_VERSION:
			return _result(LoadStatus.NEWER_VERSION, null, warnings)
	if FileAccess.file_exists(main_path) or FileAccess.file_exists(backup_path):
		return _result(LoadStatus.CORRUPT, null, warnings)
	return _result(LoadStatus.MISSING, null, warnings)


func save_data(data: Dictionary, known_item_ids: Array) -> bool:
	var text := JSON.stringify(data, "\t") + "\n"
	if not _write_verified(temp_path, text, known_item_ids):
		push_warning("ProgressStore: 临时文件写入或校验失败，保留原进度")
		_remove(temp_path)
		return false
	if FileAccess.file_exists(main_path):
		_remove(backup_path)
		if DirAccess.rename_absolute(main_path, backup_path) != OK:
			push_warning("ProgressStore: 无法把主文件转为备份，保留原进度")
			_remove(temp_path)
			return false
	if fail_commit_after_backup:
		push_warning("ProgressStore: 模拟提交失败")
		return false
	if DirAccess.rename_absolute(temp_path, main_path) != OK:
		push_warning("ProgressStore: 提交主文件失败，备份仍可恢复")
		return false
	return true


## 把无法读取的主文件移到 .corrupt，之后的保存不会覆盖它。
func quarantine_corrupt() -> void:
	if not FileAccess.file_exists(main_path):
		return
	_remove(corrupt_path)
	DirAccess.rename_absolute(main_path, corrupt_path)


func delete_files_for_tests() -> void:
	for path in [main_path, temp_path, backup_path, corrupt_path]:
		_remove(path)


## 解析并校验。结构错误为 CORRUPT；单个条目无效或未知 ID 会丢弃并记入 warnings。
static func parse_text(text: String, known_item_ids: Array, warnings: PackedStringArray) -> Dictionary:
	var json := JSON.new()
	if text.is_empty() or json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {"status": LoadStatus.CORRUPT, "data": null}
	var raw: Dictionary = json.data
	if not _is_whole_number(raw.get("schema_version")):
		return {"status": LoadStatus.CORRUPT, "data": null}
	var version := int(raw["schema_version"])
	if version > SCHEMA_VERSION:
		return {"status": LoadStatus.NEWER_VERSION, "data": null}
	if version < 1:
		return {"status": LoadStatus.CORRUPT, "data": null}
	if typeof(raw.get("items")) != TYPE_DICTIONARY or typeof(raw.get("claimed_objects")) != TYPE_ARRAY:
		return {"status": LoadStatus.CORRUPT, "data": null}
	var data := {
		"schema_version": SCHEMA_VERSION,
		"location": _read_location(raw.get("location"), warnings),
		"items": {},
		"claimed_objects": [],
	}
	var items: Dictionary = raw["items"]
	for key in items:
		var count: Variant = items[key]
		if typeof(key) != TYPE_STRING or not (StringName(key) in known_item_ids):
			warnings.append("忽略未知物品 ID：%s" % str(key))
		elif not _is_whole_number(count) or int(count) < 0 or int(count) > MAX_ITEM_COUNT:
			warnings.append("忽略无效物品数量：%s=%s" % [key, str(count)])
		elif int(count) > 0:
			data.items[key] = int(count)
	for object_id in raw["claimed_objects"]:
		if _is_valid_id(object_id):
			if not (object_id in data.claimed_objects):
				data.claimed_objects.append(object_id)
		else:
			warnings.append("忽略无效对象 ID：%s" % str(object_id))
	return {"status": LoadStatus.OK, "data": data}


static func _read_location(value: Variant, warnings: PackedStringArray) -> Dictionary:
	var location := {"scene_id": DEFAULT_SCENE_ID, "entry_id": DEFAULT_ENTRY_ID}
	if typeof(value) != TYPE_DICTIONARY:
		warnings.append("缺少继续位置，使用村落默认入口")
		return location
	var scene_id: Variant = value.get("scene_id")
	if typeof(scene_id) == TYPE_STRING and SAFE_SCENES.has(scene_id):
		location.scene_id = scene_id
	else:
		warnings.append("未知继续场景 ID：%s" % str(scene_id))
	var entry_id: Variant = value.get("entry_id")
	if _is_valid_id(entry_id):
		location.entry_id = entry_id
	else:
		warnings.append("无效入口 ID：%s" % str(entry_id))
	return location


static func _is_valid_id(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty() and value.length() <= MAX_ID_LENGTH


static func _is_whole_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and is_finite(value) and value == floorf(value)


func _write_verified(path: String, text: String, known_item_ids: Array) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or FileAccess.get_file_as_string(path) != text:
		return false
	return parse_text(text, known_item_ids, PackedStringArray()).status == LoadStatus.OK


func _result(status: int, data: Variant, warnings: PackedStringArray) -> Dictionary:
	for warning in warnings:
		push_warning("ProgressStore: " + warning)
	return {"status": status, "data": data, "warnings": warnings}


static func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
