class_name ItemCatalog
extends RefCounted
## 物品总表。以后新增物品只改 data/items/items.json，不要再把物品写进脚本。
## 大类、中类、具体物品分层。数量不写在这里。

const ITEMS_PATH := "res://data/items/items.json"
const EFFECTS_PATH := "res://data/effects/effects.json"

static var _items: Dictionary = {}
static var _effects: Dictionary = {}
static var _item_ids: Array[StringName] = []
static var _definitions: Dictionary = {}
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_read_items()
	_read_effects()


static func get_item(item_id: StringName) -> Dictionary:
	ensure_loaded()
	return _items.get(String(item_id), {})


static func get_effect(effect_id: String) -> Dictionary:
	ensure_loaded()
	return _effects.get(effect_id, {})


static func item_ids() -> Array[StringName]:
	ensure_loaded()
	return _item_ids.duplicate()


static func make_definition(item_id: StringName) -> ItemDefinition:
	ensure_loaded()
	if _definitions.has(item_id):
		return _definitions[item_id]
	var data: Dictionary = get_item(item_id)
	if data.is_empty():
		return null
	var definition := ItemDefinition.new()
	definition.item_id = item_id
	definition.display_name = String(data.get("name", item_id))
	definition.description = _description(data)
	_definitions[item_id] = definition
	return definition


static func _description(data: Dictionary) -> String:
	var text := String(data.get("description", ""))
	if data.get("category_id", "") == "weapon":
		text += "\n攻击力 %s" % str(data.get("attack", 0))
		var effect: Dictionary = get_effect(String(data.get("effect_id", "")))
		if not effect.is_empty():
			text += "\n特效：%s" % String(effect.get("name", ""))
		var abilities: Array = data.get("abilities", [])
		if not abilities.is_empty():
			text += "\n能力：%s" % ", ".join(abilities)
	return text


static func _read_items() -> void:
	var parsed: Variant = _parse_file(ITEMS_PATH)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ItemCatalog: 物品表不是对象")
		return
	for category in parsed.get("categories", []):
		if typeof(category) != TYPE_DICTIONARY:
			continue
		for group in category.get("groups", []):
			if typeof(group) != TYPE_DICTIONARY:
				continue
			for item in group.get("items", []):
				if typeof(item) != TYPE_DICTIONARY or String(item.get("id", "")) == "":
					continue
				var stored: Dictionary = item.duplicate(true)
				stored["category_id"] = String(category.get("id", ""))
				stored["category_name"] = String(category.get("name", ""))
				stored["group_id"] = String(group.get("id", ""))
				stored["group_name"] = String(group.get("name", ""))
				var id := String(stored.id)
				_items[id] = stored
				_item_ids.append(StringName(id))


static func _read_effects() -> void:
	var parsed: Variant = _parse_file(EFFECTS_PATH)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ItemCatalog: 特效表不是对象")
		return
	for effect in parsed.get("effects", []):
		if typeof(effect) != TYPE_DICTIONARY or String(effect.get("id", "")) == "":
			continue
		_effects[String(effect.id)] = effect


static func _parse_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("ItemCatalog: 缺少 " + path)
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))
