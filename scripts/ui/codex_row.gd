extends HBoxContainer
## 图鉴一行：形状标记、名称、角色、发现状态。


@onready var _mark_label: Label = $MarkLabel
@onready var _name_label: Label = $NameLabel
@onready var _role_label: Label = $RoleLabel
@onready var _state_label: Label = $StateLabel


func show_entry(display_name: String, role_name: String, discovered: bool) -> void:
	_mark_label.text = "◆" if discovered else "○"
	_name_label.text = display_name
	_role_label.text = role_name
	_state_label.text = "已发现" if discovered else "未发现"
	_state_label.modulate = Color(0.85, 0.78, 0.45, 1) if discovered else Color(0.62, 0.62, 0.58, 1)
