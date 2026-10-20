extends CharacterBody2D
## 驻守机械。在活动范围内保持距离，预警后沿锁定方向射直线弹。
## 不追出范围，不隔墙开火。弹只打玩家，不打自己或其他敌人。

signal defeated

const LootTable := preload("res://scripts/loot/loot_table.gd")
const Targeting := preload("res://scripts/combat/combat_targeting.gd")
const BOLT_SCENE := preload("res://scenes/weapons/stone_projectile.tscn")

enum State { HOLD, WINDUP, RECOVERY, HURT, DEAD }

@export var max_hp: int = 6
@export var move_speed: float = 70.0
@export var notice_radius: float = 220.0
@export var activity_radius: float = 180.0
@export var preferred_range: float = 140.0
@export var shot_damage: int = 1
@export var shot_speed: float = 240.0
@export var shot_lifetime: float = 1.2
@export var windup_seconds: float = 0.4
@export var recovery_seconds: float = 0.9
@export var hurt_seconds: float = 0.16
@export var loot_table_id: String = ""
@export var loot_seed: int = 0

var hp: int
var state: int = State.HOLD
## 测试用：非空时每帧沿该速度移动，不跑射击。
var debug_velocity: Variant = null

var _home: Vector2 = Vector2.ZERO
var _player: Node2D
var _aim: Vector2 = Vector2.LEFT
var _state_left: float = 0.0
var _defeat_sent: bool = false

@onready var _visual_root: Node2D = $Visual


func _ready() -> void:
	add_to_group("enemies")
	hp = max_hp
	_home = global_position
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_resolve_player()


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if debug_velocity is Vector2:
		velocity = debug_velocity
		move_and_slide()
		_face()
		queue_redraw()
		return
	_resolve_player()
	if state != State.HOLD and state != State.DEAD:
		_state_left -= delta
	match state:
		State.HOLD:
			_tick_hold()
		State.WINDUP:
			velocity = Vector2.ZERO
			if _state_left <= 0.0:
				_fire()
				_enter(State.RECOVERY, recovery_seconds)
		State.RECOVERY:
			velocity = Vector2.ZERO
			if _state_left <= 0.0:
				_enter(State.HOLD, 0.0)
		State.HURT:
			velocity = Vector2.ZERO
			if _state_left <= 0.0:
				_enter(State.HOLD, 0.0)
	_face()
	queue_redraw()


func home_position() -> Vector2:
	return _home


func take_damage(amount: int) -> void:
	if amount <= 0 or hp <= 0 or state == State.DEAD:
		return
	hp = maxi(0, hp - amount)
	print("Sentry HP: ", hp, "/", max_hp)
	if hp <= 0:
		_die()
		return
	_enter(State.HURT, hurt_seconds)


func _tick_hold() -> void:
	if not _player_in_territory() or not _can_notice():
		if global_position.distance_to(_home) > 12.0:
			_move_toward(_home)
		else:
			velocity = Vector2.ZERO
		return
	_face_player()
	var distance := global_position.distance_to(_player.global_position)
	if distance < preferred_range - 12.0:
		var away := global_position - _player.global_position
		if away.length_squared() < 0.01:
			away = Vector2.LEFT
		var retreat := global_position + away.normalized() * 36.0
		if retreat.distance_to(_home) <= activity_radius:
			_move_toward(retreat)
		else:
			velocity = Vector2.ZERO
		return
	if distance > preferred_range + 24.0 and global_position.distance_to(_home) < activity_radius - 8.0:
		_move_toward(_player.global_position)
		return
	velocity = Vector2.ZERO
	_enter(State.WINDUP, windup_seconds)


func _fire() -> void:
	if hp <= 0 or state == State.DEAD or not _can_notice():
		return
	var parent := get_parent()
	if parent == null:
		return
	var bolt = BOLT_SCENE.instantiate()
	parent.add_child(bolt)
	bolt.global_position = global_position + _aim * 18.0
	bolt.speed = shot_speed
	bolt.lifetime = shot_lifetime
	bolt.armor_break = 0
	bolt.max_hits = 1
	bolt.source = self
	bolt.snapshot_id = "sentry"
	bolt.origin_effect_id = "enemy_shot"
	bolt.victim_group = &"player"
	bolt.path_mask = 1 | Targeting.TERRAIN_LAYER
	bolt.collision_mask = 1 | Targeting.TERRAIN_LAYER
	bolt.setup(_aim, shot_damage)


func _die() -> void:
	state = State.DEAD
	hp = 0
	velocity = Vector2.ZERO
	if not _defeat_sent:
		_defeat_sent = true
		print("Sentry defeated")
		defeated.emit()
	if loot_table_id != "":
		LootTable.release_once(self, loot_table_id, loot_seed, false)
	queue_free()


func _player_in_territory() -> bool:
	return _player != null and is_instance_valid(_player) \
		and global_position.distance_to(_home) <= activity_radius \
		and _player.global_position.distance_to(_home) <= activity_radius


func _can_notice() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	if not ("hp" in _player) or _player.hp <= 0:
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
	if next_state == State.WINDUP:
		_face_player()
	state = next_state
	_state_left = seconds


func _draw() -> void:
	if state == State.WINDUP:
		draw_line(Vector2.ZERO, _aim * 56.0, Color(0.95, 0.45, 0.15, 0.9), 2.0)
	draw_arc(to_local(_home), activity_radius, 0.0, TAU, 40, Color(0.45, 0.55, 0.62, 0.25), 1.0)
