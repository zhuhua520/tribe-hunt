extends Node2D
## 玩家手动动作。D1：鼠标指向瞄准，左键攻击，空格闪避。
## S5a 剑：点按为三段连击，按住后松开为蓄力斩。每一段是独立攻击实例。
## 生效阶段用关键帧圆和相邻采样扫掠；同一实例对同一目标只结算一次。
## 前摇与生效不可取消；后摇后段和蓄力可被闪避取消。闪避不消耗耐力。
## 时长和范围都是测试值。调试圈就是本帧实际查询的采样，等 A2 动作图集。

signal attack_started(direction: Vector2)
signal attack_hit(target: Node)
signal dodge_started(direction: Vector2)

enum State { IDLE, WINDUP, ACTIVE, RECOVERY, CHARGE, DODGE, HURT, DEAD }

const SettingsStore := preload("res://scripts/save/settings_store.gd")
const Targeting := preload("res://scripts/combat/combat_targeting.gd")
const SwordData := preload("res://scripts/combat/sword_attack_data.gd")
const WeaponEffectLink := preload("res://scripts/items/weapon_effect_link.gd")
const Volume := preload("res://scripts/combat/melee_attack_volume.gd")

@export var attack_move_scale: float = 0.35
@export var dodge_seconds: float = 0.24
@export var dodge_speed: float = 560.0
@export var dodge_invulnerable_seconds: float = 0.2
@export var dodge_cooldown_seconds: float = 0.15
@export var hurt_stun_seconds: float = 0.18
@export var buffer_seconds: float = 0.2

var state: int = State.IDLE
var aim_direction: Vector2 = Vector2.RIGHT
var attack_count: int = 0
var dodge_count: int = 0
## 测试用：非空时代替鼠标位置作为瞄准点（世界坐标）。
var test_aim_point: Variant = null
## 当前手持物品。攻击方式从物品表连到特效表，默认试验短剑。
var weapon_item_id: StringName = &"sword_training"

var _combo: Array[MeleeAttackDefinition] = []
var _charged: MeleeAttackDefinition
var _weapon: WeaponDefinition
var _attack: MeleeAttackDefinition
var _combo_index: int = 0
var _state_left: float = 0.0
var _active_t: float = 0.0
var _recovery_elapsed: float = 0.0
var _prev_origin: Vector2 = Vector2.ZERO
var _invulnerable_left: float = 0.0
var _dodge_cooldown_left: float = 0.0
var _dodge_direction: Vector2 = Vector2.RIGHT
var _buffered_action: StringName = &""
var _buffer_left: float = 0.0
var _hit_ids: Dictionary = {}
var _hit_samples: Array = []
var _visual_circles: Array = []
var _move_input: Vector2 = Vector2.ZERO
var _attack_held: bool = false
var _hold_time: float = 0.0

@onready var _player: CharacterBody2D = get_parent()
@onready var _arc: Polygon2D = $AttackArc
@onready var _aim_line: Line2D = $AimLine
@onready var _auto_label: Label = $AutoLabel


func _ready() -> void:
	_combo = SwordData.combo_attacks()
	_charged = SwordData.charged_attack()
	_weapon = SwordData.weapon()
	_arc.visible = false
	_refresh_auto_label()
	_update_visuals()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		_clear_buffer()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("auto_attack_toggle"):
		get_viewport().set_input_as_handled()
		SettingsStore.set_auto_attack(not SettingsStore.is_auto_attack_enabled())
		_refresh_auto_label()
	elif event.is_action_pressed("attack"):
		get_viewport().set_input_as_handled()
		_attack_held = true
		_hold_time = 0.0
		if state != State.IDLE:
			request(&"attack")
	elif event.is_action_released("attack"):
		get_viewport().set_input_as_handled()
		_attack_held = false
		if state == State.CHARGE:
			_start_attack_instance(_charged, true)
		elif state == State.IDLE:
			request(&"attack")
	elif event.is_action_pressed("dodge"):
		get_viewport().set_input_as_handled()
		request(&"dodge")


func _physics_process(delta: float) -> void:
	_update_aim()
	_invulnerable_left = maxf(0.0, _invulnerable_left - delta)
	_dodge_cooldown_left = maxf(0.0, _dodge_cooldown_left - delta)
	if _buffer_left > 0.0:
		_buffer_left -= delta
		if _buffer_left <= 0.0:
			_clear_buffer()
	if _attack_held and state == State.IDLE and _player_alive():
		_hold_time += delta
		if _hold_time >= SwordData.CHARGE_THRESHOLD_SECONDS:
			_begin_charge()
	if state == State.RECOVERY:
		_recovery_elapsed += delta
	if state != State.IDLE and state != State.DEAD and state != State.CHARGE:
		var previous_left := _state_left
		_state_left -= delta
		match state:
			State.WINDUP:
				if _state_left <= 0.0 and _attack != null:
					_enter(State.ACTIVE, _attack.active_seconds)
			State.ACTIVE:
				_advance_active(previous_left)
				if _state_left <= 0.0 and _attack != null:
					_enter(State.RECOVERY, _attack.recovery_seconds)
			_:
				if _state_left <= 0.0:
					_enter(State.IDLE, 0.0)
	_try_consume_buffer()
	_update_visuals()
	queue_redraw()


