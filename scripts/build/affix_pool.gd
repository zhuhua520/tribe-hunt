extends RefCounted
## 副词条在实例生成时抽一次。星级不在这里随机。

const PATH := "res://data/build/affixes.json"

static var _catalog: Dictionary = {}
static var _loaded := false


static func roll(pool: Array, seed_value: int) -> Dictionary:
	var error := check_pool(pool)
	if error != "":
		return {"ok": false, "affixes": [], "error": error}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var ids: Array = pool.duplicate()
	for index in range(ids.size() - 1, 0, -1):
		var swap_at := rng.randi_range(0, index)
		var swapped = ids[index]
		ids[index] = ids[swap_at]
		ids[swap_at] = swapped
	var affixes: Array = []
	for pick in 2:
		var affix_id := String(ids[pick])
		var spec: Dictionary = catalog().get(affix_id, {})
		affixes.append({
			"id": affix_id,
			"value": rng.randi_range(int(spec.get("min", 0)), int(spec.get("max", 0))),
		})
	return {"ok": true, "affixes": affixes, "error": ""}


static func check_pool(pool: Array) -> String:
	if pool.size() < 2:
		return "词条池不足两种"
	var seen := {}
	for entry in pool:
		var affix_id := String(entry)
		if seen.has(affix_id):
			return "词条池重复"
		seen[affix_id] = true
		var spec: Dictionary = catalog().get(affix_id, {})
		if spec.is_empty():
			return "未知词条"
		var error := check_range(spec.get("min", null), spec.get("max", null))
		if error != "":
			return error
	return ""


static func check_range(min_value: Variant, max_value: Variant) -> String:
	if not _finite_number(min_value) or not _finite_number(max_value):
		return "词条数值无效"
	if float(min_value) > float(max_value):
		return "词条区间无效"
	return ""


static func catalog() -> Dictionary:
	_ensure()
	return _catalog


static func mods_for(inst: Dictionary) -> Dictionary:
	var mods := {
		"flat_damage": 0,
		"range_flat": 0.0,
		"interval_percent": 0.0,
	}
	var lines: PackedStringArray = PackedStringArray()
	for entry in inst.get("affixes", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var spec: Dictionary = catalog().get(String(entry.get("id", "")), {})
		if spec.is_empty():
			continue
		var stat := String(spec.get("stat", ""))
		var value := int(entry.get("value", 0))
		if stat == "flat_damage":
			mods["flat_damage"] = int(mods["flat_damage"]) + value
		elif stat == "range_flat":
			mods["range_flat"] = float(mods["range_flat"]) + float(value)
		elif stat == "interval_percent":
			mods["interval_percent"] = float(mods["interval_percent"]) + float(value)
		lines.append("%s %+d" % [String(spec.get("name", "")), value])
	mods["lines"] = lines
	return mods


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		push_error("AffixPool: 缺少词条表")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("AffixPool: 词条表不是对象")
		return
	for affix in parsed.get("affixes", []):
		if typeof(affix) != TYPE_DICTIONARY:
			continue
		var affix_id := String(affix.get("id", ""))
		if affix_id == "":
			continue
		_catalog[affix_id] = affix


static func _finite_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))
