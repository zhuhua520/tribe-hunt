extends HBoxContainer

signal action_pressed(slot: String)
signal lock_pressed(slot: String)
signal dismantle_pressed(slot: String)
signal enhance_pressed(slot: String)

var slot: String = ""

@onready var _name_label: Label = $NameLabel
@onready var _detail_label: Label = $DetailLabel
@onready var _action_button: Button = $ActionButton
@onready var _lock_button: Button = $LockButton
@onready var _dismantle_button: Button = $DismantleButton
@onready var _enhance_button: Button = $EnhanceButton


func _ready() -> void:
	_action_button.pressed.connect(func() -> void: action_pressed.emit(slot))
	_lock_button.pressed.connect(func() -> void: lock_pressed.emit(slot))
	_dismantle_button.pressed.connect(func() -> void: dismantle_pressed.emit(slot))
	_enhance_button.pressed.connect(func() -> void: enhance_pressed.emit(slot))


func show_slot(
	next_slot: String,
	title: String,
	detail: String,
	action_text: String,
	lock_text: String = "",
	dismantle_text: String = "",
	enhance_text: String = ""
) -> void:
	slot = next_slot
	_name_label.text = title
	_detail_label.text = detail
	_action_button.text = action_text
	_action_button.visible = action_text != ""
	_lock_button.text = lock_text
	_lock_button.visible = lock_text != ""
	_dismantle_button.text = dismantle_text
	_dismantle_button.visible = dismantle_text != ""
	_enhance_button.text = enhance_text
	_enhance_button.visible = enhance_text != ""
