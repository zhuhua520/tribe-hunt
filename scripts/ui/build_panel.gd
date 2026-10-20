extends CanvasLayer
## 构筑页只连接这一页的槽位和实例行。预览与自动攻击用同一份派生。

const Derived := preload("res://scripts/build/build_derived_stats.gd")
const ModalStack := preload("res://scripts/ui/modal_stack.gd")
const THEME := preload("res://data/ui/ui_theme.tres")
const ROW_SCENE := preload("res://scenes/ui/build_slot_row.tscn")

@onready var _root: Control = $Root
@onready var _status_label: Label = $Root/Center/Panel/Margin/VBox/StatusLabel
@onready var _preview_label: Label = $Root/Center/Panel/Margin/VBox/PreviewLabel
@onready var _slots: VBoxContainer = $Root/Center/Panel/Margin/VBox/Slots
@onready var _compare_label: Label = $Root/Center/Panel/Margin/VBox/CompareLabel
@onready var _codex_label: Label = $Root/Center/Panel/Margin/VBox/CodexLabel
@onready var _confirm_box: HBoxContainer = $Root/Center/Panel/Margin/VBox/ConfirmBox
@onready var _confirm_label: Label = $Root/Center/Panel/Margin/VBox/ConfirmBox/ConfirmLabel
@onready var _confirm_button: Button = $Root/Center/Panel/Margin/VBox/ConfirmBox/ConfirmButton
@onready var _cancel_button: Button = $Root/Center/Panel/Margin/VBox/ConfirmBox/CancelButton
@onready var _instances: VBoxContainer = $Root/Center/Panel/Margin/VBox/Instances
@onready var _preset_a: Button = $Root/Center/Panel/Margin/VBox/PresetRow/PresetA
@onready var _preset_b: Button = $Root/Center/Panel/Margin/VBox/PresetRow/PresetB
@onready var _close_button: Button = $Root/Center/Panel/Margin/VBox/CloseButton
@onready var _open_button: Button = $OpenButton

var _pending_dismantle: String = ""


func _ready() -> void:
	add_to_group("build_panel")
	_root.visible = false
	_root.theme = THEME
	_open_button.pressed.connect(open)
	_close_button.pressed.connect(close)
	_preset_a.pressed.connect(func() -> void: _activate("preset_a"))
	_preset_b.pressed.connect(func() -> void: _activate("preset_b"))
	_confirm_button.pressed.connect(func() -> void: confirm_dismantle())
	_cancel_button.pressed.connect(cancel_dismantle)
	if not ProgressState.build_loadout.changed.is_connected(_refresh):
		ProgressState.build_loadout.changed.connect(_refresh)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not _root.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _confirm_box.visible:
			cancel_dismantle()
		else:
			close()


func open() -> void:
	ModalStack.close_all_except(self)
	_refresh()
	_root.visible = true
	ModalStack.push(self)
	_close_button.grab_focus()


func close() -> void:
	_clear_confirm()
	_root.visible = false
	ModalStack.pop(self)


func is_open() -> bool:
	return _root.visible


func preview_text() -> String:
	return _preview_label.text


func compare_text() -> String:
	return _compare_label.text


func status_text() -> String:
	return _status_label.text


func codex_text() -> String:
	return _codex_label.text


func confirm_visible() -> bool:
	return _confirm_box.visible


func request_dismantle(instance_id: String) -> String:
	if not _in_village():
		_status_label.text = "战斗中不能拆解"
		return "战斗中不能拆解"
	var reason := ProgressState.dismantle_blocked_reason(instance_id, false)
	if reason == "还装在预设里，需要确认卸下再拆":
		_pending_dismantle = instance_id
		_confirm_label.text = "这件还装在预设里。确认卸下并拆解？不会改其他组件。"
		_confirm_box.visible = true
		_status_label.text = reason
		return reason
	if reason != "":
		_status_label.text = reason
		return reason
	reason = ProgressState.dismantle_component(instance_id, false)
	_refresh()
	if reason != "":
		_status_label.text = reason
	return reason


func confirm_dismantle() -> String:
	if not _in_village():
		_status_label.text = "战斗中不能拆解"
		return "战斗中不能拆解"
	var instance_id := _pending_dismantle
	if instance_id == "":
		return "没有待确认的拆解"
	var reason := ProgressState.dismantle_component(instance_id, true)
	_clear_confirm()
	_refresh()
	if reason != "":
		_status_label.text = reason
	return reason


