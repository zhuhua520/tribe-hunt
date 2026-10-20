extends CanvasLayer
## 合成铺配方页。复用店铺页的列表+说明+离开结构。无货币，不是买卖。

const RecipeCatalog := preload("res://scripts/items/recipe_catalog.gd")
const ItemCatalog := preload("res://scripts/items/item_catalog.gd")
const ModalStack := preload("res://scripts/ui/modal_stack.gd")
const THEME := preload("res://data/ui/ui_theme.tres")

@onready var _root: Control = $Root
@onready var _title: Label = $Root/Center/Panel/Margin/VBox/TitleLabel
@onready var _list: ItemList = $Root/Center/Panel/Margin/VBox/ItemList
@onready var _detail: Label = $Root/Center/Panel/Margin/VBox/DetailLabel
@onready var _craft_button: Button = $Root/Center/Panel/Margin/VBox/CraftButton
@onready var _close: Button = $Root/Center/Panel/Margin/VBox/CloseButton

var _recipe_ids: PackedStringArray = PackedStringArray()
var _selected: String = ""


func _ready() -> void:
	_root.visible = false
	_root.theme = THEME
	_list.item_selected.connect(_on_selected)
	_craft_button.pressed.connect(_on_craft_pressed)
	_close.pressed.connect(close)


func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible or event.is_echo() or not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	close()


func is_open() -> bool:
	return _root.visible


func row_count() -> int:
	return _list.item_count


func detail_text() -> String:
	return _detail.text


func selected_recipe_id() -> String:
	return _selected


func open_recipes() -> void:
	ModalStack.close_all_except(self)
	_title.text = "合成铺"
	_refresh_list()
	_root.visible = true
	ModalStack.push(self)
	_close.grab_focus()


func close() -> void:
	_root.visible = false
	ModalStack.pop(self)


func try_craft_selected() -> String:
	if _selected == "":
		return "没有选中配方"
	return ProgressState.craft_recipe(_selected)


func _refresh_list() -> void:
	_recipe_ids = RecipeCatalog.ids()
	_list.clear()
	for recipe_id in _recipe_ids:
		var recipe: Dictionary = RecipeCatalog.recipe(recipe_id)
		var line := String(recipe.get("name", recipe_id))
		var reason := ProgressState.craft_blocked_reason(recipe_id)
		if reason != "":
			line += "　%s" % reason
		else:
			line += "　可制作"
		_list.add_item(line)
	if _recipe_ids.is_empty():
		_selected = ""
		_detail.text = "还没有可做的配方。"
		_craft_button.disabled = true
		return
	var index := 0
	if _selected != "":
		var found := _recipe_ids.find(_selected)
		if found >= 0:
			index = found
	_list.select(index)
	_on_selected(index)


func _on_selected(index: int) -> void:
	if index < 0 or index >= _recipe_ids.size():
		return
	_selected = _recipe_ids[index]
	var recipe: Dictionary = RecipeCatalog.recipe(_selected)
	var output: Dictionary = ItemCatalog.get_item(StringName(recipe.get("output_item_id", "")))
	var lines := PackedStringArray()
	lines.append("做成：%s ×%d" % [String(output.get("name", recipe.get("output_item_id", ""))), int(recipe.get("output_count", 1))])
	var blueprint_id := String(recipe.get("blueprint_item_id", ""))
	if blueprint_id != "":
		var blueprint: Dictionary = ItemCatalog.get_item(StringName(blueprint_id))
		var held := ProgressState.item_count(StringName(blueprint_id))
		lines.append("图纸：%s（持有 %d，制作不消耗）" % [String(blueprint.get("name", blueprint_id)), held])
	var tech_id := String(recipe.get("tech_id", ""))
	if tech_id != "":
		var tech: Dictionary = preload("res://scripts/progression/growth_catalog.gd").tech(tech_id)
		var unlocked := ProgressState.has_tech(tech_id)
		lines.append("技术：%s（%s）" % [String(tech.get("name", tech_id)), "已解锁" if unlocked else "未解锁"])
	for entry in recipe.get("ingredients", []):
		var item_id := StringName(entry.get("item_id", ""))
		var need := int(entry.get("count", 0))
		var item: Dictionary = ItemCatalog.get_item(item_id)
		lines.append("材料：%s %d/%d" % [String(item.get("name", item_id)), ProgressState.item_count(item_id), need])
		var purpose := String(item.get("description", ""))
		if purpose != "":
			lines.append(purpose)
	var note := String(recipe.get("note", ""))
	if note != "":
		lines.append(note)
	var reason := ProgressState.craft_blocked_reason(_selected)
	if reason != "":
		lines.append(reason)
	_detail.text = "\n".join(lines)
	_craft_button.disabled = reason != ""


func _on_craft_pressed() -> void:
	_craft_button.disabled = true
	var reason := try_craft_selected()
	_refresh_list()
	if reason == "":
		_detail.text = "做成了。材料已扣除，回村存档已写入。"
	elif _detail.text.find(reason) < 0:
		_detail.text += "\n" + reason
