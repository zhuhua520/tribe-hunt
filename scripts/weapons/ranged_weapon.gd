extends Node2D
## 弹弓：自动朝射程内最近敌人发射石弹。与近战武器并存。

const WEAPON_CATEGORY := "ranged"

@export var damage: int = 1
@export var attack_range: float = 320.0
@export var cooldown: float = 0.85
@export var projectile_scene: PackedScene

@onready var sprite: Sprite2D = $Sprite2D

var _cooldown_left: float = 0.0


func _ready() -> void:
	if sprite.texture == null:
		sprite.texture = load("res://assets/sprites/weapons/sling.png")
	sprite.position = Vector2(-16, 8)
	if projectile_scene == null:
		projectile_scene = load("res://scenes/weapons/stone_projectile.tscn")


func _physics_process(delta: float) -> void:
	var owner_body := get_parent()
	if owner_body == null or not ("hp" in owner_body) or owner_body.hp <= 0:
		return

	if _cooldown_left > 0.0:
		_cooldown_left = maxf(0.0, _cooldown_left - delta)

	var target := _find_nearest_enemy()
	if target == null:
		return

	var to_target := target.global_position - global_position
	var effective_attack_range := BuildRunService.get_effective_attack_range(
		attack_range, WEAPON_CATEGORY
	)
	# 弹弓挂在身侧，只朝向目标，不强行覆盖玩家朝向。
	sprite.flip_h = to_target.x < 0.0

	if _cooldown_left > 0.0:
		return
	if to_target.length() > effective_attack_range:
		return
	if projectile_scene == null:
		return

	_cooldown_left = BuildRunService.get_effective_cooldown(cooldown, WEAPON_CATEGORY)
	var stone := projectile_scene.instantiate() as Area2D
	var host := get_tree().current_scene
	if host == null:
		host = owner_body.get_parent()
	host.add_child(stone)
	stone.global_position = global_position
	if stone.has_method("setup"):
		stone.setup(to_target, damage)
	print("Sling fired")


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
