extends Control
## 出征选择页面：左侧为分类占位，右侧为具体目的地（含当前可出征战斗点與原型构筑/撤离配置），返回回到村落。

const SceneFlow = preload("res://scripts/ui/scene_flow.gd")

@onready var _confirm_button: Button = $Center/Panel/Margin/MainVBox/BottomBar/ConfirmButton
@onready var _back_button: Button = $Center/Panel/Margin/MainVBox/BottomBar/BackButton
@onready var _build_options: VBoxContainer = $Center/Panel/Margin/MainVBox/Columns/RightDestBox/PrepConfigBox/BuildOptions
@onready var _build_summary: Label = $Center/Panel/Margin/MainVBox/Columns/RightDestBox/PrepConfigBox/BuildSummaryLabel
@onready var _rhythm_option: OptionButton = $Center/Panel/Margin/MainVBox/Columns/RightDestBox/PrepConfigBox/RhythmOption
@onready var _category_forest_btn: Button = $Center/Panel/Margin/MainVBox/Columns/LeftCategoryBox/CatForestButton
@onready var _category_swamp_btn: Button = $Center/Panel/Margin/MainVBox/Columns/LeftCategoryBox/CatSwampButton
@onready var _category_ruins_btn: Button = $Center/Panel/Margin/MainVBox/Columns/LeftCategoryBox/CatRuinsButton
@onready var _dest_boar_btn: Button = $Center/Panel/Margin/MainVBox/Columns/RightDestBox/DestList/DestBoarWoodsButton
@onready var _dest_placeholder_btn: Button = $Center/Panel/Margin/MainVBox/Columns/RightDestBox/DestList/DestPlaceholderButton
@onready var _dest_desc_label: Label = $Center/Panel/Margin/MainVBox/Columns/RightDestBox/DestDescLabel

var _leaving: bool = false
var _module_checkboxes: Dictionary = {}
var _selected_dest_valid: bool = true


func _ready() -> void:
	DisplayServer.window_set_title("TribeHunt")
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_category_forest_btn.pressed.connect(_on_category_selected.bind("forest"))
	_category_swamp_btn.pressed.connect(_on_category_selected.bind("swamp"))
	_category_ruins_btn.pressed.connect(_on_category_selected.bind("ruins"))
	_dest_boar_btn.pressed.connect(_on_dest_selected.bind(true))
	_dest_placeholder_btn.pressed.connect(_on_dest_selected.bind(false))
	_build_module_options()
	_build_rhythm_options()
	_on_category_selected("forest")
	_confirm_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed("ui_cancel"):
		return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
	_on_back_pressed()


func _on_category_selected(cat_id: String) -> void:
	if cat_id == "forest":
		_dest_boar_btn.visible = true
		_dest_placeholder_btn.text = "迷雾林深处（占位，暂未开放）"
		_on_dest_selected(true)
	elif cat_id == "swamp":
		_dest_boar_btn.visible = false
		_dest_placeholder_btn.text = "腐泥沼泽出征点（分类占位）"
		_on_dest_selected(false)
	else:
		_dest_boar_btn.visible = false
		_dest_placeholder_btn.text = "远古石环出征点（分类占位）"
		_on_dest_selected(false)


func _on_dest_selected(is_boar_woods: bool) -> void:
	_selected_dest_valid = is_boar_woods
	_confirm_button.disabled = not is_boar_woods
	if is_boar_woods:
		_dest_desc_label.text = "当前目的地：【野猪林外围（出征点）】\n三波普通野兽与末段野猪王遭遇（已接入战斗场景）。"
	else:
		_dest_desc_label.text = "当前目的地：占位区域（尚未开放，请选择「近郊猎场」→「野猪林外围」出征）。"


func _on_confirm_pressed() -> void:
	if not _selected_dest_valid:
		return
	BuildRunService.set_prepared_module_ids(_selected_module_ids())
	BuildRunService.set_extraction_wave_interval(_rhythm_option.get_selected_id())
	_go(SceneFlow.ARENA)


func _on_back_pressed() -> void:
	_go(SceneFlow.VILLAGE)


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
		checkbox.custom_minimum_size = Vector2(0.0, 34.0)
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
