extends CharacterBody2D
## 狼王。预警开始时锁定方向，沿这条线扑出去；扑空后有一段不能改向的恢复。
## 不是野狼换色加血。轮廓和扑击轨迹是几何占位。

signal defeated

const LootTable := preload("res://scripts/loot/loot_table.gd")
const Targeting := preload("res://scripts/combat/combat_targeting.gd")
const ContextScript := preload("res://scripts/combat/hit_context.gd")

enum State { HOLD, WINDUP, POUNCE, RECOVERY, HURT, DEAD }

@export var max_hp: int = 10
@export var move_speed: float = 90.0
@export var notice_radius: float = 200.0
@export var activity_radius: float = 160.0
@export var pounce_range: float = 150.0
@export var pounce_damage: int = 2
@export var pounce_speed: float = 280.0
@export var pounce_seconds: float = 0.28
@export var windup_seconds: float = 0.35
@export var recovery_seconds: float = 0.7
@export var hit_radius: float = 26.0
@export var hurt_seconds: float = 0.12
@export var loot_table_id: String = ""
@export var loot_seed: int = 0

var hp: int
var state: int = State.HOLD
## 测试用：非空时每帧沿该速度移动，不扑击。
var debug_velocity: Variant = null

var _home: Vector2 = Vector2.ZERO
var _player: Node2D
var _aim: Vector2 = Vector2.LEFT
var _state_left: float = 0.0
var _hit_done: bool = false
var _attack_id: int = 0
var _defeat_sent: bool = false
var _trail_from: Vector2 = Vector2.ZERO

@onready var _visual_root: Node2D = $Visual


func _ready() -> void:
	add_to_group("enemies")
	hp = max_hp
	_home = global_position
	_trail_from = global_position
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
				_begin_pounce()
		State.POUNCE:
			velocity = _aim * pounce_speed
			move_and_slide()
			_try_hit()
			if _state_left <= 0.0:
				_finish_pounce()
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
	print("Wolf king HP: ", hp, "/", max_hp)
	if hp <= 0:
		_die()
		return
	if state != State.POUNCE:
		_enter(State.HURT, hurt_seconds)


func _tick_hold() -> void:
	if not _player_in_territory() or not _can_notice():
		if global_position.distance_to(_home) > 12.0:
			_move_toward(_home)
		else:
			velocity = Vector2.ZERO
		return
	var distance := global_position.distance_to(_player.global_position)
	if distance > pounce_range:
		if global_position.distance_to(_home) < activity_radius - 8.0:
			_move_toward(_player.global_position)
		else:
			velocity = Vector2.ZERO
		return
	velocity = Vector2.ZERO
	_enter(State.WINDUP, windup_seconds)


func _begin_pounce() -> void:
	_hit_done = false
	_trail_from = global_position
	_attack_id = Targeting.begin_attack()
	_enter(State.POUNCE, pounce_seconds)


func _finish_pounce() -> void:
	if _attack_id > 0:
		Targeting.close_attack(_attack_id)
		_attack_id = 0
	_enter(State.RECOVERY, recovery_seconds)


func _try_hit() -> void:
	if _hit_done or _player == null or not is_instance_valid(_player):
		return
	if not ("hp" in _player) or _player.hp <= 0:
		return
	if global_position.distance_to(_player.global_position) > hit_radius + 18.0:
		return
	if not Targeting.has_line_of_sight(self, _player):
		return
	_hit_done = true
	var context = ContextScript.new()
	context.attack_instance_id = _attack_id
	context.source = self
	context.snapshot_id = "wolf_king"
	context.target = _player
	context.base_damage = pounce_damage
	context.snapshot_damage = pounce_damage
	context.origin_effect_id = "enemy_pounce"
	Targeting.resolve(context)


func _die() -> void:
	state = State.DEAD
	hp = 0
	velocity = Vector2.ZERO
	if _attack_id > 0:
		Targeting.close_attack(_attack_id)
		_attack_id = 0
	if not _defeat_sent:
		_defeat_sent = true
		print("Wolf king defeated")
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


func _face() -> void:
	_visual_root.rotation = _aim.angle()


func _resolve_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	_player = get_tree().get_first_node_in_group("player") as Node2D


func _enter(next_state: int, seconds: float) -> void:
	if next_state == State.WINDUP and _player != null and is_instance_valid(_player):
		var offset := _player.global_position - global_position
		if offset.length() > 4.0:
			_aim = offset.normalized()
	state = next_state
	_state_left = seconds


func _draw() -> void:
	if state == State.WINDUP or state == State.POUNCE:
		draw_line(Vector2.ZERO, _aim * 72.0, Color(0.85, 0.2, 0.15, 0.85), 3.0)
	if state == State.POUNCE:
		draw_line(to_local(_trail_from), Vector2.ZERO, Color(0.9, 0.35, 0.2, 0.55), 4.0)
	draw_arc(to_local(_home), activity_radius, 0.0, TAU, 40, Color(0.55, 0.3, 0.25, 0.25), 1.0)
