extends Control
## 状态说明页。只展示文字并返回，不执行联机、多人游戏或工坊操作。

const SceneFlow = preload("res://scripts/ui/scene_flow.gd")

@export_file("*.tscn") var back_scene_path: String = ""

@onready var _back_button: Button = $Center/Panel/Margin/VBox/BackButton

var _leaving: bool = false


func _ready() -> void:
	DisplayServer.window_set_title("TribeHunt")
	_back_button.pressed.connect(_on_back_pressed)
	_back_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed("ui_cancel"):
		return
	_mark_input_handled()
	_on_back_pressed()


func _mark_input_handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _on_back_pressed() -> void:
	if _leaving:
		return
	_leaving = true
	SceneFlow.go_to(back_scene_path)
