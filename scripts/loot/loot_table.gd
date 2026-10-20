extends RefCounted
## 掉落表只描述保底、加权一次选择、独立概率。加权用权重，独立概率用 0 到 1，两者不混用。

const PATH := "res://data/loot/loot_tables.json"
const DROP_SCENE := preload("res://scenes/props/world_drop.tscn")
const ItemCatalog := preload("res://scripts/items/item_catalog.gd")
const BuildLoadout := preload("res://scripts/build/build_loadout.gd")

static var _tables: Dictionary = {}
static var _loaded := false


static func roll(table_id: String, seed_value: int) -> Dictionary:
	_ensure()
	if not _tables.has(table_id):
		return _failed(PackedStringArray(["未知掉落表：%s" % table_id]))
	return roll_table(_tables[table_id], seed_value)


static func roll_table(table: Dictionary, seed_value: int) -> Dictionary:
	var errors := diagnose(table)
	if not errors.is_empty():
		return _failed(errors)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var drops: Array = []
	for entry in table.get("entries", []):
		var kind := String(entry.get("kind", ""))
		if kind == "guaranteed":
			_append_drop(entry, rng, drops)
		elif kind == "weighted_choice":
			for _roll in int(entry.get("rolls", 1)):
				var choice: Dictionary = _pick_weighted(entry.get("choices", []), rng)
				if choice.get("empty", false) == true:
					continue
				_append_drop(choice, rng, drops)
		elif kind == "independent_chance":
			if rng.randf() < float(entry.get("chance", 0.0)):
				_append_drop(entry, rng, drops)
	return {"ok": true, "drops": drops, "errors": PackedStringArray()}


static func sources_for_item(item_id: String) -> PackedStringArray:
	return _sources_for("item_id", item_id)


static func sources_for_component(definition_id: String) -> PackedStringArray:
	return _sources_for("component_definition_id", definition_id)


static func sources_text_for_item(item_id: String) -> String:
	return _sources_text(sources_for_item(item_id))


