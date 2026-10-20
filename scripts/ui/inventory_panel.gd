extends CanvasLayer
## 背包界面：列出 ProgressState 中的持有物，选中后显示说明。只读，不改数量。
## 不设格数或容量上限（未定；不恢复旧背包格数规则）。按 inventory 动作开关，ui_cancel 关闭；暂停时不响应。

const Catalog := preload("res://scripts/items/item_catalog.gd")
const LootTable := preload("res://scripts/loot/loot_table.gd")
const ModalStack := preload("res://scripts/ui/modal_stack.gd")
const THEME := preload("res://data/ui/ui_theme.tres")
const UiIcons := preload("res://scripts/ui/ui_icons.gd")

@onready var _root: Control = $Root
@onready var _filter: OptionButton = $Root/Center/Panel/Margin/VBox/FilterRow/FilterOption
@onready var _sort: OptionButton = $Root/Center/Panel/Margin/VBox/FilterRow/SortOption
@onready var _list: ItemList = $Root/Center/Panel/Margin/VBox/ItemList
@onready var _detail_label: Label = $Root/Center/Panel/Margin/VBox/DetailLabel
@onready var _equip_button: Button = $Root/Center/Panel/Margin/VBox/EquipButton
@onready var _close_button: Button = $Root/Center/Panel/Margin/VBox/CloseButton

var _entries: Array = []


func _ready() -> void:
	_root.visible = false
	_root.theme = THEME
	if _filter.item_count == 0:
		for label in ["全部", "武器", "素材", "图纸"]:
			_filter.add_item(label)
	if _sort.item_count == 0:
		for label in ["默认", "名称", "数量"]:
			_sort.add_item(label)
	_filter.selected = 0
	_sort.selected = 0
	ProgressState.items_changed.connect(_refresh)
	_list.item_selected.connect(_show_detail)
	_filter.item_selected.connect(func(_index: int) -> void: _refresh())
	_sort.item_selected.connect(func(_index: int) -> void: _refresh())
	_equip_button.pressed.connect(_open_equipment)
	_close_button.pressed.connect(close)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("inventory"):
		get_viewport().set_input_as_handled()
		toggle()
	elif _root.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func toggle() -> void:
	if _root.visible:
		close()
	else:
		open()


func open() -> void:
	ModalStack.close_all_except(self)
	_refresh()
	_root.visible = true
	ModalStack.push(self)
	if not _entries.is_empty():
		_list.select(0)
		_show_detail(0)
	_close_button.grab_focus()


func _open_equipment() -> void:
	var panel := get_tree().get_first_node_in_group("equipment_panel")
	if panel == null:
		return
	var item_id := &""
	var selected := _list.get_selected_items()
	if not selected.is_empty() and selected[0] < _entries.size():
		item_id = _entries[selected[0]].definition.item_id
	close()
	panel.open_for(item_id)


func close() -> void:
	_root.visible = false
	ModalStack.pop(self)


func is_open() -> bool:
	return _root.visible


func row_texts() -> PackedStringArray:
	var texts := PackedStringArray()
	for index in _list.item_count:
		texts.append(_list.get_item_text(index))
	return texts


func detail_text() -> String:
	return _detail_label.text


func set_filter_index(index: int) -> void:
	_filter.selected = index
	_refresh()


func set_sort_index(index: int) -> void:
	_sort.selected = index
	_refresh()


func _refresh() -> void:
	var selected := _list.get_selected_items()
	_entries = _visible_entries()
	_list.clear()
	for entry in _entries:
		_list.add_item("%s ×%d" % [entry.definition.display_name, entry.count])
		_list.set_item_icon(_list.item_count - 1, UiIcons.texture_for(_category_id(entry.definition.item_id)))
	if _entries.is_empty():
		_detail_label.text = "背包是空的。" if ProgressState.inventory_entries().is_empty() else "没有符合筛选的物品。"
		return
	var index: int = selected[0] if not selected.is_empty() and selected[0] < _entries.size() else 0
	_list.select(index)
	_show_detail(index)


func _visible_entries() -> Array:
	var wanted := _wanted_category()
	var entries: Array = []
	for entry in ProgressState.inventory_entries():
		if wanted != "" and _category_id(entry.definition.item_id) != wanted:
			continue
		entries.append(entry)
	if _sort.selected == 1:
		entries.sort_custom(func(a, b) -> bool: return String(a.definition.display_name) < String(b.definition.display_name))
	elif _sort.selected == 2:
		entries.sort_custom(func(a, b) -> bool: return int(a.count) > int(b.count))
	return entries


func _wanted_category() -> String:
	match _filter.selected:
		1:
			return "weapon"
		2:
			return "material"
		3:
			return "blueprint"
		_:
			return ""


func _category_id(item_id: StringName) -> String:
	var item: Dictionary = Catalog.get_item(item_id)
	if item.is_empty():
		return "material"
	return String(item.get("category_id", "material"))


func _show_detail(index: int) -> void:
	if index < 0 or index >= _entries.size():
		return
	var entry: Dictionary = _entries[index]
	var item_id := String(entry.definition.item_id)
	_detail_label.text = "%s\n数量：%d\n\n%s\n%s" % [
		entry.definition.display_name,
		entry.count,
		entry.definition.description,
		LootTable.sources_text_for_item(item_id),
	]
