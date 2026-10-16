extends Control
## 波次结束时的左右卡片。点一张就确认：继续留在副本，或召唤回城传送门。

signal continue_selected
signal extract_selected

var _continue_card: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_view()
	visible = false


func open_for_wave(_wave_index: int, _total_waves: int) -> void:
	visible = true
	if _continue_card != null:
		_continue_card.grab_focus()


func _build_view() -> void:
	var dimmer := ColorRect.new()
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.02, 0.03, 0.02, 0.72)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dimmer)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 48)
	center.add_child(row)

	_continue_card = _make_card("继续", "留在副本\n下一波继续")
	_continue_card.pressed.connect(_on_continue_pressed)
	row.add_child(_continue_card)

	var return_card := _make_card("回城", "出现传送门\n走进后返回村落")
	return_card.pressed.connect(_on_extract_pressed)
	row.add_child(return_card)


func _make_card(title: String, detail: String) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(300.0, 220.0)
	card.text = "%s\n\n%s" % [title, detail]
	card.add_theme_font_size_override("font_size", 28)
	card.alignment = HORIZONTAL_ALIGNMENT_CENTER
	return card


func _on_continue_pressed() -> void:
	visible = false
	continue_selected.emit()


func _on_extract_pressed() -> void:
	visible = false
	extract_selected.emit()
