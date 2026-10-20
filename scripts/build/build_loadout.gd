extends RefCounted
## 构筑实例和预设。发放测试包本身不写盘；回村安全点会把当前快照写入进度。旧样例模块目录不从这里读取。

signal changed

const COMPONENTS_PATH := "res://data/build/components.json"
const AffixPool := preload("res://scripts/build/affix_pool.gd")
const PRESET_A := "preset_a"
const PRESET_B := "preset_b"
## 测试上限与消耗，不是最终数值。
const ENHANCE_CAP := 3
const ENHANCE_COST_ITEM := "material_fiber"
const ENHANCE_COST_COUNT := 1
const ENHANCE_FLAT_DAMAGE := 1

var _definitions: Dictionary = {}
var instances: Dictionary = {}
var presets: Array = []
var active_build_id: String = ""
var discovered: Dictionary = {}
var _loaded := false


func clear() -> void:
	instances.clear()
	presets.clear()
	active_build_id = ""
	discovered.clear()
	changed.emit()


func grant_test_pack() -> String:
	_ensure_definitions()
	if instances.is_empty():
		_add_instance("inst_core", "core_test_damage")
		_add_instance("inst_haste_a", "support_haste")
		_add_instance("inst_haste_b", "support_haste")
		_add_instance("inst_reach", "support_reach")
		_add_instance("inst_projectile", "support_projectile")
		_add_instance("inst_echo", "core_echo")
		_add_instance("inst_break", "core_break")
		_add_instance("inst_echo_range", "support_echo_range")
		_add_instance("inst_break_power", "support_break_power")
		_add_instance("inst_hunt", "core_hunt")
		_add_instance("inst_shield_time", "support_shield_time")
		presets = [
			_empty_preset(PRESET_A, "试验甲"),
			_empty_preset(PRESET_B, "试验乙"),
		]
		active_build_id = PRESET_A
		changed.emit()
	return "构筑测试包只在本进程，没有写入存档。回村后才会保存。"


func definition(definition_id: String) -> Dictionary:
	_ensure_definitions()
	return _definitions.get(definition_id, {})


func instance(instance_id: String) -> Dictionary:
	return instances.get(instance_id, {})


func active_preset() -> Dictionary:
	for preset in presets:
		if String(preset.get("build_id", "")) == active_build_id:
			return preset
	return {}


func export_state() -> Dictionary:
	var found: Array = discovered.keys()
	found.sort()
	return {
		"active_build_id": active_build_id,
		"instances": instances.duplicate(true),
		"presets": presets.duplicate(true),
		"discovered": found,
	}


func replace_from_save(data: Dictionary) -> void:
	instances.clear()
	var saved_instances: Dictionary = data.get("instances", {})
	for instance_id in saved_instances:
		var inst: Variant = saved_instances[instance_id]
		if typeof(inst) == TYPE_DICTIONARY:
			instances[String(instance_id)] = inst.duplicate(true)
	presets.clear()
	for preset in data.get("presets", []):
		if typeof(preset) == TYPE_DICTIONARY:
			presets.append(preset.duplicate(true))
	active_build_id = String(data.get("active_build_id", ""))
	discovered.clear()
	for definition_id in data.get("discovered", []):
		var id := String(definition_id)
		if id != "":
			discovered[id] = true
	for instance_id in instances:
		var definition_id := String(instance(String(instance_id)).get("definition_id", ""))
		if definition_id != "":
			discovered[definition_id] = true
	changed.emit()


