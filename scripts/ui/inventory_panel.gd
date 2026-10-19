extends CanvasLayer
## 背包界面：列出 ProgressState 中的持有物，选中后显示说明。只读，不改数量。
## 不设格数或容量上限（未定；不恢复旧背包格数规则）。按 inventory 动作开关，ui_cancel 关闭；暂停时不响应。

@onready var _root: Control = $Root
@onready var _list: ItemList = $Root/Center/Panel/Margin/VBox/ItemList
@onready var _detail_label: Label = $Root/Center/Panel/Margin/VBox/DetailLabel
@onready var _close_button: Button = $Root/Center/Panel/Margin/VBox/CloseButton

var _entries: Array = []


func _ready() -> void:
	_root.visible = false
	ProgressState.items_changed.connect(_refresh)
	_list.item_selected.connect(_show_detail)
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
	_refresh()
	_root.visible = true
	if not _entries.is_empty():
		_list.select(0)
		_show_detail(0)
	_close_button.grab_focus()


func close() -> void:
	_root.visible = false


func is_open() -> bool:
	return _root.visible


func row_texts() -> PackedStringArray:
	var texts := PackedStringArray()
	for index in _list.item_count:
		texts.append(_list.get_item_text(index))
	return texts


func detail_text() -> String:
	return _detail_label.text


func _refresh() -> void:
	var selected := _list.get_selected_items()
	_entries = ProgressState.inventory_entries()
	_list.clear()
	for entry in _entries:
		_list.add_item("%s ×%d" % [entry.definition.display_name, entry.count])
	if _entries.is_empty():
		_detail_label.text = "背包是空的。"
		return
	var index: int = selected[0] if not selected.is_empty() and selected[0] < _entries.size() else 0
	_list.select(index)
	_show_detail(index)


func _show_detail(index: int) -> void:
	if index < 0 or index >= _entries.size():
		return
	var entry: Dictionary = _entries[index]
	_detail_label.text = "%s\n数量：%d\n\n%s" % [entry.definition.display_name, entry.count, entry.definition.description]
