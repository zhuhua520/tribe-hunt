extends Node2D
## 动作试验场：两具无甲木桩、一具装甲目标、连击、蓄力斩和闪避预警。可直接运行本场景。

@export var camera_limits: Rect2i = Rect2i(-664, -424, 1328, 848)

@onready var _player: CharacterBody2D = $Player
@onready var _dummy_label: Label = $Dummy/HpLabel
@onready var _dummy: Node2D = $Dummy
@onready var _dummy_b_label: Label = $DummyB/HpLabel
@onready var _dummy_b: Node2D = $DummyB


func _ready() -> void:
	DisplayServer.window_set_title("TribeHunt - 动作试验场")
	var camera := _player.get_node("Camera2D") as Camera2D
	camera.position_smoothing_enabled = false
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.limit_left = camera_limits.position.x
	camera.limit_top = camera_limits.position.y
	camera.limit_right = camera_limits.end.x
	camera.limit_bottom = camera_limits.end.y
	camera.make_current()


func _process(_delta: float) -> void:
	if is_instance_valid(_dummy):
		_dummy_label.text = "木桩 %d/%d" % [_dummy.hp, _dummy.max_hp]
	if is_instance_valid(_dummy_b):
		_dummy_b_label.text = "木桩 %d/%d" % [_dummy_b.hp, _dummy_b.max_hp]
