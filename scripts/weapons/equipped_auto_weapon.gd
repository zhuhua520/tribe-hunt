extends Node2D
## 正式战斗只跑当前装备的这一把。扇形扫击或圆形范围，不走连击和蓄力输入。
## 冷却记在 ProgressState，换场景和换装都不清零，也不写入存档。

const Targeting := preload("res://scripts/combat/combat_targeting.gd")
const Volume := preload("res://scripts/combat/melee_attack_volume.gd")
const Derived := preload("res://scripts/build/build_derived_stats.gd")
const PROJECTILE_SCENE := preload("res://scenes/weapons/stone_projectile.tscn")

var _flash_left: float = 0.0
var _flash_dir: Vector2 = Vector2.RIGHT
var _flash_range: float = 0.0
var _flash_arc: float = 110.0
var _flash_behavior: String = "sector_sweep"


func _physics_process(delta: float) -> void:
	_flash_left = maxf(0.0, _flash_left - delta)
	queue_redraw()
	var wielder := get_parent()
	if wielder == null or not ("hp" in wielder) or wielder.hp <= 0:
		return
	if bool(wielder.get("use_historical_auto_weapons")):
		return
	var actions := wielder.get_node_or_null("ActionController")
	if actions != null and actions.has_method("blocks_new_auto_attack") and actions.blocks_new_auto_attack():
		return
	if actions != null and actions.has_method("allows_transitional_auto") and not actions.allows_transitional_auto():
		return
	ProgressState.attack_cooldown_left = maxf(0.0, ProgressState.attack_cooldown_left - delta)
	if ProgressState.attack_cooldown_left > 0.0:
		return
	var profile: Dictionary = Derived.from_weapon(ProgressState.equipped_weapon_id())
	var target := Targeting.nearest_enemy(self, float(profile.range))
	if target == null:
		return
	_strike(profile, target)
	ProgressState.attack_cooldown_left = float(profile.interval)


func _strike(profile: Dictionary, aim_target: Node2D) -> void:
	var behavior := String(profile.behavior_id)
	var reach := float(profile.range)
	var arc := deg_to_rad(float(profile.arc_degrees))
	var facing := aim_target.global_position - global_position
	if facing.length_squared() < 0.0001:
		facing = Vector2.RIGHT
	facing = facing.normalized()
	var frozen_damage := int(profile.damage)
	if behavior == "projectile":
		_launch_projectile(profile, facing, frozen_damage)
		_remember_flash(facing, reach, float(profile.arc_degrees), behavior)
		return
	var attack_id := Targeting.begin_attack()
	var wielder := get_parent()
	for candidate in get_tree().get_nodes_in_group("enemies"):
		if not Targeting.is_live_target(candidate):
			continue
		var offset: Vector2 = candidate.global_position - global_position
		if offset.length() > reach + Volume.body_radius(candidate):
			continue
		if behavior == "sector_sweep" and offset.length() > 0.001 and absf(facing.angle_to(offset)) > arc * 0.5:
			continue
		if not Targeting.has_line_of_sight(self, candidate):
			continue
		var context = load("res://scripts/combat/hit_context.gd").new()
		context.attack_instance_id = attack_id
		context.source = wielder
		context.snapshot_id = String(profile.item_id)
		context.target = candidate
		context.base_damage = frozen_damage
		context.snapshot_damage = frozen_damage
		context.origin_effect_id = String(profile.behavior_id)
		context.armor_break = int(profile.get("armor_break", 0))
		Targeting.resolve(context)
	Targeting.close_attack(attack_id)
	_remember_flash(facing, reach, float(profile.arc_degrees), behavior)


func _launch_projectile(profile: Dictionary, facing: Vector2, frozen_damage: int) -> void:
	var wielder := get_parent()
	if wielder == null or wielder.get_parent() == null:
		return
	var arrow = PROJECTILE_SCENE.instantiate()
	wielder.get_parent().add_child(arrow)
	arrow.global_position = global_position
	arrow.speed = maxf(1.0, float(profile.get("projectile_speed", 280.0)))
	arrow.lifetime = maxf(0.05, float(profile.get("lifetime", 1.4)))
	arrow.armor_break = int(profile.get("armor_break", 0))
	arrow.source = wielder
	arrow.snapshot_id = String(profile.get("item_id", ""))
	arrow.origin_effect_id = "projectile"
	arrow.max_hits = maxi(1, int(profile.get("pierce_count", 1)))
	arrow.falloff = clampf(float(profile.get("damage_falloff", 1.0)), 0.05, 1.0)
	arrow.setup(facing, frozen_damage)


func _remember_flash(facing: Vector2, reach: float, arc_degrees: float, behavior: String) -> void:
	_flash_left = 0.12
	_flash_dir = facing
	_flash_range = reach
	_flash_arc = arc_degrees
	_flash_behavior = behavior
	queue_redraw()


func _draw() -> void:
	if _flash_left <= 0.0:
		return
	var color := Color(0.95, 0.55, 0.2, 0.28)
	if _flash_behavior == "area_strike":
		draw_arc(Vector2.ZERO, _flash_range, 0.0, TAU, 24, color, 2.0)
		return
	var half := deg_to_rad(_flash_arc) * 0.5
	var base := _flash_dir.angle()
	draw_arc(Vector2.ZERO, _flash_range, base - half, base + half, 12, color, 2.0)
	draw_line(Vector2.ZERO, Vector2.from_angle(base - half) * _flash_range, color, 2.0)
	draw_line(Vector2.ZERO, Vector2.from_angle(base + half) * _flash_range, color, 2.0)
