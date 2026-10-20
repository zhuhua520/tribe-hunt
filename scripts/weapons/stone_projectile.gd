extends Area2D
const Targeting := preload("res://scripts/combat/combat_targeting.gd")
## 直线弹。默认打中第一个敌人或墙就消失。穿杨弓把 max_hits 设为 2，第二个目标伤害按 falloff 衰减。
## 每个物理帧沿位移做射线，避免高速穿过薄目标或先打到墙后的敌人。

const PATH_MASK := 2 | Targeting.TERRAIN_LAYER
const MAX_PATH_QUERIES := 6

@export var speed: float = 420.0
@export var lifetime: float = 2.0

var damage: int = 1
var armor_break: int = 0
var max_hits: int = 1
var falloff: float = 1.0
var source: Node = null
var snapshot_id: String = ""
var origin_effect_id: String = "projectile"
## 玩家弹打 enemies。哨械把这一项改成 player，并改 path_mask，避免打到自己或其他敌人。
var victim_group: StringName = &"enemies"
var path_mask: int = PATH_MASK
var _direction: Vector2 = Vector2.RIGHT
var _alive: float = 0.0
var _spent: bool = false
var _hits: int = 0
var _seen: Dictionary = {}
var _attack_id: int = 0
var _closed: bool = false


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
	if _attack_id == 0:
		_attack_id = Targeting.begin_attack()


func _physics_process(delta: float) -> void:
	if _spent:
		return
	var end := global_position + _direction * speed * delta
	var excluded: Array[RID] = []
	for _step in MAX_PATH_QUERIES:
		if _spent or global_position.distance_to(end) <= 0.5:
			break
		var space := get_world_2d().direct_space_state
		var query := PhysicsRayQueryParameters2D.create(global_position, end, path_mask)
		query.exclude = excluded
		var result := space.intersect_ray(query)
		if result.is_empty():
			global_position = end
			break
		global_position = result.position
		var body: Node = result.collider
		if _is_terrain(body):
			_finish()
			return
		if _is_victim(body) and not _seen.has(body.get_instance_id()):
			_strike_target(body)
			if _spent:
				return
		excluded.append(result.rid)
	_alive += delta
	if _alive >= lifetime:
		_finish()


func _on_body_entered(body: Node2D) -> void:
	if _spent:
		return
	if _is_terrain(body):
		_finish()
		return
	if not _is_victim(body) or _seen.has(body.get_instance_id()):
		return
	_seen[body.get_instance_id()] = true
	var dealt := _damage_for_hit()
	var extra := _hits > 0
	_hits += 1
	if _hits >= maxi(1, max_hits):
		_spent = true
		queue_free()
	_apply_context(body, dealt, extra)


func _strike_target(body: Node) -> void:
	if _seen.has(body.get_instance_id()):
		return
	_seen[body.get_instance_id()] = true
	var dealt := _damage_for_hit()
	var extra := _hits > 0
	_hits += 1
	_apply_context(body, dealt, extra)
	if _hits >= maxi(1, max_hits):
		_finish()


func _damage_for_hit() -> int:
	if _hits <= 0:
		return damage
	return maxi(1, int(round(float(damage) * pow(falloff, _hits))))


func _apply_context(body: Node, dealt: int, extra: bool) -> void:
	if _attack_id == 0:
		_attack_id = Targeting.begin_attack()
	var context = load("res://scripts/combat/hit_context.gd").new()
	context.attack_instance_id = _attack_id
	context.source = source
	context.snapshot_id = snapshot_id
	context.target = body
	context.base_damage = dealt
	context.snapshot_damage = dealt
	context.armor_break = armor_break
	context.origin_effect_id = "projectile_extra" if extra else origin_effect_id
	Targeting.resolve(context)


func _finish() -> void:
	_spent = true
	if not _closed and _attack_id > 0:
		_closed = true
		Targeting.close_attack(_attack_id)
	queue_free()


func _exit_tree() -> void:
	if not _closed and _attack_id > 0:
		_closed = true
		Targeting.close_attack(_attack_id)


func _is_victim(body: Node) -> bool:
	if body == source:
		return false
	if victim_group == &"enemies":
		return Targeting.is_live_target(body)
	return is_instance_valid(body) and not body.is_queued_for_deletion() \
		and body.is_in_group(victim_group) and body.has_method("take_damage") \
		and (not ("hp" in body) or int(body.hp) > 0)


func _is_terrain(body: Node) -> bool:
	return body is CollisionObject2D and (body.collision_layer & Targeting.TERRAIN_LAYER) != 0
