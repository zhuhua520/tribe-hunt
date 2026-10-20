extends CharacterBody2D
const PreviewArt := preload("res://scripts/systems/borrowed_preview_art.gd")
const Targeting := preload("res://scripts/combat/combat_targeting.gd")
## 野猪王最小遭遇。追近、锁向冲撞和圆形震地都是临时原型值。
## 冲刺沿锁定方向平移，撞到实心地形就停，不穿墙。

signal defeated

# 临时原型值：只为看清预警和走位，不代表最终数值。
const CHASE_SPEED := 78.0
const CHASE_SECONDS := 1.05
const CHARGE_WINDUP_SECONDS := 0.75
const CHARGE_LOCK_SECONDS := 0.45
const CHARGE_DASH_SPEED := 480.0
const CHARGE_DASH_SECONDS := 0.42
const CHARGE_RECOVER_SECONDS := 0.7
const CHARGE_DAMAGE := 2
const CHARGE_HIT_RADIUS := 50.0
const CHARGE_LANE_LENGTH := 202.0
const CHARGE_LANE_HALF_WIDTH := 50.0
const SLAM_WINDUP_SECONDS := 1.0
const SLAM_RADIUS := 118.0
const SLAM_DAMAGE := 2
const SLAM_RECOVER_SECONDS := 0.75
const BODY_RADIUS := 36.0

@export var max_hp: int = 14
@export var arena_half_size: Vector2 = Vector2(480, 270)

var hp: int
var action_name: String = "chase"
var locked_direction: Vector2 = Vector2.RIGHT
var dash_direction: Vector2 = Vector2.RIGHT

var _player: Node2D
var _action_time: float = 0.0
var _next_attack: String = "charge"
var _charge_connected: bool = false
var _hurt_flash: float = 0.0
var _defeated_emitted: bool = false

var _footprint: Polygon2D
var _charge_lane: Polygon2D
var _charge_line: Line2D
var _slam_ring: Polygon2D
var _body_sprite: Sprite2D
var _hp_label: Label


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("boar_king")
	hp = max_hp
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 2 | 8
	collision_mask = 1
	_build_placeholder_visuals()
	_resolve_player()
	var stats := get_tree().get_first_node_in_group("run_stats")
	if stats != null and stats.has_method("watch_enemy"):
		stats.watch_enemy(self)
	if stats != null and stats.has_method("note_boar_started"):
		stats.note_boar_started()
	_update_hp_label()
	print("Boar king ready hp=", hp)


func _physics_process(delta: float) -> void:
	if hp <= 0 or _player_is_defeated():
		velocity = Vector2.ZERO
		_hide_attack_markers()
		return
	_action_time += delta
	_update_hurt_flash(delta)
	match action_name:
		"chase":
			_tick_chase()
		"charge_windup":
			_tick_charge_windup()
		"charge_lock":
			_tick_charge_lock()
		"charge_dash":
			_tick_charge_dash(delta)
		"charge_recover":
			_tick_charge_recover()
		"slam_windup":
			_tick_slam_windup()
		"slam_recover":
			_tick_slam_recover()
		_:
			_begin_chase()
	_update_body_facing()
	global_position = global_position.clamp(-arena_half_size + Vector2(48, 48), arena_half_size - Vector2(48, 48))
	_update_hp_label()


func take_damage(amount: int) -> void:
	if amount <= 0 or hp <= 0:
		return
	hp = maxi(0, hp - amount)
	_hurt_flash = 0.12
	print("Boar king HP: ", hp, "/", max_hp)
	if hp <= 0:
		_defeat()


func _tick_chase() -> void:
	_hide_attack_markers()
	collision_mask = 1
	_resolve_player()
	if _player == null:
		velocity = Vector2.ZERO
		move_and_slide()
	else:
		var to_player := _player.global_position - global_position
		if to_player.length_squared() > 4.0:
			velocity = to_player.normalized() * CHASE_SPEED
		else:
			velocity = Vector2.ZERO
		move_and_slide()
	if _action_time >= CHASE_SECONDS:
		if _next_attack == "slam":
			_begin_slam_windup()
		else:
			_begin_charge_windup()


func _begin_charge_windup() -> void:
	action_name = "charge_windup"
	_action_time = 0.0
	velocity = Vector2.ZERO
	print("Boar charge windup")


func _tick_charge_windup() -> void:
	velocity = Vector2.ZERO
	collision_mask = 1
	move_and_slide()
	var aim := _aim_direction()
	_show_charge(aim, false)
	if _action_time >= CHARGE_WINDUP_SECONDS:
		locked_direction = aim
		action_name = "charge_lock"
		_action_time = 0.0
		print("Boar charge lock dir=%.3f,%.3f" % [locked_direction.x, locked_direction.y])


