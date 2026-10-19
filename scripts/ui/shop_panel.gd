extends CanvasLayer
## 城镇店铺页面。控件在场景里，这里只按物品表填列表。不买卖，不写存档。

const Catalog := preload("res://scripts/items/item_catalog.gd")

@onready var _root: Control = $Root
@onready var _title: Label = $Root/Center/Panel/Margin/VBox/TitleLabel
@onready var _list: ItemList = $Root/Center/Panel/Margin/VBox/ItemList
@onready var _close: Button = $Root/Center/Panel/Margin/VBox/CloseButton


func _ready() -> void:
	_root.visible = false
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


func open_shop(title: String, category_id: String) -> void:
	_title.text = title
	_list.clear()
	for item_id in Catalog.item_ids():
		var item: Dictionary = Catalog.get_item(item_id)
		if String(item.get("category_id", "")) != category_id:
			continue
		var line := String(item.get("name", item_id))
		line += "　" + String(item.get("group_name", ""))
		if item.has("attack"):
			line += "　攻击力 %s" % str(item.get("attack", 0))
		var effect: Dictionary = Catalog.get_effect(String(item.get("effect_id", "")))
		if not effect.is_empty():
			line += "　" + String(effect.get("name", ""))
		_list.add_item(line)
	_root.visible = true
	_close.grab_focus()


func close() -> void:
	_root.visible = false
