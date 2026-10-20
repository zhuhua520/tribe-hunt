extends CharacterBody2D
## 野狼占位。在活动范围内巡逻、察觉、追击，并做一次有前摇的撕咬。
## 玩家离开活动范围后返回巢穴，不无限追击。同一撕咬实例只结算一次。
## 身体是调试形状，不是 A3 正式图。时长和距离都是测试值。

signal defeated

const LootTable := preload("res://scripts/loot/loot_table.gd")

const Volume := preload("res://scripts/combat/melee_attack_volume.gd")
const Targeting := preload("res://scripts/combat/combat_targeting.gd")

enum State { PATROL, ALERT, CHASE, WINDUP, ACTIVE, RECOVERY, RETURN, HURT, DEAD }

@export var max_hp: int = 4
@export var move_speed: float = 150.0
@export var notice_radius: float = 150.0
@export var activity_radius: float = 240.0
@export var patrol_radius: float = 64.0
@export var bite_range: float = 40.0
@export var bite_damage: int = 1
@export var windup_seconds: float = 0.28
@export var active_seconds: float = 0.10
@export var recovery_seconds: float = 0.36
@export var hurt_seconds: float = 0.16
@export var alert_seconds: float = 0.22
@export var bite_offset: float = 30.0
@export var bite_radius: float = 18.0
@export var loot_table_id: String = ""
@export var loot_seed: int = 0

var hp: int
var state: int = State.PATROL
## 测试用：非空时每帧沿该速度移动，不跑行为。
var debug_velocity: Variant = null

var _home: Vector2 = Vector2.ZERO
var _player: Node2D
var _aim: Vector2 = Vector2.RIGHT
var _state_left: float = 0.0
var _patrol_target: Vector2 = Vector2.ZERO
var _attack: MeleeAttackDefinition
var _hit_done: bool = false
var _defeat_sent: bool = false
var _prev_origin: Vector2 = Vector2.ZERO
var _hit_samples: Array = []
var _visual: Array = []

@onready var _visual_root: Node2D = $Visual


func _ready() -> void:
	add_to_group("enemies")
	hp = max_hp
	_home = global_position
	_patrol_target = _home
	_attack = _make_bite()
	_resolve_player()
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if debug_velocity is Vector2:
		velocity = debug_velocity
		_aim = velocity.normalized() if velocity.length_squared() > 0.01 else _aim
		move_and_slide()
		_face()
		return
	_resolve_player()
	var previous_left := _state_left
	if state != State.PATROL and state != State.DEAD:
		_state_left -= delta
	match state:
		State.PATROL:
			_tick_patrol()
		State.ALERT:
			velocity = Vector2.ZERO
			_face_player()
			if _state_left <= 0.0:
				_enter(State.CHASE, 0.0)
		State.CHASE:
			_tick_chase()
		State.WINDUP:
			velocity = Vector2.ZERO
			if _state_left <= 0.0:
				_begin_active()
		State.ACTIVE:
			velocity = Vector2.ZERO
			_advance_active(previous_left)
			if _state_left <= 0.0:
				_enter(State.RECOVERY, recovery_seconds)
		State.RECOVERY:
			velocity = Vector2.ZERO
			if _state_left <= 0.0:
				_enter(State.CHASE, 0.0)
		State.RETURN:
			_tick_return()
		State.HURT:
			velocity = Vector2.ZERO
			if _state_left <= 0.0:
				_enter(State.CHASE if _player_in_territory() else State.RETURN, 0.0)
	_face()
	_update_visuals()
	queue_redraw()


func home_position() -> Vector2:
	return _home


func is_chasing() -> bool:
	return state == State.ALERT or state == State.CHASE or state == State.WINDUP \
		or state == State.ACTIVE or state == State.RECOVERY


func take_damage(amount: int) -> void:
	if amount <= 0 or hp <= 0 or state == State.DEAD:
		return
	hp = maxi(0, hp - amount)
	print("Wolf HP: ", hp, "/", max_hp)
	if hp <= 0:
		_die()
		return
	_hit_samples.clear()
	_enter(State.HURT, hurt_seconds)


func _die() -> void:
	state = State.DEAD
	hp = 0
	velocity = Vector2.ZERO
	_hit_samples.clear()
	if not _defeat_sent:
		_defeat_sent = true
		print("Wolf defeated")
		defeated.emit()
	if loot_table_id != "":
		LootTable.release_once(self, loot_table_id, loot_seed, false)
	queue_free()


func _tick_patrol() -> void:
	if _player_in_territory() and _can_notice():
		_enter(State.ALERT, alert_seconds)
		return
	if global_position.distance_to(_patrol_target) < 8.0:
		_patrol_target = _home + Vector2.from_angle(randf() * TAU) * randf_range(12.0, patrol_radius)
	_move_toward(_patrol_target)


