extends Area2D
## 店铺门口。玩家站在范围内按交互才打开页面，走过不会自动弹窗。

@export var shop_title: String = ""
@export var category_id: String = ""
@export var opens_craft: bool = false

var _occupied: bool = false


func _ready() -> void:
	body_entered.connect(_set_occupied.bind(true))
	body_exited.connect(_set_occupied.bind(false))


func player_inside() -> bool:
	return _occupied


func _set_occupied(body: Node, occupied: bool) -> void:
	if not body is CharacterBody2D:
		return
	_occupied = occupied
