extends RefCounted
## 探索区域的静态配置。威胁、敌群和唯一奖励都写在表里，不按玩家等级改。

const PATH := "res://data/regions/regions.json"

static var _by_id: Dictionary = {}
static var _loaded := false


static func region(region_id: String) -> Dictionary:
	_ensure()
	return _by_id.get(region_id, {})


static func ids() -> PackedStringArray:
	_ensure()
	return PackedStringArray(_by_id.keys())


static func region_for_scene(scene_path: String) -> Dictionary:
	_ensure()
	for region_id in _by_id:
		var entry: Dictionary = _by_id[region_id]
		if String(entry.get("scene_path", "")) == scene_path:
			return entry
	return {}


static func display_name_for_scene(scene_path: String) -> String:
	var info: Dictionary = region_for_scene(scene_path)
	if not info.is_empty():
		return String(info.get("name", scene_path))
	match scene_path:
		"res://scenes/village/village.tscn":
			return "部落村落"
		"res://scenes/exploration/action_training.tscn":
			return "动作试验场"
		"res://scenes/combat/arena.tscn":
			return "旧竞技场"
		_:
			return "未知区域"


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		push_error("RegionCatalog: 缺少区域表")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("RegionCatalog: 区域表不是对象")
		return
	for entry in parsed.get("regions", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var region_id := String(entry.get("id", ""))
		if region_id == "":
			continue
		_by_id[region_id] = entry