func _tick_charge_lock() -> void:
	velocity = Vector2.ZERO
	collision_mask = 1
	move_and_slide()
	_show_charge(locked_direction, true)
	if _action_time >= CHARGE_LOCK_SECONDS:
		dash_direction = locked_direction
		_charge_connected = false
		collision_mask = 0
		action_name = "charge_dash"
		_action_time = 0.0
		print("Boar charge dash dir=%.3f,%.3f" % [dash_direction.x, dash_direction.y])


func _tick_charge_dash(delta: float) -> void:
	# 冲刺只用锁定方向平移，不读取玩家位置。遇到实心地形就停，不穿墙。
	var desired := global_position + dash_direction * CHARGE_DASH_SPEED * delta
	var blocked := _terrain_stop(global_position, desired)
	if blocked != Vector2.INF:
		global_position = blocked
		velocity = Vector2.ZERO
		_show_charge(dash_direction, true)
		_try_charge_hit()
		_end_charge_dash("Boar charge blocked")
		return
	global_position = desired
	velocity = Vector2.ZERO
	_show_charge(dash_direction, true)
	_try_charge_hit()
	if _action_time >= CHARGE_DASH_SECONDS:
		if not _charge_connected:
			print("Boar charge missed")
		_end_charge_dash("")


func _tick_charge_recover() -> void:
	_hide_attack_markers()
	velocity = Vector2.ZERO
	collision_mask = 1
	move_and_slide()
	if _action_time >= CHARGE_RECOVER_SECONDS:
		_next_attack = "slam"
		_begin_chase()


func _begin_slam_windup() -> void:
	action_name = "slam_windup"
	_action_time = 0.0
	velocity = Vector2.ZERO
	print("Boar slam windup radius=", SLAM_RADIUS)


func _tick_slam_windup() -> void:
	velocity = Vector2.ZERO
	collision_mask = 1
	move_and_slide()
	_show_slam(false)
	if _action_time >= SLAM_WINDUP_SECONDS:
		_resolve_slam()
		action_name = "slam_recover"
		_action_time = 0.0
		print("Boar slam recover")


func _tick_slam_recover() -> void:
	_hide_attack_markers()
	velocity = Vector2.ZERO
	collision_mask = 1
	move_and_slide()
	if _action_time >= SLAM_RECOVER_SECONDS:
		_next_attack = "charge"
		_begin_chase()


func _end_charge_dash(reason: String) -> void:
	if reason != "":
		print(reason)
	collision_mask = 1
	action_name = "charge_recover"
	_action_time = 0.0
	print("Boar charge recover")


func _terrain_stop(from: Vector2, to: Vector2) -> Vector2:
	var world := get_world_2d()
	if world == null:
		return Vector2.INF
	var query := PhysicsRayQueryParameters2D.create(from, to, Targeting.TERRAIN_LAYER)
	query.exclude = [get_rid()]
	var result := world.direct_space_state.intersect_ray(query)
	if result.is_empty():
		return Vector2.INF
	var hit: Vector2 = result.position
	if dash_direction.length_squared() > 0.0001:
		hit -= dash_direction.normalized() * 8.0
	return hit


func _begin_chase() -> void:
	action_name = "chase"
	_action_time = 0.0
	_hide_attack_markers()


func _try_charge_hit() -> void:
	if _charge_connected or _player == null or not is_instance_valid(_player):
		return
	if global_position.distance_to(_player.global_position) > CHARGE_HIT_RADIUS:
		return
	_charge_connected = true
	print("Boar charge hit")
	if _player.has_method("take_damage"):
		_player.take_damage(CHARGE_DAMAGE)


func _resolve_slam() -> void:
	_show_slam(true)
	_resolve_player()
	if _player == null:
		print("Boar slam missed")
		return
	var dist := global_position.distance_to(_player.global_position)
	if dist <= SLAM_RADIUS:
		print("Boar slam hit dist=%.1f radius=%.1f" % [dist, SLAM_RADIUS])
		if _player.has_method("take_damage"):
			_player.take_damage(SLAM_DAMAGE)
	else:
		print("Boar slam missed dist=%.1f radius=%.1f" % [dist, SLAM_RADIUS])