## 记录一次动作请求。攻击从这里进入连击；蓄力只由按住攻击键进入。
func request(action: StringName) -> void:
	if state == State.DEAD or not _player_alive():
		return
	_buffered_action = action
	_buffer_left = buffer_seconds
	_try_consume_buffer()


func movement_velocity(input_vector: Vector2, move_speed: float) -> Vector2:
	_move_input = input_vector
	match state:
		State.DODGE:
			return _dodge_direction * dodge_speed
		State.CHARGE:
			return input_vector * move_speed * SwordData.CHARGE_MOVE_SCALE
		State.WINDUP, State.ACTIVE, State.RECOVERY:
			return input_vector * move_speed * attack_move_scale
		State.HURT, State.DEAD:
			return Vector2.ZERO
	return input_vector * move_speed


func is_invulnerable() -> bool:
	return _invulnerable_left > 0.0


func is_attacking() -> bool:
	return state == State.WINDUP or state == State.ACTIVE or state == State.RECOVERY


func locks_facing() -> bool:
	return is_attacking() or state == State.CHARGE


func has_buffered_action() -> bool:
	return _buffered_action != &""


func current_attack_id() -> String:
	return "" if _attack == null else _attack.attack_id


func effect_attack_style() -> String:
	return WeaponEffectLink.attack_style(weapon_item_id)


func combo_index() -> int:
	return _combo_index


func recovery_cancel_open() -> bool:
	return state == State.RECOVERY and _attack != null \
		and _recovery_elapsed >= _attack.recovery_seconds * SwordData.RECOVERY_DODGE_OPEN_RATIO


func hit_samples() -> Array:
	return _hit_samples


func visual_circles() -> Array:
	return _visual_circles


func visual_matches_hits() -> bool:
	if state != State.ACTIVE or _visual_circles.size() != _hit_samples.size():
		return false
	for i in _hit_samples.size():
		var hit: Dictionary = _hit_samples[i]
		var drawn: Dictionary = _visual_circles[i]
		if (hit.center as Vector2).distance_to(drawn.center) > 0.1 or absf(float(hit.radius) - float(drawn.radius)) > 0.1:
			return false
	return true


func state_label() -> String:
	match state:
		State.IDLE:
			return "待机"
		State.WINDUP:
			return "前摇"
		State.ACTIVE:
			return "生效"
		State.RECOVERY:
			return "后摇"
		State.CHARGE:
			return "蓄力"
		State.DODGE:
			return "闪避"
		State.HURT:
			return "受击"
		State.DEAD:
			return "倒下"
	return "未知"


## 开发者菜单用。直接打出连击中的一段，不经过点按缓冲。
func debug_start_combo_step(index: int) -> bool:
	if _combo.is_empty() or index < 0 or index >= _combo.size() or not _player_alive():
		return false
	_attack_held = false
	_hold_time = 0.0
	_clear_buffer()
	_combo_index = index
	_start_attack_instance(_combo[index], false)
	return true


## 开发者菜单用。只进入蓄力，不造成伤害。
func debug_begin_charge() -> bool:
	if not _player_alive():
		return false
	_attack_held = false
	_hold_time = 0.0
	_clear_buffer()
	_begin_charge()
	return true


## 开发者菜单用。直接打出蓄力斩。
func debug_start_charged_slash() -> bool:
	if _charged == null or not _player_alive():
		return false
	_attack_held = false
	_hold_time = 0.0
	_clear_buffer()
	_start_attack_instance(_charged, true)
	return true


func on_hurt() -> void:
	if state == State.DEAD:
		return
	_attack_held = false
	_clear_buffer()
	_enter(State.HURT, hurt_stun_seconds)


func on_defeated() -> void:
	_attack_held = false
	_clear_buffer()
	_invulnerable_left = 0.0
	_enter(State.DEAD, 0.0)


func _draw() -> void:
	for circle in _visual_circles:
		draw_circle(to_local(circle.center), float(circle.radius), _arc_color())


func _try_consume_buffer() -> void:
	if _buffered_action == &"" or not _player_alive():
		return
	if _buffered_action == &"attack":
		if state == State.IDLE:
			_clear_buffer()
			if effect_attack_style() == "heavy_slash":
				_start_attack_instance(_charged, true)
			else:
				_combo_index = 0
				_start_attack_instance(_combo[0], false)
		elif state == State.RECOVERY and effect_attack_style() != "heavy_slash" and _combo_index < _combo.size() - 1:
			_clear_buffer()
			_combo_index += 1
			_start_attack_instance(_combo[_combo_index], false)
	elif _buffered_action == &"dodge" and _can_dodge():
		_clear_buffer()
		_start_dodge()


func _can_dodge() -> bool:
	if _dodge_cooldown_left > 0.0:
		return false
	return state == State.IDLE or state == State.CHARGE or recovery_cancel_open()


