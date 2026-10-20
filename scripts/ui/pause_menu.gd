extends CanvasLayer
## 单人战斗暂停。可以继续、打开设置或结束冒险并返回部落村落。

const SceneFlow = preload("res://scripts/ui/scene_flow.gd")
const ModalStack := preload("res://scripts/ui/modal_stack.gd")
const THEME := preload("res://data/ui/ui_theme.tres")

@onready var _pause_root: Control = $PauseRoot
@onready var _settings_root: Control = $SettingsRoot
@onready var _resume_button: Button = $PauseRoot/Center/Panel/Margin/VBox/ResumeButton
@onready var _settings_button: Button = $PauseRoot/Center/Panel/Margin/VBox/SettingsButton
@onready var _menu_button: Button = $PauseRoot/Center/Panel/Margin/VBox/MenuButton
@onready var _settings_panel: VBoxContainer = $SettingsRoot/Center/Panel/Margin/SettingsPanel

var _run_ended: bool = false
var _leaving: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_root.visible = false
	_settings_root.visible = false
	_pause_root.theme = THEME
	_settings_root.theme = THEME
	_resume_button.pressed.connect(_resume)
	_settings_button.pressed.connect(_open_settings)
	_menu_button.pressed.connect(_on_menu_pressed)
	_settings_panel.connect("back_pressed", _show_pause_choices)
	var wave_manager := get_parent().get_node_or_null("WaveManager")
	if wave_manager != null:
		if wave_manager.has_signal("run_won"):
			wave_manager.run_won.connect(_on_run_ended)
		if wave_manager.has_signal("run_lost"):
			wave_manager.run_lost.connect(_on_run_ended)
		if wave_manager.has_signal("run_extracted"):
			wave_manager.run_extracted.connect(_on_run_ended)


func _unhandled_input(event: InputEvent) -> void:
	if _run_ended or _leaving or event.is_echo() or not event.is_action_pressed("pause"):
		return
	var wave_manager := get_parent().get_node_or_null("WaveManager")
	if wave_manager != null and wave_manager.has_method("is_build_adjustment_active"):
		if wave_manager.is_build_adjustment_active():
			return
	if wave_manager != null and wave_manager.has_method("is_extraction_choice_active"):
		if wave_manager.is_extraction_choice_active():
			return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
	if _settings_root.visible:
		_show_pause_choices()
	elif _pause_root.visible:
		_resume()
	elif ModalStack.close_top():
		return
	else:
		_open_pause()


func _open_pause() -> void:
	_settings_root.visible = false
	_pause_root.visible = true
	get_tree().paused = true
	_resume_button.grab_focus()


func _show_pause_choices() -> void:
	_settings_root.visible = false
	_pause_root.visible = true
	get_tree().paused = true
	_resume_button.grab_focus()


func _open_settings() -> void:
	_pause_root.visible = false
	_settings_root.visible = true
	get_tree().paused = true
	_settings_panel.call("refresh")
	_settings_panel.call("focus_back")


func _resume() -> void:
	_pause_root.visible = false
	_settings_root.visible = false
	get_tree().paused = false


func _on_menu_pressed() -> void:
	if _leaving:
		return
	_leaving = true
	_resume()
	SceneFlow.go_to(SceneFlow.VILLAGE)


func _on_run_ended() -> void:
	_run_ended = true
	_resume()
