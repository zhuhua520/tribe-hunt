extends Area2D
## 地上的可拾取物：存活的玩家在范围内按 interact 拾取。暂停时不接收输入。
## object_id 非空：一次性拾取（D2），领取状态记在 ProgressState，场景重载或往返后不再出现。
## object_id 为空：普通掉落物，不记领取状态，每个实例拾取一次后消失，数量可叠加。
## 加入 inspectable_items 组，供 ItemDetailPopup 在鼠标指向时显示详情。

signal picked(item_id: StringName, amount: int)

@export var object_id: StringName = &""
@export var item: ItemDefinition
@export var amount: int = 1
## 鼠标指向判定半径（世界坐标），与拾取范围分开。
@export var hover_radius: float = 22.0

@onready var _prompt: Label = $Prompt

var _player: Node2D
var _taken: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitorable = false
	if object_id != &"" and ProgressState.is_claimed(object_id):
		queue_free()
		return
	add_to_group("inspectable_items")
	_prompt.visible = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _unhandled_input(event: InputEvent) -> void:
	if _player == null or _taken or event.is_echo() or not event.is_action_pressed("interact"):
		return
	if not is_instance_valid(_player) or ("hp" in _player and _player.hp <= 0):
		return
	get_viewport().set_input_as_handled()
	if item == null:
		return
	var accepted := ProgressState.add_item(item.item_id, amount) if object_id == &"" \
		else ProgressState.claim_pickup(object_id, item.item_id, amount)
	if not accepted:
		return
	_taken = true
	picked.emit(item.item_id, amount)
	queue_free()


func contains_point(world_point: Vector2) -> bool:
	return not _taken and global_position.distance_to(world_point) <= hover_radius


func is_player_in_range() -> bool:
	return _player != null and is_instance_valid(_player)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player = body as Node2D
		_prompt.visible = true


func _on_body_exited(body: Node) -> void:
	if body == _player:
		_player = null
		_prompt.visible = false
