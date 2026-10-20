extends Area2D
## 设施开关：第一次交互打开对应的门并记下领取标记。重复操作不再发奖励。

signal activated

@export var object_id: StringName = &"facility.switch"
@export var door_path: NodePath = NodePath("../InnerDoor")

@onready var _prompt: Label = $Prompt

var _player: Node2D
var _door: CollisionObject2D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitorable = false
	_door = get_node_or_null(door_path) as CollisionObject2D
	if ProgressState.is_claimed(object_id):
		_set_open(true)
		_prompt.text = "已经开启"
	else:
		_prompt.text = "E 开启"
	_prompt.visible = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _unhandled_input(event: InputEvent) -> void:
	if _player == null or event.is_echo() or not event.is_action_pressed("interact"):
		return
	if not is_instance_valid(_player) or ("hp" in _player and _player.hp <= 0):
		return
	get_viewport().set_input_as_handled()
	try_activate()


func try_activate() -> bool:
	if ProgressState.is_claimed(object_id):
		_set_open(true)
		_prompt.text = "已经开启"
		return false
	ProgressState.mark_claimed(object_id)
	_set_open(true)
	_prompt.text = "已经开启"
	activated.emit()
	return true


func is_door_open() -> bool:
	return _door != null and _door.collision_layer == 0


func _set_open(open: bool) -> void:
	if _door == null:
		return
	_door.collision_layer = 0 if open else 16
	var visual := _door.get_node_or_null("Visual")
	if visual != null:
		visual.visible = not open


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player = body as Node2D
		_prompt.visible = true


func _on_body_exited(body: Node) -> void:
	if body == _player:
		_player = null
		_prompt.visible = false
