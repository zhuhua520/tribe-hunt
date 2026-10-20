extends Area2D
## 地上的可拾取物：存活的玩家在范围内按 interact 拾取。暂停时不接收输入。
## object_id 非空：一次性拾取（D2），领取状态记在 ProgressState，场景重载或往返后不再出现。
## object_id 为空：普通掉落物，不记领取状态，每个实例拾取一次后消失，数量可叠加。
## 加入 inspectable_items 组，供 ItemDetailPopup 在鼠标指向时显示详情。

signal picked(item_id: StringName, amount: int)

@export var object_id: StringName = &""
@export var item: ItemDefinition
@export var catalog_item_id: StringName = &""
@export var amount: int = 1
## 非空时，这次拾取发放一个组件实例，并使用 object_id 作为唯一领取标记。
@export var component_definition_id: String = ""
## 非空时按掉落表发放。宝箱拾取直接进入库存。
@export var loot_table_id: String = ""
@export var loot_seed: int = 0
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
	if item == null and catalog_item_id != &"":
		item = ProgressState.get_definition(catalog_item_id)
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
	try_pickup()


func try_pickup() -> bool:
	if _taken:
		return false
	if loot_table_id != "":
		var result: Dictionary = preload("res://scripts/loot/loot_table.gd").release_once(self, loot_table_id, loot_seed, true)
		if result.get("ok", false) != true:
			_prompt.text = "\n".join(result.get("errors", PackedStringArray()))
			return false
		if object_id != &"" and not ProgressState.is_claimed(object_id):
			ProgressState.mark_claimed(object_id)
		_taken = true
		picked.emit(&"", 0)
		queue_free()
		return true
	if component_definition_id != "":
		var reason := ProgressState.grant_claimed_instance(object_id, component_definition_id)
		if reason != "":
			_prompt.text = reason
			return false
		_taken = true
		picked.emit(&"", 0)
		queue_free()
		return true
	if item == null:
		return false
	if _player != null and (not is_instance_valid(_player) or ("hp" in _player and _player.hp <= 0)):
		return false
	var accepted := ProgressState.add_item(item.item_id, amount) if object_id == &"" \
		else ProgressState.claim_pickup(object_id, item.item_id, amount)
	if not accepted:
		return false
	_taken = true
	picked.emit(item.item_id, amount)
	queue_free()
	return true


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