func cancel_dismantle() -> void:
	_clear_confirm()
	_refresh()


func request_enhance(instance_id: String) -> String:
	if not _in_village():
		_status_label.text = "战斗中不能强化"
		return "战斗中不能强化"
	var reason := ProgressState.enhance_component(instance_id)
	_refresh()
	if reason != "":
		_status_label.text = reason
	return reason


func equip_instance(instance_id: String) -> String:
	return ProgressState.build_loadout.try_equip(instance_id)


func clear_slot(slot: String) -> void:
	ProgressState.build_loadout.set_slot(slot, "")


func _activate(build_id: String) -> void:
	if not _in_village():
		_refresh()
		_status_label.text = "战斗中不能切换预设"
		return
	var reason := ProgressState.build_loadout.set_active_preset(build_id)
	_refresh()
	if reason != "":
		_status_label.text = reason


func _in_village() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.scene_file_path == "res://scenes/village/village.tscn"


func _refresh() -> void:
	var profile: Dictionary = Derived.from_weapon(ProgressState.equipped_weapon_id())
	_status_label.text = String(profile.get("status", ""))
	_preview_label.text = String(profile.get("detail", ""))
	_compare_label.text = ProgressState.build_loadout.compare_text()
	_codex_label.text = ProgressState.build_loadout.discovered_text()
	if _pending_dismantle != "" and not ProgressState.build_loadout.instances.has(_pending_dismantle):
		_clear_confirm()
	_confirm_box.visible = _pending_dismantle != ""
	_fill_slots()
	_fill_instances()


func _fill_slots() -> void:
	_clear(_slots)
	var loadout = ProgressState.build_loadout
	var preset: Dictionary = loadout.active_preset()
	_add_slot("core", "核心", String(preset.get("core", "")))
	_add_slot("support_0", "辅助", String(preset.get("support_0", "")))
	_add_slot("support_1", "辅助", String(preset.get("support_1", "")))


func _add_slot(slot: String, title: String, instance_id: String) -> void:
	var row: HBoxContainer = ROW_SCENE.instantiate()
	_slots.add_child(row)
	var detail := "空"
	if instance_id != "":
		var inst: Dictionary = ProgressState.build_loadout.instance(instance_id)
		var comp: Dictionary = ProgressState.build_loadout.definition(String(inst.get("definition_id", "")))
		detail = String(comp.get("name", instance_id))
	row.show_slot(slot, title, detail, "" if instance_id == "" else "卸下")
	row.action_pressed.connect(clear_slot)


func _fill_instances() -> void:
	_clear(_instances)
	var loadout = ProgressState.build_loadout
	for instance_id in loadout.instances:
		var inst: Dictionary = loadout.instance(String(instance_id))
		var comp: Dictionary = loadout.definition(String(inst.get("definition_id", "")))
		var row: HBoxContainer = ROW_SCENE.instantiate()
		_instances.add_child(row)
		var detail := "星级 %d · %s" % [int(comp.get("star", 1)), String(comp.get("role", ""))]
		var level := int(inst.get("level", 1))
		if level > 1:
			detail = "%s · 强化 %d" % [detail, level]
		var mods: Dictionary = preload("res://scripts/build/affix_pool.gd").mods_for(inst)
		var affix_lines: PackedStringArray = mods.get("lines", PackedStringArray())
		if not affix_lines.is_empty():
			detail = "%s · %s" % [detail, " / ".join(affix_lines)]
		var lock_text := "已锁定" if inst.get("locked", false) == true else "锁定"
		row.show_slot(String(instance_id), String(comp.get("name", instance_id)), detail, "装入", lock_text, "拆解", "强化")
		row.action_pressed.connect(func(id: String) -> void: equip_instance(id))
		row.lock_pressed.connect(_toggle_lock)
		row.dismantle_pressed.connect(request_dismantle)
		row.enhance_pressed.connect(request_enhance)


func _toggle_lock(instance_id: String) -> void:
	var inst: Dictionary = ProgressState.build_loadout.instance(instance_id)
	var locked: bool = inst.get("locked", false) == true
	ProgressState.build_loadout.set_locked(instance_id, not locked)


func _clear_confirm() -> void:
	_pending_dismantle = ""
	_confirm_box.visible = false


func _clear(box: VBoxContainer) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