## raw 为 null 表示旧档没有构筑字段，静默补两套空预设。无效引用会卸下并写入 warnings。
static func saved_build(raw: Variant, warnings: PackedStringArray) -> Dictionary:
	if raw == null:
		return _default_build()
	if typeof(raw) != TYPE_DICTIONARY:
		warnings.append("忽略无效构筑")
		return _default_build()
	var definitions := _read_definitions()
	var instances := {}
	var raw_instances: Variant = raw.get("instances", {})
	if typeof(raw_instances) != TYPE_DICTIONARY:
		warnings.append("忽略无效组件列表")
		raw_instances = {}
	for instance_id in raw_instances:
		if not _valid_saved_id(instance_id):
			warnings.append("忽略无效组件：%s" % str(instance_id))
			continue
		var inst: Variant = raw_instances[instance_id]
		if typeof(inst) != TYPE_DICTIONARY:
			warnings.append("忽略无效组件：%s" % str(instance_id))
			continue
		var definition_id := String(inst.get("definition_id", ""))
		if not _valid_saved_id(definition_id):
			warnings.append("忽略无效组件：%s" % str(instance_id))
			continue
		var level := 1
		if inst.has("level") and not _whole_level(inst.get("level")):
			warnings.append("忽略无效组件等级：%s" % str(instance_id))
		elif inst.has("level"):
			level = int(inst.get("level"))
		var locked := false
		if inst.has("locked") and typeof(inst.get("locked")) != TYPE_BOOL:
			warnings.append("忽略无效锁定：%s" % str(instance_id))
		elif inst.get("locked", false) == true:
			locked = true
		var affixes := _read_affixes(inst, String(instance_id), warnings)
		if not definitions.has(definition_id):
			warnings.append("保留未知组件：%s" % str(instance_id))
		instances[String(instance_id)] = {
			"instance_id": String(instance_id),
			"definition_id": definition_id,
			"level": level,
			"locked": locked,
			"affixes": affixes,
		}
	var presets: Array = []
	var seen_builds := {}
	var raw_presets: Variant = raw.get("presets", [])
	if typeof(raw_presets) != TYPE_ARRAY:
		warnings.append("忽略无效预设")
		raw_presets = []
	for entry in raw_presets:
		if typeof(entry) != TYPE_DICTIONARY or not _valid_saved_id(entry.get("build_id", "")):
			warnings.append("忽略无效预设")
			continue
		var build_id := String(entry.get("build_id"))
		if seen_builds.has(build_id):
			warnings.append("忽略重复预设：%s" % build_id)
			continue
		seen_builds[build_id] = true
		var preset_name := "预设"
		var given_name: Variant = entry.get("name", "")
		if typeof(given_name) == TYPE_STRING and not given_name.is_empty() and given_name.length() <= 32:
			preset_name = given_name
		elif entry.has("name") and given_name != "":
			warnings.append("忽略无效预设名：%s" % build_id)
		var preset := {
			"build_id": build_id,
			"name": preset_name,
			"core": "",
			"support_0": "",
			"support_1": "",
		}
		var used_instances := {}
		var used_supports := {}
		for slot in ["core", "support_0", "support_1"]:
			var slot_value: Variant = entry.get(slot, "")
			if typeof(slot_value) != TYPE_STRING or slot_value == "":
				if entry.has(slot) and slot_value != "":
					warnings.append("预设%s的%s引用无效，已卸下" % [preset_name, _slot_label(slot)])
				continue
			if not instances.has(slot_value):
				warnings.append("预设%s的%s引用无效，已卸下" % [preset_name, _slot_label(slot)])
				continue
			if used_instances.has(slot_value):
				warnings.append("预设%s不能把同一个实例装进两个槽，已卸下" % preset_name)
				continue
			var definition_id := String(instances[slot_value].get("definition_id", ""))
			var component: Dictionary = definitions.get(definition_id, {})
			var role := String(component.get("role", ""))
			if not component.is_empty():
				var expected := "core" if slot == "core" else "support"
				if role != expected:
					warnings.append("预设%s的%s类型不符，已卸下" % [preset_name, _slot_label(slot)])
					continue
			if slot != "core" and used_supports.has(definition_id):
				warnings.append("预设%s不能装两个相同的辅助，已卸下" % preset_name)
				continue
			preset[slot] = slot_value
			used_instances[slot_value] = true
			if slot != "core":
				used_supports[definition_id] = true
		presets.append(preset)
	var discovered := {}
	var raw_discovered: Variant = raw.get("discovered", [])
	if raw.has("discovered") and typeof(raw_discovered) != TYPE_ARRAY:
		warnings.append("忽略无效图鉴")
		raw_discovered = []
	if typeof(raw_discovered) == TYPE_ARRAY:
		for definition_id in raw_discovered:
			if _valid_saved_id(definition_id):
				discovered[String(definition_id)] = true
	for instance_id in instances:
		var definition_id := String(instances[instance_id].get("definition_id", ""))
		if definition_id != "":
			discovered[definition_id] = true
	if presets.is_empty():
		var given_presets: Variant = raw.get("presets", [])
		var given_empty := false
		if typeof(given_presets) == TYPE_ARRAY:
			var given_array: Array = given_presets
			given_empty = given_array.is_empty()
		if raw.has("presets") and not given_empty:
			warnings.append("没有可用预设，已重建空预设")
		presets = _default_build().presets
	var active := ""
	if raw.has("active_build_id"):
		var given_active: Variant = raw.get("active_build_id")
		if typeof(given_active) == TYPE_STRING and given_active != "" and _preset_exists(presets, given_active):
			active = given_active
		elif typeof(given_active) == TYPE_STRING and given_active == "":
			active = String(presets[0].get("build_id", ""))
		else:
			warnings.append("忽略无效激活预设")
			active = String(presets[0].get("build_id", ""))
	else:
		active = String(presets[0].get("build_id", ""))
	var found: Array = discovered.keys()
	found.sort()
	return {
		"active_build_id": active,
		"instances": instances,
		"presets": presets,
		"discovered": found,
	}


