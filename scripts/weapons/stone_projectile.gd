extends Area2D
const Targeting := preload("res://scripts/combat/combat_targeting.gd")
## 弹弓石弹：直线飞行，命中第一个敌人或实心地形后消失。
## 每个物理帧先沿本帧位移做射线检测，按路径先后结算，避免高速穿过薄目标或同帧打到墙后敌人；
## 重叠回调只兜底处理生成时已与目标重叠的情况。

const PATH_MASK := 2 | Targeting.TERRAIN_LAYER
const MAX_PATH_QUERIES := 4

@export var speed: float = 420.0
@export var lifetime: float = 2.0

var damage: int = 1
var _direction: Vector2 = Vector2.RIGHT
var _alive: float = 0.0
var _spent: bool = false


func _ready() -> void:
	add_to_group("combat_projectiles")
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
	if _spent:
		return
	var step := _direction * speed * delta
	var hit := _first_hit_along(step)
	if not hit.is_empty():
		global_position = hit.position
		_resolve(hit.collider)
		return
	global_position += step
	_alive += delta
	if _alive >= lifetime:
		queue_free()


func _first_hit_along(step: Vector2) -> Dictionary:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + step, PATH_MASK)
	var excluded: Array[RID] = []
	for i in MAX_PATH_QUERIES:
		query.exclude = excluded
		var result := space.intersect_ray(query)
		if result.is_empty():
			return {}
		if _is_terrain(result.collider) or Targeting.is_live_target(result.collider):
			return result
		excluded.append(result.rid)
	return {}


func _on_body_entered(body: Node2D) -> void:
	if _spent or not (_is_terrain(body) or Targeting.is_live_target(body)):
		return
	_resolve(body)


func _resolve(body: Node) -> void:
	# 同帧多个碰撞只结算一次。先排队释放：致命一击会在本回调内结束战斗，不能再禁用正处于回调中的自身碰撞体。
	_spent = true
	queue_free()
	if not _is_terrain(body):
		Targeting.hit(body, damage)


func _is_terrain(body: Node) -> bool:
	return body is CollisionObject2D and (body.collision_layer & Targeting.TERRAIN_LAYER) != 0
