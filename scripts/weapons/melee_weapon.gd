extends Node2D
## 木棍：自动攻击射程内最近的敌人。

const WEAPON_CATEGORY := "melee"

@export var damage: int = 1
@export var attack_range: float = 72.0
@export var cooldown: float = 0.45

@onready var sprite: Sprite2D = $Sprite2D

var _cooldown_left: float = 0.0
var _swing_left: float = 0.0


func _ready() -> void:
	if sprite.texture == null:
		sprite.texture = load("res://assets/sprites/weapons/club.png")
	sprite.position = Vector2(18, 0)


func _physics_process(delta: float) -> void:
	var owner_body := get_parent()
	if owner_body == null or not ("hp" in owner_body) or owner_body.hp <= 0:
		return

	if _cooldown_left > 0.0:
		_cooldown_left = maxf(0.0, _cooldown_left - delta)
	if _swing_left > 0.0:
		_swing_left = maxf(0.0, _swing_left - delta)
		sprite.rotation = lerpf(-0.8, 0.9, 1.0 - _swing_left / 0.12)
	else:
		sprite.rotation = 0.0

	var target := _find_nearest_enemy()
	if target == null:
		return

	var to_target := target.global_position - global_position
	look_at(target.global_position)

	if _cooldown_left > 0.0:
		return
	if to_target.length() > attack_range:
		return

	_cooldown_left = BuildRunService.get_effective_cooldown(cooldown, WEAPON_CATEGORY)
	_swing_left = 0.12
	if target.has_method("take_damage"):
		target.take_damage(damage)
		print("Club hit enemy")


func _find_nearest_enemy() -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("enemies"):
		if node == null or not is_instance_valid(node):
			continue
		if not (node is Node2D):
			continue
		if "hp" in node and node.hp <= 0:
			continue
		var enemy := node as Node2D
		var dist := global_position.distance_to(enemy.global_position)
		if dist < best_dist:
			best_dist = dist
			best = enemy
	return best
