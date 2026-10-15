extends Area2D
## 弹弓石弹：直线飞行，命中敌人后造成伤害并消失。

@export var speed: float = 420.0
@export var lifetime: float = 2.0

var damage: int = 1
var _direction: Vector2 = Vector2.RIGHT
var _alive: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null and sprite.texture == null:
		sprite.texture = load("res://assets/sprites/projectiles/stone.png")


func setup(direction: Vector2, dmg: int) -> void:
	if direction.length_squared() < 0.0001:
		_direction = Vector2.RIGHT
	else:
		_direction = direction.normalized()
	damage = dmg
	rotation = _direction.angle()


func _physics_process(delta: float) -> void:
	global_position += _direction * speed * delta
	_alive += delta
	if _alive >= lifetime:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body == null or not body.is_in_group("enemies"):
		return
	if body.has_method("take_damage"):
		body.take_damage(damage)
		print("Stone hit enemy")
	queue_free()
