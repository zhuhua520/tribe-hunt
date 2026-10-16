extends Control
## 在线合作入口：本机测试房间的创建 / 加入 / 离开。好友与公开房间仍为占位。

const SceneFlow = preload("res://scripts/ui/scene_flow.gd")

@onready var _status_label: Label = $Center/Panel/Margin/VBox/StatusLabel
@onready var _create_button: Button = $Center/Panel/Margin/VBox/CreateButton
@onready var _address_edit: LineEdit = $Center/Panel/Margin/VBox/JoinRow/AddressEdit
@onready var _port_spin: SpinBox = $Center/Panel/Margin/VBox/JoinRow/PortSpin
@onready var _join_button: Button = $Center/Panel/Margin/VBox/JoinRow/JoinButton
@onready var _enter_move_test_button: Button = $Center/Panel/Margin/VBox/EnterMoveTestButton
@onready var _leave_button: Button = $Center/Panel/Margin/VBox/LeaveButton
@onready var _friends_button: Button = $Center/Panel/Margin/VBox/FriendsButton
@onready var _public_button: Button = $Center/Panel/Margin/VBox/PublicButton
@onready var _back_button: Button = $Center/Panel/Margin/VBox/BackButton

var _leaving: bool = false


func _ready() -> void:
	DisplayServer.window_set_title("TribeHunt")
	_address_edit.text = SessionService.join_address
	_port_spin.min_value = 1
	_port_spin.max_value = 65535
	_port_spin.value = SessionService.listen_port
	_port_spin.rounded = true
	_create_button.pressed.connect(_on_create_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_enter_move_test_button.pressed.connect(_on_enter_move_test_pressed)
	_leave_button.pressed.connect(_on_leave_pressed)
	_friends_button.pressed.connect(_on_friends_pressed)
	_public_button.pressed.connect(_on_public_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	SessionService.status_changed.connect(_on_session_status_changed)
	_refresh_ui()
	_create_button.grab_focus()


func _exit_tree() -> void:
	if SessionService.status_changed.is_connected(_on_session_status_changed):
		SessionService.status_changed.disconnect(_on_session_status_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed("ui_cancel"):
		return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
	_on_back_pressed()


func _on_create_pressed() -> void:
	SessionService.create_room(int(_port_spin.value))


func _on_join_pressed() -> void:
	SessionService.join_room(_address_edit.text, int(_port_spin.value))


func _on_enter_move_test_pressed() -> void:
	SessionService.start_move_test()


func _on_leave_pressed() -> void:
	SessionService.leave_session()


func _on_friends_pressed() -> void:
	_go(SceneFlow.ONLINE_FRIENDS)


func _on_public_pressed() -> void:
	_go(SceneFlow.ONLINE_PUBLIC_ROOMS)


func _on_back_pressed() -> void:
	if SessionService.is_in_session():
		SessionService.leave_session()
	_go(SceneFlow.MAIN_MENU)


func _on_session_status_changed() -> void:
	_refresh_ui()


func _refresh_ui() -> void:
	_status_label.text = SessionService.status_text
	var can_start := SessionService.can_start_session()
	_create_button.disabled = not can_start
	_join_button.disabled = not can_start
	_address_edit.editable = can_start
	_port_spin.editable = can_start
	_enter_move_test_button.disabled = not SessionService.can_enter_move_test()
	_leave_button.disabled = (
		SessionService.connection_status
		== SessionService.ConnectionStatus.DISCONNECTED
	)


func _go(scene_path: String) -> void:
	if _leaving:
		return
	_leaving = true
	SceneFlow.go_to(scene_path)
