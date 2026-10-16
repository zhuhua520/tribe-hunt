extends Control
## 单人波间构筑调整面板。只切换当前样例模块，不处理掉落或奖励。

signal confirmed

var _title_label: Label
var _module_checkboxes: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_view()
	visible = false


func open_for_wave(wave_index: int, total_waves: int) -> void:
	_title_label.text = "第 %d/%d 波结束：调整构筑" % [wave_index, total_waves]
	for module in BuildRunService.get_module_definitions():
		var checkbox := _module_checkboxes[module.module_id] as CheckBox
		checkbox.button_pressed = BuildRunService.is_equipped(module.module_id)
	visible = true
	var first_checkbox: CheckBox
	if not _module_checkboxes.is_empty():
		first_checkbox = _module_checkboxes.values()[0] as CheckBox
	if first_checkbox != null:
		first_checkbox.grab_focus()


func _build_view() -> void:
	var dimmer := ColorRect.new()
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.02, 0.03, 0.02, 0.78)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dimmer)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620.0, 0.0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)

	_title_label = _make_label("调整构筑", 26)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_title_label)

	var instructions := _make_label(
		"可增减本次运行的样例模块。选项只验证模块效果和组合，不代表最终槽位、掉落或重复装备规则。",
		16
	)
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(instructions)

	for module in BuildRunService.get_module_definitions():
		var checkbox := CheckBox.new()
		checkbox.text = "%s：%s（临时原型值）" % [module.display_name, module.prototype_effect_label()]
		checkbox.custom_minimum_size = Vector2(0.0, 42.0)
		_module_checkboxes[module.module_id] = checkbox
		content.add_child(checkbox)

	var confirm_button := Button.new()
	confirm_button.text = "确认构筑并继续"
	confirm_button.custom_minimum_size = Vector2(0.0, 44.0)
	confirm_button.pressed.connect(_on_confirm_pressed)
	content.add_child(confirm_button)


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _on_confirm_pressed() -> void:
	var selected_ids: Array[String] = []
	for module in BuildRunService.get_module_definitions():
		var checkbox := _module_checkboxes[module.module_id] as CheckBox
		if checkbox.button_pressed:
			selected_ids.append(module.module_id)
	BuildRunService.set_equipped_module_ids(selected_ids)
	visible = false
	confirmed.emit()
