extends Button
## 开发者菜单里的一行物品。外观在场景中，页面只负责填入物品 id。

signal grant_requested(item_id: StringName)

var _item_id: StringName = &""


func setup(item_id: StringName, label: String) -> void:
	_item_id = item_id
	text = "加入 " + label


func _ready() -> void:
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	if not pressed.is_connected(_emit_grant):
		pressed.connect(_emit_grant)


func _emit_grant() -> void:
	if _item_id != &"":
		grant_requested.emit(_item_id)
