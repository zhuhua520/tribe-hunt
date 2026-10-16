extends Control
## 主菜单：开始远征、在线合作、创意工坊、设置、退出。

const SceneFlow = preload("res://scripts/ui/scene_flow.gd")
const SettingsStore = preload("res://scripts/save/settings_store.gd")

@onready var _start_button: Button = $Center/Panel/Margin/VBox/StartButton
@onready var _online_button: Button = $Center/Panel/Margin/VBox/OnlineButton
@onready var _workshop_button: Button = $Center/Panel/Margin/VBox/WorkshopButton
@onready var _settings_button: Button = $Center/Panel/Margin/VBox/SettingsButton
@onready var _quit_button: Button = $Center/Panel/Margin/VBox/QuitButton


func _ready() -> void:
	DisplayServer.window_set_title("TribeHunt")
	SettingsStore.load_and_apply()
	_start_button.pressed.connect(_on_start_pressed)
	_online_button.pressed.connect(_on_online_pressed)
	_workshop_button.pressed.connect(_on_workshop_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_start_button.grab_focus()


func _on_start_pressed() -> void:
	SceneFlow.go_to(SceneFlow.MODE_SELECT)


func _on_online_pressed() -> void:
	SceneFlow.go_to(SceneFlow.ONLINE_LOBBY)


func _on_workshop_pressed() -> void:
	SceneFlow.go_to(SceneFlow.WORKSHOP)


func _on_settings_pressed() -> void:
	SceneFlow.go_to(SceneFlow.SETTINGS)


func _on_quit_pressed() -> void:
	SceneFlow.quit()