static func _default_build() -> Dictionary:
	return {
		"active_build_id": PRESET_A,
		"instances": {},
		"presets": [
			_empty_preset(PRESET_A, "试验甲"),
			_empty_preset(PRESET_B, "试验乙"),
		],
		"discovered": [],
	}


static func _preset_exists(presets: Array, build_id: String) -> bool:
	for preset in presets:
		if String(preset.get("build_id", "")) == build_id:
			return true
	return false


static func _slot_label(slot: String) -> String:
	return "核心" if slot == "core" else "辅助"


static func _valid_saved_id(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty() and value.length() <= 128


static func _whole_level(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return value >= 1
	return typeof(value) == TYPE_FLOAT and is_finite(value) and value == floorf(value) and value >= 1.0


static func _read_definitions() -> Dictionary:
	var definitions := {}
	if not FileAccess.file_exists(COMPONENTS_PATH):
		return definitions
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(COMPONENTS_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return definitions
	for component in parsed.get("components", []):
		if typeof(component) != TYPE_DICTIONARY:
			continue
		var id := String(component.get("id", ""))
		if id != "":
			definitions[id] = component
	return definitions


func add_instance(instance_id: String, definition_id: String) -> String:
	_ensure_definitions()
	if not _valid_saved_id(instance_id):
		return "无效实例"
	if instances.has(instance_id):
		return "已经拥有这个实例"
	if definition(definition_id).is_empty():
		return "未知组件"
	_add_instance(instance_id, definition_id)
	changed.emit()
	return ""


func set_active_preset(build_id: String) -> String:
	for preset in presets:
		if String(preset.get("build_id", "")) == build_id:
			active_build_id = build_id
			changed.emit()
			return ""
	return "没有这个预设"


func set_slot(slot: String, instance_id: String) -> String:
	var preset: Dictionary = active_preset()
	if preset.is_empty():
		return "没有激活的预设"
	if instance_id == "":
		preset[slot] = ""
		changed.emit()
		return ""
	var inst: Dictionary = instance(instance_id)
	if inst.is_empty():
		return "未知实例"
	var comp: Dictionary = definition(String(inst.get("definition_id", "")))
	if comp.is_empty():
		return "未知组件"
	var role := String(comp.get("role", ""))
	if slot == "core" and role != "core":
		return "核心槽只能装核心"
	if slot.begins_with("support") and role != "support":
		return "辅助槽只能装辅助"
	if _slot_holds_instance(preset, instance_id, slot):
		return "这个实例已经装在另一个槽"
	if role == "support" and _support_definition_taken(preset, String(comp.get("id", "")), slot):
		return "不能装两个相同的辅助"
	preset[slot] = instance_id
	changed.emit()
	return ""


func try_equip(instance_id: String) -> String:
	var inst: Dictionary = instance(instance_id)
	if inst.is_empty():
		return "未知实例"
	var comp: Dictionary = definition(String(inst.get("definition_id", "")))
	var role := String(comp.get("role", ""))
	var preset: Dictionary = active_preset()
	if preset.is_empty():
		return "没有激活的预设"
	if role == "core":
		return set_slot("core", instance_id)
	if String(preset.get("support_0", "")) == "":
		return set_slot("support_0", instance_id)
	if String(preset.get("support_1", "")) == "":
		return set_slot("support_1", instance_id)
	return "辅助槽已满"


func _slot_holds_instance(preset: Dictionary, instance_id: String, except_slot: String) -> bool:
	for slot in ["core", "support_0", "support_1"]:
		if slot == except_slot:
			continue
		if String(preset.get(slot, "")) == instance_id:
			return true
	return false


func _affix_text(inst: Dictionary) -> String:
	var mods: Dictionary = AffixPool.mods_for(inst)
	var lines: PackedStringArray = mods.get("lines", PackedStringArray())
	if lines.is_empty():
		return "无副词条"
	return " / ".join(lines)


static func _read_affixes(inst: Dictionary, instance_id: String, warnings: PackedStringArray) -> Array:
	if not inst.has("affixes"):
		return []
	var raw: Variant = inst.get("affixes")
	if typeof(raw) != TYPE_ARRAY:
		warnings.append("忽略无效词条：%s" % instance_id)
		return []
	var kept: Array = []
	var seen := {}
	for entry in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			warnings.append("忽略无效词条：%s" % instance_id)
			continue
		var affix_id := String(entry.get("id", ""))
		var spec: Dictionary = AffixPool.catalog().get(affix_id, {})
		var value: Variant = entry.get("value", null)
		var range_error := ""
		if not spec.is_empty():
			range_error = AffixPool.check_range(spec.get("min", null), spec.get("max", null))
		var value_ok: bool = typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value) and value == floorf(value))
		var inside := false
		if spec.is_empty() or range_error != "" or not value_ok:
			inside = false
		else:
			inside = int(value) >= int(spec.get("min", 0)) and int(value) <= int(spec.get("max", 0))
		if spec.is_empty() or not inside or seen.has(affix_id):
			warnings.append("忽略无效词条：%s" % instance_id)
			continue
		seen[affix_id] = true
		kept.append({"id": affix_id, "value": int(value)})
	return kept


func _support_definition_taken(preset: Dictionary, definition_id: String, except_slot: String) -> bool:
	for slot in ["support_0", "support_1"]:
		if slot == except_slot:
			continue
		var other: Dictionary = instance(String(preset.get(slot, "")))
		if String(other.get("definition_id", "")) == definition_id:
			return true
	return false


func _add_instance(instance_id: String, definition_id: String, affixes: Array = []) -> void:
	instances[instance_id] = {
		"instance_id": instance_id,
		"definition_id": definition_id,
		"level": 1,
		"locked": false,
		"affixes": affixes.duplicate(true),
	}
	if definition_id != "":
		discovered[definition_id] = true


func create_random_instance(instance_id: String, definition_id: String, seed_value: int) -> String:
	_ensure_definitions()
	if not _valid_saved_id(instance_id):
		return "无效实例"
	if instances.has(instance_id):
		return "已经拥有这个实例"
	var comp: Dictionary = definition(definition_id)
	if comp.is_empty():
		return "未知组件"
	var pool: Variant = comp.get("affix_pool", [])
	if typeof(pool) != TYPE_ARRAY:
		return "词条池无效"
	var rolled: Dictionary = AffixPool.roll(pool, seed_value)
	if rolled.get("ok", false) != true:
		return String(rolled.get("error", "词条池无效"))
	_add_instance(instance_id, definition_id, rolled.get("affixes", []))
	changed.emit()
	return ""


func set_locked(instance_id: String, locked: bool) -> String:
	if not instances.has(instance_id):
		return "未知实例"
	instances[instance_id]["locked"] = locked
	changed.emit()
	return ""


func is_referenced(instance_id: String) -> bool:
	for preset in presets:
		for slot in ["core", "support_0", "support_1"]:
			if String(preset.get(slot, "")) == instance_id:
				return true
	return false


func dismantle_blocked_reason(instance_id: String, confirm_unequip: bool = false) -> String:
	if not instances.has(instance_id):
		return "未知实例"
	if instances[instance_id].get("locked", false) == true:
		return "已锁定，不能拆解"
	if is_referenced(instance_id) and not confirm_unequip:
		return "还装在预设里，需要确认卸下再拆"
	return ""


func dismantle(instance_id: String, confirm_unequip: bool = false) -> String:
	var reason := dismantle_blocked_reason(instance_id, confirm_unequip)
	if reason != "":
		return reason
	for preset in presets:
		for slot in ["core", "support_0", "support_1"]:
			if String(preset.get(slot, "")) == instance_id:
				preset[slot] = ""
	instances.erase(instance_id)
	changed.emit()
	return ""


func enhance_blocked_reason(instance_id: String) -> String:
	if not instances.has(instance_id):
		return "未知实例"
	if int(instances[instance_id].get("level", 1)) >= ENHANCE_CAP:
		return "已到测试上限"
	return ""


func enhance(instance_id: String) -> String:
	var reason := enhance_blocked_reason(instance_id)
	if reason != "":
		return reason
	instances[instance_id]["level"] = int(instances[instance_id].get("level", 1)) + 1
	changed.emit()
	return ""


func has_discovered(definition_id: String) -> bool:
	return discovered.has(definition_id)


func definition_ids() -> PackedStringArray:
	_ensure_definitions()
	var ids := PackedStringArray()
	var keys: Array = _definitions.keys()
	keys.sort()
	for definition_id in keys:
		ids.append(String(definition_id))
	return ids


func discovered_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	var keys: Array = discovered.keys()
	keys.sort()
	for definition_id in keys:
		ids.append(String(definition_id))
	return ids


func discovered_text() -> String:
	_ensure_definitions()
	var names := PackedStringArray()
	for definition_id in discovered_ids():
		var comp: Dictionary = definition(String(definition_id))
		names.append(String(comp.get("name", definition_id)))
	if names.is_empty():
		return "还没有发现组件"
	return "已发现：%s" % "、".join(names)


func compare_text() -> String:
	var grouped := {}
	for instance_id in instances:
		var inst: Dictionary = instance(String(instance_id))
		var definition_id := String(inst.get("definition_id", ""))
		if not grouped.has(definition_id):
			grouped[definition_id] = []
		grouped[definition_id].append(String(instance_id))
	var lines: PackedStringArray = PackedStringArray()
	for definition_id in grouped:
		var ids: Array = grouped[definition_id]
		if ids.size() < 2:
			continue
		var comp: Dictionary = definition(definition_id)
		lines.append("%s · 星级 %d" % [String(comp.get("name", definition_id)), int(comp.get("star", 1))])
		for instance_id in ids:
			lines.append("%s %s" % [instance_id, _affix_text(instance(String(instance_id)))])
	if lines.is_empty():
		return "没有可比较的同名组件"
	return "\n".join(lines)


static func _empty_preset(build_id: String, display_name: String) -> Dictionary:
	return {
		"build_id": build_id,
		"name": display_name,
		"core": "",
		"support_0": "",
		"support_1": "",
	}


func _ensure_definitions() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(COMPONENTS_PATH):
		push_error("BuildLoadout: 缺少组件表")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(COMPONENTS_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("BuildLoadout: 组件表不是对象")
		return
	for component in parsed.get("components", []):
		if typeof(component) != TYPE_DICTIONARY:
			continue
		var id := String(component.get("id", ""))
		if id == "":
			continue
		_definitions[id] = component
