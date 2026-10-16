extends Control
## 单人撤离节点。继续进入现有下一波流程，撤离只结束本次运行。

signal continue_selected
signal extract_selected

var _title_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_view()
	visible = false


func open_for_wave(wave_index: int, total_waves: int) -> void:
	_title_label.text = "第 %d/%d 波结束：撤离节点" % [wave_index, total_waves]
	visible = true


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

	_title_label = _make_label("撤离节点", 26)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_title_label)

	var instructions := _make_label(
		"这是对照用的临时选择，不代表最终撤离节奏。继续会进入下一波，并可调整构筑。撤离只结束本次运行，不发放奖励，也不写入成长存档。",
		16
	)
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(instructions)

	var continue_button := Button.new()
	continue_button.text = "继续"
	continue_button.custom_minimum_size = Vector2(0.0, 44.0)
	continue_button.pressed.connect(_on_continue_pressed)
	content.add_child(continue_button)

	var extract_button := Button.new()
	extract_button.text = "撤离"
	extract_button.custom_minimum_size = Vector2(0.0, 44.0)
	extract_button.pressed.connect(_on_extract_pressed)
	content.add_child(extract_button)


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _on_continue_pressed() -> void:
	visible = false
	continue_selected.emit()


func _on_extract_pressed() -> void:
	visible = false
	extract_selected.emit()
