extends HBoxContainer

signal equip_pressed(item_id: StringName)

var item_id: StringName = &""

@onready var _name_label: Label = $NameLabel
@onready var _stats_label: Label = $StatsLabel
@onready var _reason_label: Label = $ReasonLabel
@onready var _equip_button: Button = $EquipButton


func _ready() -> void:
	_equip_button.pressed.connect(_on_equip_pressed)


func show_entry(next_id: StringName, display_name: String, reason: String, can_equip: bool, stats: String = "") -> void:
	item_id = next_id
	_name_label.text = display_name
	_stats_label.text = stats
	_stats_label.visible = stats != ""
	_reason_label.text = reason
	_reason_label.visible = reason != ""
	_equip_button.visible = can_equip


func _on_equip_pressed() -> void:
	equip_pressed.emit(item_id)
