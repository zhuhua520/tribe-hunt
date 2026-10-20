extends CanvasLayer
## 装备页只负责这一页的节点。当前数值和玩家出手读同一份武器配置。

const Link := preload("res://scripts/items/weapon_effect_link.gd")
const Catalog := preload("res://scripts/items/item_catalog.gd")
const ModalStack := preload("res://scripts/ui/modal_stack.gd")
const THEME := preload("res://data/ui/ui_theme.tres")
const ROW_SCENE := preload("res://scenes/ui/equipment_row.tscn")

@onready var _root: Control = $Root
@onready var _current_label: Label = $Root/Center/Panel/Margin/VBox/CurrentLabel
@onready var _compare_label: Label = $Root/Center/Panel/Margin/VBox/CompareLabel
@onready var _status_label: Label = $Root/Center/Panel/Margin/VBox/StatusLabel
@onready var _rows: VBoxContainer = $Root/Center/Panel/Margin/VBox/Rows
@onready var _close_button: Button = $Root/Center/Panel/Margin/VBox/CloseButton
@onready var _open_button: Button = $OpenButton

var _compare_id: StringName = &""


func _ready() -> void:
	add_to_group("equipment_panel")
	_root.visible = false
	_root.theme = THEME
	_open_button.pressed.connect(open)
	_close_button.pressed.connect(close)
	ProgressState.equipment_changed.connect(_refresh)
	ProgressState.items_changed.connect(_refresh)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not _root.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func open() -> void:
	open_for(&"")


func open_for(item_id: StringName) -> void:
	ModalStack.close_all_except(self)
	_compare_id = item_id
	_refresh()
	_status_label.text = _selection_reason(item_id)
	_root.visible = true
	ModalStack.push(self)
	_close_button.grab_focus()


func _selection_reason(item_id: StringName) -> String:
	if item_id == &"":
		return ""
	var item: Dictionary = Catalog.get_item(item_id)
	if item.is_empty():
		return "未知物品"
	if String(item.get("category_id", "")) != "weapon":
		return "不是武器，不能装备"
	if ProgressState.item_count(item_id) <= 0:
		return "未持有"
	if not _safe_to_equip():
		return "回村后再换装"
	return ""


func close() -> void:
	_root.visible = false
	ModalStack.pop(self)


func is_open() -> bool:
	return _root.visible


func current_text() -> String:
	return _current_label.text


func status_text() -> String:
	return _status_label.text


func compare_text() -> String:
	return _compare_label.text


func equip_from_row(item_id: StringName) -> void:
	if not _safe_to_equip():
		_status_label.text = "回村后再换装"
		_refresh()
		return
	var reason := ProgressState.equip_weapon(item_id)
	_status_label.text = "已装备" if reason == "" else reason
	_refresh()


func _safe_to_equip() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return true
	var path := scene.scene_file_path
	return path == "res://scenes/village/village.tscn" or path == "res://scenes/exploration/action_training.tscn"


func _profile_line(item_id: StringName) -> String:
	var profile: Dictionary = Link.combat_profile(item_id)
	return "%s 伤害 %s · 间隔 %s秒 · 范围 %s" % [
		String(profile.get("display_name", item_id)),
		str(profile.get("damage", 0)),
		str(profile.get("interval", 0)),
		str(profile.get("range", 0)),
	]


func _refresh() -> void:
	var profile: Dictionary = Link.combat_profile(ProgressState.equipped_weapon_id())
	_current_label.text = "当前装备：%s\n%s" % [String(profile.display_name), String(profile.summary)]
	if _compare_id != &"" and String(Catalog.get_item(_compare_id).get("category_id", "")) == "weapon":
		_compare_label.text = "比较\n当前 %s\n选中 %s" % [
			_profile_line(ProgressState.equipped_weapon_id()),
			_profile_line(_compare_id),
		]
	else:
		_compare_label.text = "比较：选中另一把武器可对照伤害、间隔和范围"
	var can_swap := _safe_to_equip()
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for item_id in Catalog.item_ids():
		var item: Dictionary = Catalog.get_item(item_id)
		if String(item.get("category_id", "")) != "weapon":
			continue
		var row: HBoxContainer = ROW_SCENE.instantiate()
		_rows.add_child(row)
		var owned := ProgressState.item_count(item_id) > 0
		var current := item_id == ProgressState.equipped_weapon_id()
		var reason := ""
		if current:
			reason = "使用中"
		elif not owned:
			reason = "未持有"
		elif not can_swap:
			reason = "回村后再换装"
		var stats := "伤害 %s · 间隔 %s" % [str(item.get("attack", 0)), str(Catalog.get_effect(String(item.get("effect_id", ""))).get("interval", "—"))]
		row.show_entry(item_id, String(item.get("name", item_id)), reason, owned and not current and can_swap, stats)
		row.equip_pressed.connect(equip_from_row)
