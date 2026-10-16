extends Control
## 主菜单中的设置页。返回主菜单，不写入玩家进度。

const SceneFlow = preload("res://scripts/ui/scene_flow.gd")

@onready var _panel: VBoxContainer = $Center/Panel/Margin/SettingsPanel

var _leaving: bool = false


func _ready() -> void:
	DisplayServer.window_set_title("TribeHunt")
	_panel.connect("back_pressed", _on_back_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed("ui_cancel"):
		return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
	_on_back_pressed()


func _on_back_pressed() -> void:
	if _leaving:
		return
	_leaving = true
	SceneFlow.go_to(SceneFlow.MAIN_MENU)
