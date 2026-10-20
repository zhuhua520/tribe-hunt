extends RefCounted
## 制作配方。只加载产出已在物品表里、且已经实现的武器配方。

const PATH := "res://data/recipes/recipes.json"
const ItemCatalog := preload("res://scripts/items/item_catalog.gd")

static var _by_id: Dictionary = {}
static var _ids: PackedStringArray = PackedStringArray()
static var _loaded := false


static func recipe(recipe_id: String) -> Dictionary:
	_ensure()
	return _by_id.get(recipe_id, {})


static func ids() -> PackedStringArray:
	_ensure()
	return _ids.duplicate()


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		push_error("RecipeCatalog: 缺少配方表")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("RecipeCatalog: 配方表不是对象")
		return
	for entry in parsed.get("recipes", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var recipe_id := String(entry.get("id", ""))
		var output_id := String(entry.get("output_item_id", ""))
		if recipe_id == "" or output_id == "":
			continue
		var output: Dictionary = ItemCatalog.get_item(StringName(output_id))
		if output.is_empty() or String(output.get("category_id", "")) != "weapon":
			push_error("RecipeCatalog: 跳过未实现产出 %s" % output_id)
			continue
		if not _ingredients_ok(entry.get("ingredients", [])):
			push_error("RecipeCatalog: 跳过未知材料 %s" % recipe_id)
			continue
		var blueprint_id := String(entry.get("blueprint_item_id", ""))
		if blueprint_id != "" and ItemCatalog.get_item(StringName(blueprint_id)).is_empty():
			push_error("RecipeCatalog: 跳过未知图纸 %s" % recipe_id)
			continue
		_by_id[recipe_id] = entry
		_ids.append(recipe_id)


static func _ingredients_ok(raw: Variant) -> bool:
	if typeof(raw) != TYPE_ARRAY:
		return false
	for entry in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			return false
		var item_id := String(entry.get("item_id", ""))
		if item_id == "" or int(entry.get("count", 0)) <= 0:
			return false
		if ItemCatalog.get_item(StringName(item_id)).is_empty():
			return false
	return true
