extends Control
## 主菜单：开始远征（动态加载进入部落村落）、在线合作、创意工坊、设置、退出。

const SceneFlow = preload("res://scripts/ui/scene_flow.gd")
const SettingsStore = preload("res://scripts/save/settings_store.gd")

@onready var _start_button: Button = $Center/Panel/Margin/VBox/StartButton
@onready var _online_button: Button = $Center/Panel/Margin/VBox/OnlineButton
@onready var _workshop_button: Button = $Center/Panel/Margin/VBox/WorkshopButton
@onready var _settings_button: Button = $Center/Panel/Margin/VBox/SettingsButton
@onready var _quit_button: Button = $Center/Panel/Margin/VBox/QuitButton

var _loading_target: String = ""
var _loading_overlay: ColorRect = null
var _loading_label: Label = null


func _ready() -> void:
	DisplayServer.window_set_title("TribeHunt")
	SettingsStore.load_and_apply()
	_start_button.pressed.connect(_on_start_pressed)
	_online_button.pressed.connect(_on_online_pressed)
	_workshop_button.pressed.connect(_on_workshop_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_start_button.grab_focus()
	set_process(false)


func _process(_delta: float) -> void:
	if _loading_target.is_empty():
		set_process(false)
		return
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(_loading_target, progress)
	if _loading_label != null and not progress.is_empty():
		var pct := int(round(float(progress[0]) * 100.0))
		_loading_label.text = "正在加载部落村落资源... %d%%" % pct
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var packed := ResourceLoader.load_threaded_get(_loading_target) as PackedScene
		_loading_target = ""
		set_process(false)
		if packed != null:
			SceneFlow.go_to_packed(packed)
		else:
			SceneFlow.go_to(SceneFlow.VILLAGE)
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		_loading_target = ""
		set_process(false)
		SceneFlow.go_to(SceneFlow.VILLAGE)


func _on_start_pressed() -> void:
	if not _loading_target.is_empty():
		return
	_show_loading_overlay()
	_loading_target = SceneFlow.VILLAGE
	var err := ResourceLoader.load_threaded_request(_loading_target)
	if err != OK:
		_loading_target = ""
		SceneFlow.go_to(SceneFlow.VILLAGE)
		return
	set_process(true)


func _show_loading_overlay() -> void:
	if _loading_overlay != null:
		_loading_overlay.visible = true
		return
	_loading_overlay = ColorRect.new()
	_loading_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_overlay.color = Color(0.06, 0.05, 0.04, 0.85)
	add_child(_loading_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_overlay.add_child(center)

	_loading_label = Label.new()
	_loading_label.text = "正在加载部落村落资源... 0%"
	_loading_label.add_theme_font_size_override("font_size", 24)
	_loading_label.add_theme_color_override("font_color", Color(0.93, 0.86, 0.72, 1.0))
	center.add_child(_loading_label)


func _on_online_pressed() -> void:
	if not _loading_target.is_empty():
		return
	SceneFlow.go_to(SceneFlow.ONLINE_LOBBY)


func _on_workshop_pressed() -> void:
	if not _loading_target.is_empty():
		return
	SceneFlow.go_to(SceneFlow.WORKSHOP)


func _on_settings_pressed() -> void:
	if not _loading_target.is_empty():
		return
	SceneFlow.go_to(SceneFlow.SETTINGS)


func _on_quit_pressed() -> void:
	SceneFlow.quit()
