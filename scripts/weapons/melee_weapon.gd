extends Node2D
## 自动木棍（D1 后为可开关辅助，默认关闭）：准备、命中、收招；目标在出手时锁定，命中时重新检查距离和实心地形遮挡。

const PreviewArt := preload("res://scripts/systems/borrowed_preview_art.gd")
const Targeting := preload("res://scripts/combat/combat_targeting.gd")
const SettingsStore := preload("res://scripts/save/settings_store.gd")

@export var definition: WeaponDefinition = preload("res://data/build/weapon_club.tres")
@onready var sprite: Sprite2D = $Sprite2D

var _cooldown_left: float = 0.0
var _phase_left: float = 0.0
var _phase: String = "idle"
var _target: Node2D


func _ready() -> void:
	if sprite.texture == null:
		sprite.texture = PreviewArt.texture("club_in_hand.png")
	sprite.position = Vector2(18, 0)


func _physics_process(delta: float) -> void:
	var wielder := get_parent()
	if definition == null or wielder == null or not "hp" in wielder or wielder.hp <= 0:
		return
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	if _phase != "idle":
		_phase_left = maxf(0.0, _phase_left - delta)
		if _phase == "windup":
			sprite.rotation = -0.8
			if _phase_left <= 0.0:
				_resolve_strike()
		else:
			sprite.rotation = lerpf(-0.8, 0.9, 1.0 - _phase_left / maxf(0.01, definition.swing_seconds))
			if _phase_left <= 0.0:
				_phase = "idle"
				sprite.rotation = 0.0
		return
	if _cooldown_left > 0.0 or not SettingsStore.is_auto_attack_enabled():
		return
	_target = Targeting.nearest_enemy(self, effective_range())
	if _target == null:
		return
	look_at(_target.global_position)
	_cooldown_left = BuildRunService.get_effective_cooldown(definition.cooldown, definition.category_tag)
	_phase = "windup"
	_phase_left = maxf(0.0, definition.windup_seconds)
	if _phase_left <= 0.0:
		_resolve_strike()


func effective_range() -> float:
	return BuildRunService.get_effective_attack_range(definition.attack_range, definition.category_tag)


func _resolve_strike() -> void:
	_phase = "swing"
	_phase_left = maxf(0.01, definition.swing_seconds)
	if Targeting.is_live_target(_target) and global_position.distance_to(_target.global_position) <= effective_range() \
			and Targeting.has_line_of_sight(self, _target):
		Targeting.hit(_target, BuildRunService.get_effective_damage(definition))
	_target = null