func _tick_chase() -> void:
	if not _player_in_territory():
		_enter(State.RETURN, 0.0)
		return
	_face_player()
	var distance := global_position.distance_to(_player.global_position)
	if distance <= bite_range:
		_start_bite()
		return
	_move_toward(_player.global_position)


func _tick_return() -> void:
	if _player_in_territory() and _can_notice():
		_enter(State.ALERT, alert_seconds)
		return
	if global_position.distance_to(_home) <= 12.0:
		_enter(State.PATROL, 0.0)
		return
	_move_toward(_home)


func _start_bite() -> void:
	_face_player()
	_hit_done = false
	_hit_samples.clear()
	_enter(State.WINDUP, windup_seconds)


func _begin_active() -> void:
	_prev_origin = global_position
	_hit_samples = Volume.samples_between(_attack, _prev_origin, _prev_origin, _aim, 0.0, 0.0)
	_enter(State.ACTIVE, active_seconds)
	_resolve_bite()


func _advance_active(previous_left: float) -> void:
	var duration := maxf(0.01, active_seconds)
	var previous_t := clampf(1.0 - previous_left / duration, 0.0, 1.0)
	var next_t := clampf(1.0 - maxf(_state_left, 0.0) / duration, previous_t, 1.0)
	var origin := global_position
	_hit_samples = Volume.samples_between(_attack, _prev_origin, origin, _aim, previous_t, next_t)
	_resolve_bite()
	_prev_origin = origin


func _resolve_bite() -> void:
	if _hit_done or _player == null or not is_instance_valid(_player):
		return
	if not _player.has_method("take_damage") or not ("hp" in _player) or _player.hp <= 0:
		return
	var radius := Volume.body_radius(_player)
	if not Volume.overlaps(_hit_samples, _player.global_position, radius):
		return
	if not Targeting.has_line_of_sight(self, _player):
		return
	_hit_done = true
	_player.take_damage(bite_damage)


func _player_in_territory() -> bool:
	return _player != null and is_instance_valid(_player) \
		and global_position.distance_to(_home) <= activity_radius \
		and _player.global_position.distance_to(_home) <= activity_radius


func _can_notice() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	if global_position.distance_to(_player.global_position) > notice_radius:
		return false
	return Targeting.has_line_of_sight(self, _player)


func _move_toward(point: Vector2) -> void:
	var offset := point - global_position
	if offset.length() <= 8.0:
		velocity = Vector2.ZERO
		return
	_aim = offset.normalized()
	velocity = _aim * move_speed
	move_and_slide()


func _face_player() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var offset := _player.global_position - global_position
	if offset.length() > 4.0:
		_aim = offset.normalized()


func _face() -> void:
	_visual_root.rotation = _aim.angle()


func _resolve_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	_player = get_tree().get_first_node_in_group("player") as Node2D


func _enter(next_state: int, seconds: float) -> void:
	state = next_state
	_state_left = seconds
	if next_state == State.PATROL:
		_patrol_target = global_position
	if next_state != State.ACTIVE and next_state != State.WINDUP:
		if next_state != State.RECOVERY:
			_hit_samples.clear()


func _make_bite() -> MeleeAttackDefinition:
	var start := MeleeHitKeyframe.new()
	start.time = 0.0
	start.offset = Vector2(bite_offset, -12.0)
	start.radius = bite_radius
	var ending := MeleeHitKeyframe.new()
	ending.time = 1.0
	ending.offset = Vector2(bite_offset, 12.0)
	ending.radius = bite_radius
	var attack := MeleeAttackDefinition.new()
	attack.attack_id = "wolf_bite"
	attack.windup_seconds = windup_seconds
	attack.active_seconds = active_seconds
	attack.recovery_seconds = recovery_seconds
	attack.keyframes = [start, ending]
	return attack


func _update_visuals() -> void:
	if state == State.ACTIVE:
		_visual = _hit_samples.duplicate(true)
	elif state == State.WINDUP or state == State.RECOVERY:
		var preview_t := 0.0 if state == State.WINDUP else 1.0
		_visual = Volume.samples_between(_attack, global_position, global_position, _aim, preview_t, preview_t)
	elif state == State.ALERT or state == State.CHASE:
		_visual = Volume.samples_between(_attack, global_position, global_position, _aim, 0.0, 0.0)
	else:
		_visual = []


func _draw() -> void:
	var color := Color(1.0, 0.85, 0.3, 0.35)
	if state == State.ACTIVE:
		color = Color(1.0, 0.45, 0.2, 0.55)
	elif state == State.RECOVERY:
		color = Color(0.7, 0.7, 0.7, 0.25)
	for circle in _visual:
		draw_circle(to_local(circle.center), float(circle.radius), color)
	draw_arc(to_local(_home), activity_radius, 0.0, TAU, 48, Color(0.55, 0.7, 0.85, 0.25), 1.0)
