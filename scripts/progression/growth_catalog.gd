extends RefCounted
## 经验、测试等级区间和技术表。数量是测试配置，不是最终数值。

const PATH := "res://data/growth/growth.json"

static var _loaded := false
static var _config: Dictionary = {}
static var _techs: Dictionary = {}


static func config() -> Dictionary:
	_ensure()
	return _config.duplicate(true)


static func tech(tech_id: String) -> Dictionary:
	_ensure()
	return _techs.get(tech_id, {})


static func tech_ids() -> PackedStringArray:
	_ensure()
	var ids := PackedStringArray()
	var keys: Array = _techs.keys()
	keys.sort()
	for tech_id in keys:
		ids.append(String(tech_id))
	return ids


static func test_level_range() -> int:
	_ensure()
	return int(_config.get("test_level_range", 3))


static func xp_per_kill() -> int:
	_ensure()
	return int(_config.get("xp_per_kill", 1))


static func xp_per_level() -> int:
	_ensure()
	return int(_config.get("xp_per_level", 2))


static func hp_per_level() -> int:
	_ensure()
	return int(_config.get("hp_per_level", 1))


static func flat_damage_per_level() -> int:
	_ensure()
	return int(_config.get("flat_damage_per_level", 1))


static func base_max_hp() -> int:
	_ensure()
	return int(_config.get("base_max_hp", 8))


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_config = {
		"base_max_hp": 8,
		"test_level_range": 3,
		"xp_per_kill": 1,
		"xp_per_level": 2,
		"hp_per_level": 1,
		"flat_damage_per_level": 1,
	}
	if not FileAccess.file_exists(PATH):
		push_error("GrowthCatalog: 缺少成长表")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("GrowthCatalog: 成长表不是对象")
		return
	for key in _config.keys():
		if parsed.has(key) and typeof(parsed.get(key)) == TYPE_INT:
			_config[key] = int(parsed.get(key))
		elif parsed.has(key) and typeof(parsed.get(key)) == TYPE_FLOAT and is_finite(parsed.get(key)) and parsed.get(key) == floorf(parsed.get(key)):
			_config[key] = int(parsed.get(key))
	for entry in parsed.get("techs", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var tech_id := String(entry.get("id", ""))
		if tech_id == "":
			continue
		_techs[tech_id] = entry
