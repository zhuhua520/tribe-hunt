extends CanvasLayer
## 组件图鉴。列出全部定义的发现/未发现，不等于背包库存。

const ModalStack := preload("res://scripts/ui/modal_stack.gd")
const THEME := preload("res://data/ui/ui_theme.tres")
const ROW_SCENE := preload("res://scenes/ui/codex_row.tscn")

@onready var _root: Control = $Root
@onready var _status_label: Label = $Root/Center/Panel/Margin/VBox/StatusLabel
@onready var _rows: VBoxContainer = $Root/Center/Panel/Margin/VBox/Scroll/Rows
@onready var _close_button: Button = $Root/Center/Panel/Margin/VBox/CloseButton
@onready var _open_button: Button = $OpenButton


func _ready() -> void:
	add_to_group("codex_panel")
	_root.visible = false
	_root.theme = THEME
	_open_button.pressed.connect(open)
	_close_button.pressed.connect(close)
	if not ProgressState.build_loadout.changed.is_connected(_refresh):
		ProgressState.build_loadout.changed.connect(_refresh)
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


func row_texts() -> PackedStringArray:
	var texts := PackedStringArray()
	for row in _rows.get_children():
		texts.append("%s %s %s" % [
			row.get_node("NameLabel").text,
			row.get_node("RoleLabel").text,
			row.get_node("StateLabel").text,
		])
	return texts


func _refresh() -> void:
	var loadout = ProgressState.build_loadout
	var definition_ids: PackedStringArray = loadout.definition_ids()
	var discovered: int = 0
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for definition_id in definition_ids:
		var comp: Dictionary = loadout.definition(String(definition_id))
		var found: bool = loadout.discovered.has(String(definition_id))
		if found:
			discovered += 1
		var row: HBoxContainer = ROW_SCENE.instantiate()
		_rows.add_child(row)
		var role := "核心" if String(comp.get("role", "")) == "core" else "辅助"
		row.show_entry(String(comp.get("name", definition_id)), role, found)
	_status_label.text = "已发现 %d / 共 %d（组件图鉴，不是背包）" % [discovered, definition_ids.size()]
