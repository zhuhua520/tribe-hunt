extends Control
## 单人出征准备。选择少量原型模块后进入三波战斗。

const SceneFlow = preload("res://scripts/ui/scene_flow.gd")

@onready var _confirm_button: Button = $Center/Panel/Margin/VBox/ConfirmButton
@onready var _back_button: Button = $Center/Panel/Margin/VBox/BackButton
@onready var _build_options: VBoxContainer = $Center/Panel/Margin/VBox/BuildOptions
@onready var _build_summary: Label = $Center/Panel/Margin/VBox/BuildSummaryLabel
@onready var _rhythm_option: OptionButton = $Center/Panel/Margin/VBox/RhythmOption

var _leaving: bool = false
var _module_checkboxes: Dictionary = {}


func _ready() -> void:
	DisplayServer.window_set_title("TribeHunt")
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_build_module_options()
	_build_rhythm_options()
	_confirm_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed("ui_cancel"):
		return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
	_on_back_pressed()


func _on_confirm_pressed() -> void:
	BuildRunService.set_prepared_module_ids(_selected_module_ids())
	BuildRunService.set_extraction_wave_interval(_rhythm_option.get_selected_id())
	_go(SceneFlow.ARENA)


func _on_back_pressed() -> void:
	_go(SceneFlow.MODE_SELECT)


func _go(scene_path: String) -> void:
	if _leaving:
		return
	_leaving = true
	SceneFlow.go_to(scene_path)


func _build_rhythm_options() -> void:
	_rhythm_option.clear()
	_rhythm_option.add_item("每波开放", BuildRunService.EXTRACTION_EVERY_WAVE)
	_rhythm_option.add_item("每两波开放", BuildRunService.EXTRACTION_EVERY_TWO_WAVES)
	var selected_index := 0
	if BuildRunService.extraction_wave_interval == BuildRunService.EXTRACTION_EVERY_TWO_WAVES:
		selected_index = 1
	_rhythm_option.select(selected_index)


func _build_module_options() -> void:
	for module in BuildRunService.get_module_definitions():
		var checkbox := CheckBox.new()
		checkbox.text = "%s：%s（临时原型值）" % [module.display_name, module.prototype_effect_label()]
		checkbox.button_pressed = BuildRunService.is_prepared(module.module_id)
		checkbox.custom_minimum_size = Vector2(0.0, 40.0)
		checkbox.toggled.connect(_on_module_toggled.bind(module.module_id))
		_module_checkboxes[module.module_id] = checkbox
		_build_options.add_child(checkbox)
	_update_build_summary()


func _on_module_toggled(_is_selected: bool, _module_id: String) -> void:
	_update_build_summary()


func _selected_module_ids() -> Array[String]:
	var selected_ids: Array[String] = []
	for module in BuildRunService.get_module_definitions():
		var checkbox := _module_checkboxes[module.module_id] as CheckBox
		if checkbox.button_pressed:
			selected_ids.append(module.module_id)
	return selected_ids


func _update_build_summary() -> void:
	var selected := PackedStringArray()
	for module_id in _selected_module_ids():
		var module := BuildRunService.get_module(module_id)
		if module != null:
			selected.append(module.display_name)
	_build_summary.text = "本次携带：" + ("、".join(selected) if not selected.is_empty() else "暂不携带模块")
