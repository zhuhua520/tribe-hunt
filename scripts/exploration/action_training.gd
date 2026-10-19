extends Node2D
## S4 动作试验场（灰盒）：手动攻击训练木桩、闪避预警攻击。可直接运行本场景测试，不接入主流程。

@export var camera_limits: Rect2i = Rect2i(-664, -424, 1328, 848)

@onready var _player: CharacterBody2D = $Player
@onready var _dummy_label: Label = $Dummy/HpLabel
@onready var _dummy: Node2D = $Dummy


func _ready() -> void:
	DisplayServer.window_set_title("TribeHunt - 动作试验场（S4 原型）")
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