func _aim_direction() -> Vector2:
	_resolve_player()
	if _player == null:
		if locked_direction.length_squared() > 0.0001:
			return locked_direction
		return Vector2.RIGHT
	var to_player := _player.global_position - global_position
	if to_player.length_squared() < 0.0001:
		return Vector2.RIGHT
	return to_player.normalized()


func _resolve_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	_player = get_tree().get_first_node_in_group("player") as Node2D


func _player_is_defeated() -> bool:
	_resolve_player()
	return _player != null and "hp" in _player and int(_player.hp) <= 0


func _defeat() -> void:
	if _defeated_emitted:
		return
	_defeated_emitted = true
	hp = 0
	velocity = Vector2.ZERO
	_hide_attack_markers()
	print("Boar king defeated")
	defeated.emit()
	queue_free()


func _build_placeholder_visuals() -> void:
	_footprint = _make_polygon(Color(0.45, 0.28, 0.12, 0.9), -4)
	_footprint.polygon = _circle_points(BODY_RADIUS, 24)
	_charge_lane = _make_polygon(Color(1, 0.45, 0.08, 0), -3)
	_slam_ring = _make_polygon(Color(0.98, 0.84, 0.16, 0), -3)
	_charge_line = Line2D.new()
	_charge_line.width = 6.0
	_charge_line.default_color = Color(1, 0.15, 0.05, 0)
	_charge_line.z_as_relative = false
	_charge_line.z_index = -2
	_charge_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_charge_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(_charge_line)

	_body_sprite = get_node_or_null("BodySprite") as Sprite2D
	if _body_sprite != null and _body_sprite.texture == null:
		_body_sprite.texture = PreviewArt.texture("boar_sheet.png")
	if _body_sprite != null:
		_body_sprite.hframes = 2
	_hp_label = get_node_or_null("HpLabel") as Label


func _update_body_facing() -> void:
	if _body_sprite == null:
		return
	var facing := velocity
	if action_name == "charge_lock":
		facing = locked_direction
	elif action_name == "charge_dash":
		facing = dash_direction
	elif _player != null and is_instance_valid(_player):
		facing = _player.global_position - global_position
	if facing.length_squared() > 0.001:
		_body_sprite.rotation = facing.angle() - PI
	_body_sprite.frame = int(_action_time * 4.0) % 2
func _make_polygon(color: Color, z: int) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.color = color
	poly.z_as_relative = false
	poly.z_index = z
	add_child(poly)
	return poly


func _show_charge(direction: Vector2, locked: bool) -> void:
	var dir := direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	var side := Vector2(-dir.y, dir.x) * CHARGE_LANE_HALF_WIDTH
	var tip := dir * CHARGE_LANE_LENGTH
	_charge_lane.polygon = PackedVector2Array([side * 0.35, tip + side, tip - side, -side * 0.35])
	if locked:
		_charge_lane.color = Color(0.95, 0.16, 0.05, 0.62)
		_charge_line.default_color = Color(1, 0.95, 0.85, 0.95)
	else:
		_charge_lane.color = Color(1, 0.52, 0.08, 0.42)
		_charge_line.default_color = Color(1, 0.95, 0.7, 0.9)
	_charge_line.points = PackedVector2Array([Vector2.ZERO, tip])
	_slam_ring.color.a = 0.0


func _show_slam(impact: bool) -> void:
	_slam_ring.polygon = _circle_points(SLAM_RADIUS, 32)
	if impact:
		_slam_ring.color = Color(1, 0.25, 0.12, 0.72)
	else:
		var pulse := 0.34 + 0.22 * absf(sin(_action_time * 9.0))
		_slam_ring.color = Color(0.98, 0.86, 0.18, pulse)
	_charge_lane.color.a = 0.0
	_charge_line.default_color.a = 0.0


func _hide_attack_markers() -> void:
	if _charge_lane != null:
		_charge_lane.color.a = 0.0
	if _charge_line != null:
		_charge_line.default_color.a = 0.0
	if _slam_ring != null:
		_slam_ring.color.a = 0.0


func _circle_points(radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in segments:
		var angle := TAU * float(i) / float(segments)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


func _update_hurt_flash(delta: float) -> void:
	if _body_sprite == null:
		return
	if _hurt_flash > 0.0:
		_hurt_flash = maxf(0.0, _hurt_flash - delta)
		_body_sprite.modulate = Color(1.0, 0.72, 0.72, 1.0)
	else:
		_body_sprite.modulate = Color(0.88, 0.64, 0.46, 1.0)


func _update_hp_label() -> void:
	if _hp_label == null:
		return
	_hp_label.text = "野猪王 %d/%d" % [hp, max_hp]
