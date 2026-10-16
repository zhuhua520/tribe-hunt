extends Control
## 模式选择：单人进入出征准备；本地合作只打开状态说明。

const SceneFlow = preload("res://scripts/ui/scene_flow.gd")

@onready var _solo_button: Button = $Center/Panel/Margin/VBox/SoloButton
@onready var _local_button: Button = $Center/Panel/Margin/VBox/LocalButton
@onready var _back_button: Button = $Center/Panel/Margin/VBox/BackButton

var _leaving: bool = false


func _ready() -> void:
	DisplayServer.window_set_title("TribeHunt")
	_solo_button.pressed.connect(_on_solo_pressed)
	_local_button.pressed.connect(_on_local_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_solo_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed("ui_cancel"):
		return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
	_on_back_pressed()


func _on_solo_pressed() -> void:
	_go(SceneFlow.VILLAGE)


func _on_local_pressed() -> void:
	_go(SceneFlow.LOCAL_COOP_STATUS)


func _on_back_pressed() -> void:
	_go(SceneFlow.MAIN_MENU)


func _go(scene_path: String) -> void:
	if _leaving:
		return
	_leaving = true
	SceneFlow.go_to(scene_path)
