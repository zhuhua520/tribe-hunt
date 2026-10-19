extends Node2D
## 玩家手动动作（S4 原型；D1 = 鼠标指向瞄准，左键攻击，空格闪避）。挂在 Player 下。
## 一次近战攻击：前摇 → 生效 → 后摇；闪避；受击硬直；单格输入缓冲。闪避不消耗耐力。
## 前摇与生效不可取消；后摇可被闪避取消。缓冲只保留最近一次按键，超时或暂停时丢弃。
## 所有时长、距离、速度都是可调测试值，不是最终手感。画面暂用调试扇形，等 A2 动作图集。

signal attack_started(direction: Vector2)
signal attack_hit(target: Node)
signal dodge_started(direction: Vector2)

enum State { IDLE, WINDUP, ACTIVE, RECOVERY, DODGE, HURT, DEAD }

const SettingsStore := preload("res://scripts/save/settings_store.gd")
const Targeting := preload("res://scripts/combat/combat_targeting.gd")
const ARC_SEGMENTS := 10

@export var windup_seconds: float = 0.12
@export var active_seconds: float = 0.08
@export var recovery_seconds: float = 0.22
@export var attack_radius: float = 76.0
@export var attack_arc_degrees: float = 110.0
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

var _state_left: float = 0.0
var _invulnerable_left: float = 0.0
var _dodge_cooldown_left: float = 0.0
var _dodge_direction: Vector2 = Vector2.RIGHT
var _buffered_action: StringName = &""
var _buffer_left: float = 0.0
var _hit_ids: Dictionary = {}
var _move_input: Vector2 = Vector2.ZERO

@onready var _player: CharacterBody2D = get_parent()
@onready var _arc: Polygon2D = $AttackArc
@onready var _aim_line: Line2D = $AimLine
@onready var _auto_label: Label = $AutoLabel


func _ready() -> void:
	_build_arc()
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
	if state != State.IDLE and state != State.DEAD:
		_state_left -= delta
		match state:
			State.WINDUP:
				if _state_left <= 0.0:
					_enter(State.ACTIVE, active_seconds)
			State.ACTIVE:
				_apply_hits()
				if _state_left <= 0.0:
					_enter(State.RECOVERY, recovery_seconds)
			_:
				if _state_left <= 0.0:
					_enter(State.IDLE, 0.0)
	_try_consume_buffer()
	_update_visuals()


## 记录一次动作请求；能立即执行就执行，否则留在单格缓冲里等待可执行时机。
func request(action: StringName) -> void:
	if state == State.DEAD or not _player_alive():
		return
	_buffered_action = action
	_buffer_left = buffer_seconds
	_try_consume_buffer()


## Player 每个物理帧调用，用当前动作状态决定实际速度。
func movement_velocity(input_vector: Vector2, move_speed: float) -> Vector2:
	_move_input = input_vector
	match state:
		State.DODGE:
			return _dodge_direction * dodge_speed
		State.WINDUP, State.ACTIVE, State.RECOVERY:
			return input_vector * move_speed * attack_move_scale
		State.HURT, State.DEAD:
			return Vector2.ZERO
	return input_vector * move_speed


func is_invulnerable() -> bool:
	return _invulnerable_left > 0.0


func is_attacking() -> bool:
	return state == State.WINDUP or state == State.ACTIVE or state == State.RECOVERY


func has_buffered_action() -> bool:
	return _buffered_action != &""


func on_hurt() -> void:
	if state == State.DEAD:
		return
	_clear_buffer()
	_enter(State.HURT, hurt_stun_seconds)


func on_defeated() -> void:
	_clear_buffer()
	_invulnerable_left = 0.0
	_enter(State.DEAD, 0.0)


func _try_consume_buffer() -> void:
	if _buffered_action == &"" or not _player_alive():
		return
	if _buffered_action == &"attack" and state == State.IDLE:
		_clear_buffer()
		_start_attack()
	elif _buffered_action == &"dodge" and (state == State.IDLE or state == State.RECOVERY) and _dodge_cooldown_left <= 0.0:
		_clear_buffer()
		_start_dodge()


func _start_attack() -> void:
	_update_aim()
	_hit_ids.clear()
	attack_count += 1
	_enter(State.WINDUP, windup_seconds)
	attack_started.emit(aim_direction)


func _start_dodge() -> void:
	_dodge_direction = _move_input.normalized() if _move_input.length_squared() > 0.01 else aim_direction
	dodge_count += 1
	_invulnerable_left = dodge_invulnerable_seconds
	_dodge_cooldown_left = dodge_seconds + dodge_cooldown_seconds
	_enter(State.DODGE, dodge_seconds)
	dodge_started.emit(_dodge_direction)


func _enter(next_state: int, seconds: float) -> void:
	state = next_state
	_state_left = seconds
	if next_state == State.ACTIVE:
		_apply_hits()


func _apply_hits() -> void:
	var origin := _player.global_position
	var half_arc := deg_to_rad(attack_arc_degrees) * 0.5
	for candidate in get_tree().get_nodes_in_group("enemies"):
		if _hit_ids.has(candidate.get_instance_id()) or not Targeting.is_live_target(candidate):
			continue
		var offset: Vector2 = candidate.global_position - origin
		if offset.length() > attack_radius:
			continue
		if offset.length() > 0.001 and absf(aim_direction.angle_to(offset)) > half_arc:
			continue
		if not Targeting.has_line_of_sight(_player, candidate):
			continue
		_hit_ids[candidate.get_instance_id()] = true
		Targeting.hit(candidate, _damage())
		attack_hit.emit(candidate)


func _damage() -> int:
	var melee := _player.get_node_or_null("MeleeWeapon")
	if melee != null and melee.definition != null:
		return BuildRunService.get_effective_damage(melee.definition)
	return 1


func _update_aim() -> void:
	if is_attacking():
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


func _build_arc() -> void:
	var points := PackedVector2Array([Vector2.ZERO])
	var half_arc := deg_to_rad(attack_arc_degrees) * 0.5
	for i in ARC_SEGMENTS + 1:
		var angle := -half_arc + half_arc * 2.0 * float(i) / float(ARC_SEGMENTS)
		points.append(Vector2.RIGHT.rotated(angle) * attack_radius)
	_arc.polygon = points


func _update_visuals() -> void:
	_aim_line.points = PackedVector2Array([aim_direction * 18.0, aim_direction * 40.0])
	_aim_line.visible = state != State.DEAD
	_arc.rotation = aim_direction.angle()
	_arc.visible = is_attacking()
	match state:
		State.WINDUP:
			_arc.color = Color(1.0, 0.9, 0.4, 0.18)
		State.ACTIVE:
			_arc.color = Color(1.0, 0.55, 0.2, 0.55)
		State.RECOVERY:
			_arc.color = Color(0.7, 0.7, 0.7, 0.12)


func _refresh_auto_label() -> void:
	_auto_label.visible = SettingsStore.is_auto_attack_enabled()