func _begin_charge() -> void:
	_hold_time = 0.0
	_combo_index = 0
	_attack = null
	_hit_ids.clear()
	_hit_samples.clear()
	_enter(State.CHARGE, 0.0)


func _start_attack_instance(attack: MeleeAttackDefinition, reset_combo: bool) -> void:
	if reset_combo:
		_combo_index = 0
	_attack = attack
	_hit_ids.clear()
	_hit_samples.clear()
	attack_count += 1
	_update_aim(true)
	_enter(State.WINDUP, attack.windup_seconds)
	attack_started.emit(aim_direction)


func _start_dodge() -> void:
	_attack_held = false
	_dodge_direction = _move_input.normalized() if _move_input.length_squared() > 0.01 else aim_direction
	dodge_count += 1
	_invulnerable_left = dodge_invulnerable_seconds
	_dodge_cooldown_left = dodge_seconds + dodge_cooldown_seconds
	_enter(State.DODGE, dodge_seconds)
	dodge_started.emit(_dodge_direction)


func _enter(next_state: int, seconds: float) -> void:
	state = next_state
	_state_left = seconds
	if next_state == State.IDLE or next_state == State.HURT or next_state == State.DEAD or next_state == State.DODGE:
		_combo_index = 0
		_hit_samples.clear()
		if next_state != State.DODGE:
			_attack = null
	elif next_state == State.ACTIVE and _attack != null:
		_active_t = 0.0
		_prev_origin = _player.global_position
		_hit_samples = Volume.samples_between(_attack, _prev_origin, _prev_origin, aim_direction, 0.0, 0.0)
		_resolve_hits()
	elif next_state == State.RECOVERY:
		_recovery_elapsed = 0.0
		_hit_samples.clear()
	elif next_state == State.CHARGE:
		_hit_samples.clear()


func _advance_active(previous_left: float) -> void:
	if _attack == null:
		return
	var duration := maxf(0.01, _attack.active_seconds)
	var previous_t := clampf(1.0 - previous_left / duration, 0.0, 1.0)
	var next_t := clampf(1.0 - maxf(_state_left, 0.0) / duration, previous_t, 1.0)
	var origin := _player.global_position
	_hit_samples = Volume.samples_between(_attack, _prev_origin, origin, aim_direction, previous_t, next_t)
	_resolve_hits()
	_prev_origin = origin
	_active_t = next_t


func _resolve_hits() -> void:
	if state != State.ACTIVE:
		return
	for candidate in get_tree().get_nodes_in_group("enemies"):
		if _hit_ids.has(candidate.get_instance_id()) or not Targeting.is_live_target(candidate):
			continue
		var radius := Volume.body_radius(candidate)
		if not Volume.overlaps(_hit_samples, candidate.global_position, radius):
			continue
		if not Targeting.has_line_of_sight(_player, candidate):
			continue
		_hit_ids[candidate.get_instance_id()] = true
		Targeting.hit(candidate, _damage(), 0 if _attack == null else _attack.armor_break)
		attack_hit.emit(candidate)


func _damage() -> int:
	var multiplier := 1.0 if _attack == null else _attack.damage_multiplier
	if _weapon == null:
		return maxi(1, roundi(multiplier))
	return maxi(1, roundi(float(BuildRunService.get_effective_damage(_weapon)) * multiplier))


func _update_aim(force: bool = false) -> void:
	if not force and (state == State.WINDUP or state == State.ACTIVE or state == State.RECOVERY):
		return
	var point: Vector2 = test_aim_point if test_aim_point != null else get_global_mouse_position()
	var offset := point - _player.global_position
	if offset.length() > 4.0:
		aim_direction = offset.normalized()


func _player_alive() -> bool:
	return _player != null and (not "hp" in _player or _player.hp > 0)


func _clear_buffer() -> void:
	_buffered_action = &""
	_buffer_left = 0.0


func _arc_color() -> Color:
	match state:
		State.WINDUP:
			return Color(1.0, 0.9, 0.4, 0.28)
		State.CHARGE:
			return Color(0.45, 0.75, 1.0, 0.28)
		State.ACTIVE:
			return Color(1.0, 0.55, 0.2, 0.5)
		State.RECOVERY:
			return Color(0.7, 0.7, 0.7, 0.18)
		_:
			return Color(0, 0, 0, 0)


func _update_visuals() -> void:
	_aim_line.points = PackedVector2Array([aim_direction * 18.0, aim_direction * 40.0])
	_aim_line.visible = state != State.DEAD
	if state == State.ACTIVE:
		_visual_circles = _hit_samples.duplicate(true)
	elif state == State.CHARGE and _charged != null:
		_visual_circles = Volume.samples_between(_charged, _player.global_position, _player.global_position, aim_direction, 0.0, 1.0)
	elif is_attacking() and _attack != null:
		var preview_t := 0.0 if state == State.WINDUP else 1.0
		_visual_circles = Volume.samples_between(
			_attack, _player.global_position, _player.global_position, aim_direction, preview_t, preview_t
		)
	else:
		_visual_circles = []


func _refresh_auto_label() -> void:
	_auto_label.visible = SettingsStore.is_auto_attack_enabled()
