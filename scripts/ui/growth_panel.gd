extends CanvasLayer
## 成长页只连接这一页的等级、经验和一条技术。不开放自由加点。

const GrowthCatalog := preload("res://scripts/progression/growth_catalog.gd")
const ModalStack := preload("res://scripts/ui/modal_stack.gd")
const THEME := preload("res://data/ui/ui_theme.tres")

@onready var _root: Control = $Root
@onready var _status_label: Label = $Root/Center/Panel/Margin/VBox/StatusLabel
@onready var _detail_label: Label = $Root/Center/Panel/Margin/VBox/DetailLabel
@onready var _research_button: Button = $Root/Center/Panel/Margin/VBox/ResearchButton
@onready var _close_button: Button = $Root/Center/Panel/Margin/VBox/CloseButton
@onready var _open_button: Button = $OpenButton

const TECH_ID := "tech_bow_training"


func _ready() -> void:
	add_to_group("growth_panel")
	_root.visible = false
	_root.theme = THEME
	_open_button.pressed.connect(open)
	_close_button.pressed.connect(close)
	_research_button.pressed.connect(func() -> void: try_research())
	if not ProgressState.growth_changed.is_connected(_refresh):
		ProgressState.growth_changed.connect(_refresh)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not _root.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func open() -> void:
	ModalStack.close_all_except(self)
	_refresh()
	_root.visible = true
	ModalStack.push(self)
	_close_button.grab_focus()


func close() -> void:
	_root.visible = false
	ModalStack.pop(self)


func is_open() -> bool:
	return _root.visible


func status_text() -> String:
	return _status_label.text


func detail_text() -> String:
	return _detail_label.text


func try_research() -> String:
	if not _in_village():
		_status_label.text = "战斗中不能研究"
		return "战斗中不能研究"
	var reason := ProgressState.research_tech(TECH_ID)
	_refresh()
	if reason != "":
		_status_label.text = reason
	return reason


func _in_village() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.scene_file_path == "res://scenes/village/village.tscn"


func _refresh() -> void:
	_status_label.text = ProgressState.growth_text()
	var spec: Dictionary = GrowthCatalog.tech(TECH_ID)
	var lines := PackedStringArray()
	lines.append(String(spec.get("name", TECH_ID)))
	lines.append(String(spec.get("description", "")))
	lines.append("需要等级 %d（测试配置，不是最终数值）" % int(spec.get("required_level", 1)))
	var cost_id: StringName = StringName(spec.get("cost_item_id", ""))
	var need := int(spec.get("cost_count", 0))
	lines.append("材料：测试纤维 %d/%d" % [ProgressState.item_count(cost_id), need])
	if ProgressState.has_tech(TECH_ID):
		lines.append("已解锁：可在合成铺制作试验弓")
		_research_button.disabled = true
		_research_button.text = "已研究"
	else:
		var reason := ProgressState.research_blocked_reason(TECH_ID)
		if reason != "":
			lines.append(reason)
		_research_button.disabled = reason != ""
		_research_button.text = "研究"
	_detail_label.text = "\n".join(lines)
