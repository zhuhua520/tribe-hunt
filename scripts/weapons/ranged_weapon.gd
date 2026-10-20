extends Node2D
## 过渡自动弹弓。正式战斗始终出手；手动夹具里才看旧的 auto_attack 开关。
## 发射时取方向，弹体不追踪。闪避、受击和死亡期间不发射新弹。

const Targeting := preload("res://scripts/combat/combat_targeting.gd")
const SettingsStore := preload("res://scripts/save/settings_store.gd")

@export var definition: WeaponDefinition = preload("res://data/build/weapon_sling.tres")
@export var projectile_scene: PackedScene = preload("res://scenes/weapons/stone_projectile.tscn")
@onready var sprite: Sprite2D = $Sprite2D

var _cooldown_left: float = 0.0


func _ready() -> void:
	if sprite.texture == null:
		sprite.texture = load("res://assets/sprites/weapons/sling.png")
	sprite.position = Vector2(-16, 8)
	var wielder := get_parent()
	if wielder == null or not bool(wielder.get("use_historical_auto_weapons")):
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	var wielder := get_parent()
	if definition == null or wielder == null or not "hp" in wielder or wielder.hp <= 0:
		return
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	if _cooldown_left > 0.0 or not _can_begin_auto_attack():
		return
	var radius := BuildRunService.get_effective_attack_range(definition.attack_range, definition.category_tag)
	var target := Targeting.nearest_enemy(self, radius)
	if target == null or projectile_scene == null:
		return
	var direction := target.global_position - global_position
	sprite.flip_h = direction.x < 0.0
	var stone := projectile_scene.instantiate() as Area2D
	if stone == null:
		return
	# 与持有者使用同一场地，避免依赖 current_scene 或全局唯一玩家。
	wielder.get_parent().add_child(stone)
	stone.global_position = global_position
	stone.speed = BuildRunService.get_effective_projectile_speed(definition)
	stone.lifetime = definition.projectile_lifetime
	stone.setup(direction, BuildRunService.get_effective_damage(definition))
	_cooldown_left = BuildRunService.get_effective_cooldown(definition.cooldown, definition.category_tag)


func _can_begin_auto_attack() -> bool:
	var wielder := get_parent()
	if wielder == null:
		return false
	var actions := wielder.get_node_or_null("ActionController")
	if actions == null:
		return true
	if actions.has_method("blocks_new_auto_attack") and actions.blocks_new_auto_attack():
		return false
	if actions.has_method("allows_transitional_auto"):
		return actions.allows_transitional_auto()
	return SettingsStore.is_auto_attack_enabled()