static func diagnose(table: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var table_id := String(table.get("id", ""))
	if table_id == "":
		errors.append("掉落表缺少 id")
	var entries: Variant = table.get("entries", [])
	if typeof(entries) != TYPE_ARRAY or entries.is_empty():
		errors.append("%s 没有条目" % table_id)
		return errors
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("%s 有一条不是对象" % table_id)
			continue
		_diagnose_entry(table_id, entry, errors)
	return errors


static func release_once(host: Node, table_id: String, seed_value: int, into_inventory: bool) -> Dictionary:
	if host.get_meta("loot_released", false) == true:
		return {"ok": true, "drops": [], "errors": PackedStringArray(), "repeat": true}
	host.set_meta("loot_released", true)
	var result := roll(table_id, seed_value if seed_value != 0 else randi())
	if result.ok != true:
		for error in result.errors:
			push_error("LootTable: " + error)
		return result
	for drop in result.drops:
		_give(host, drop, into_inventory)
	result["repeat"] = false
	return result


static func _diagnose_entry(table_id: String, entry: Dictionary, errors: PackedStringArray) -> void:
	var kind := String(entry.get("kind", ""))
	if kind != "guaranteed" and kind != "weighted_choice" and kind != "independent_chance":
		errors.append("%s 未知条目类型：%s" % [table_id, kind])
		return
	if kind == "weighted_choice":
		if entry.has("chance"):
			errors.append("%s 加权条目不能写概率" % table_id)
		var rolls: Variant = entry.get("rolls", 1)
		if not _whole(rolls) or int(rolls) < 1:
			errors.append("%s 加权次数无效" % table_id)
		var choices: Variant = entry.get("choices", [])
		if typeof(choices) != TYPE_ARRAY or choices.is_empty():
			errors.append("%s 加权没有选项" % table_id)
			return
		for choice in choices:
			if typeof(choice) != TYPE_DICTIONARY:
				errors.append("%s 加权选项不是对象" % table_id)
				continue
			if choice.has("chance"):
				errors.append("%s 加权选项不能写概率" % table_id)
			var weight: Variant = choice.get("weight", 0)
			if not _whole(weight) or int(weight) <= 0:
				errors.append("%s 权重必须是正整数" % table_id)
			if choice.get("empty", false) != true:
				_diagnose_reward(table_id, choice, errors)
		return
	if kind == "independent_chance":
		if entry.has("weight"):
			errors.append("%s 独立概率不能写权重" % table_id)
		var chance: Variant = entry.get("chance", -1.0)
		var chance_type := typeof(chance)
		if (chance_type != TYPE_FLOAT and chance_type != TYPE_INT) or float(chance) < 0.0 or float(chance) > 1.0:
			errors.append("%s 独立概率必须在 0 到 1" % table_id)
	elif entry.has("chance") or entry.has("weight"):
		errors.append("%s 保底条目不能写权重或概率" % table_id)
	_diagnose_reward(table_id, entry, errors)


static func _diagnose_reward(table_id: String, reward: Dictionary, errors: PackedStringArray) -> void:
	var has_item := reward.has("item_id")
	var has_component := reward.has("component_definition_id")
	if has_item == has_component:
		errors.append("%s 奖励必须是物品或组件之一" % table_id)
		return
	if has_item:
		var item_id := String(reward.get("item_id", ""))
		if ItemCatalog.get_item(StringName(item_id)).is_empty() and not _is_legacy_item(item_id):
			errors.append("%s 未知物品：%s" % [table_id, item_id])
		_diagnose_count(table_id, reward, errors)
	else:
		var definition_id := String(reward.get("component_definition_id", ""))
		if definition_id == "" or BuildLoadout.new().definition(definition_id).is_empty():
			errors.append("%s 未知组件：%s" % [table_id, definition_id])
		var claim_id := String(reward.get("claim_id", ""))
		if claim_id == "":
			errors.append("%s 组件奖励必须有领取标记" % table_id)
	if reward.has("min_count") or reward.has("max_count"):
		if has_component:
			errors.append("%s 组件奖励不能写数量" % table_id)


static func _diagnose_count(table_id: String, reward: Dictionary, errors: PackedStringArray) -> void:
	var min_count: Variant = reward.get("min_count", 1)
	var max_count: Variant = reward.get("max_count", min_count)
	if not _whole(min_count) or not _whole(max_count) or int(min_count) < 1 or int(max_count) < int(min_count):
		errors.append("%s 数量区间无效" % table_id)


static func _append_drop(reward: Dictionary, rng: RandomNumberGenerator, drops: Array) -> void:
	if reward.has("component_definition_id"):
		drops.append({
			"component_definition_id": String(reward.get("component_definition_id", "")),
			"claim_id": String(reward.get("claim_id", "")),
		})
		return
	var min_count := int(reward.get("min_count", 1))
	var max_count := int(reward.get("max_count", min_count))
	drops.append({
		"item_id": String(reward.get("item_id", "")),
		"amount": rng.randi_range(min_count, max_count),
		"claim_id": String(reward.get("claim_id", "")),
	})


static func _pick_weighted(choices: Array, rng: RandomNumberGenerator) -> Dictionary:
	var total := 0
	for choice in choices:
		total += int(choice.get("weight", 0))
	var ticket := rng.randi_range(1, total)
	var cursor := 0
	for choice in choices:
		cursor += int(choice.get("weight", 0))
		if ticket <= cursor:
			return choice
	return choices.back()


static func _give(host: Node, drop: Dictionary, into_inventory: bool) -> void:
	var claim_id := StringName(String(drop.get("claim_id", "")))
	if claim_id != &"" and ProgressState.is_claimed(claim_id):
		return
	if drop.has("component_definition_id"):
		ProgressState.grant_claimed_instance(claim_id, String(drop.get("component_definition_id", "")))
		return
	var item_id := StringName(String(drop.get("item_id", "")))
	var amount := int(drop.get("amount", 0))
	if claim_id != &"":
		ProgressState.claim_pickup(claim_id, item_id, amount)
		return
	if into_inventory:
		ProgressState.add_item(item_id, amount)
		return
	var parent := host.get_parent()
	if parent == null:
		return
	var definition: ItemDefinition = ProgressState.get_definition(item_id)
	if definition == null:
		return
	var node := DROP_SCENE.instantiate()
	node.item = definition
	node.amount = amount
	node.position = host.position
	parent.add_child.call_deferred(node)


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		push_error("LootTable: 缺少掉落表")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("LootTable: 掉落表不是对象")
		return
	for table in parsed.get("tables", []):
		if typeof(table) != TYPE_DICTIONARY:
			continue
		var table_id := String(table.get("id", ""))
		if table_id == "":
			continue
		var errors := diagnose(table)
		if not errors.is_empty():
			for error in errors:
				push_error("LootTable: " + error)
		_tables[table_id] = table


static func _is_legacy_item(item_id: String) -> bool:
	return item_id == "item_test_hide" or item_id == "item_test_material"


static func _whole(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and is_finite(value) and value == floorf(value)


static func _sources_for(field: String, value: String) -> PackedStringArray:
	_ensure()
	var found: Dictionary = {}
	for table_id in _tables:
		var table: Dictionary = _tables[table_id]
		if _table_has_reward(table, field, value):
			found[_source_label(table)] = true
	var names := PackedStringArray()
	var keys: Array = found.keys()
	keys.sort()
	for name in keys:
		names.append(String(name))
	return names


static func _sources_text(names: PackedStringArray) -> String:
	if names.is_empty():
		return "来源：未录入掉落表"
	return "来源：%s" % "、".join(names)


static func _source_label(table: Dictionary) -> String:
	var label := String(table.get("source_label", ""))
	if label != "":
		return label
	return String(table.get("id", "未知掉落"))


static func _table_has_reward(table: Dictionary, field: String, value: String) -> bool:
	for entry in table.get("entries", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if String(entry.get(field, "")) == value:
			return true
		for choice in entry.get("choices", []):
			if typeof(choice) == TYPE_DICTIONARY and String(choice.get(field, "")) == value:
				return true
	return false


static func _failed(errors: PackedStringArray) -> Dictionary:
	return {"ok": false, "drops": [], "errors": errors}
