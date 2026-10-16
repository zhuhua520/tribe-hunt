extends Node
## 联机测试场的临时自动攻击。数值对齐现有单人木棍/弹弓，只在服务器结算。
## 不修改单人武器，也不代表最终自动/手动攻击方案。

const STONE_TEXTURE := preload("res://assets/sprites/projectiles/stone.png")

const CLUB_DAMAGE := 1
const CLUB_RANGE := 72.0
const CLUB_COOLDOWN := 0.45
const SLING_DAMAGE := 1
const SLING_RANGE := 320.0
const SLING_COOLDOWN := 0.85
const STONE_SPEED := 420.0
const STONE_LIFE := 2.0
const STONE_HIT_RADIUS := 18.0
const CONTACT_DAMAGE := 1
const CONTACT_RADIUS := 30.0

var _club_cooldown: Dictionary = {}
var _sling_cooldown: Dictionary = {}
var _stones: Array[Dictionary] = []
var _next_stone_id: int = 1
var _stones_root: Node2D


func _ready() -> void:
	_stones_root = get_parent().get_node("Stones") as Node2D


func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	if _match_ended():
		return
	_tick_auto_attacks(delta)
	_tick_stones(delta)
	_tick_contact()


func _match_ended() -> bool:
	var director := get_parent().get_node_or_null("WaveDirector")
	return director != null and str(director.phase) == "ended"


func _tick_auto_attacks(delta: float) -> void:
	for player in get_tree().get_nodes_in_group("net_players"):
		if player == null or not is_instance_valid(player) or player.hp <= 0:
			continue
		var peer_id := int(player.peer_id)
		_club_cooldown[peer_id] = maxf(0.0, float(_club_cooldown.get(peer_id, 0.0)) - delta)
		_sling_cooldown[peer_id] = maxf(0.0, float(_sling_cooldown.get(peer_id, 0.0)) - delta)
		var target := _nearest_living_enemy(player.global_position)
		if target == null:
			continue
		var distance: float = player.global_position.distance_to(target.global_position)
		if float(_club_cooldown[peer_id]) <= 0.0 and distance <= CLUB_RANGE:
			_club_cooldown[peer_id] = CLUB_COOLDOWN
			_damage_enemy(target, CLUB_DAMAGE)
			print("Net club hit")
		if float(_sling_cooldown[peer_id]) <= 0.0 and distance <= SLING_RANGE:
			_sling_cooldown[peer_id] = SLING_COOLDOWN
			var aim: Vector2 = target.global_position - player.global_position
			if aim.length_squared() < 0.0001:
				aim = Vector2.RIGHT
			_spawn_stone(player.global_position, aim.normalized())
			print("Net sling fired")


func _tick_stones(delta: float) -> void:
	var remaining: Array[Dictionary] = []
	for stone in _stones:
		var pos: Vector2 = stone["pos"]
		var direction: Vector2 = stone["dir"]
		pos += direction * STONE_SPEED * delta
		stone["pos"] = pos
		stone["life"] = float(stone["life"]) - delta
		var stone_id := int(stone["id"])
		_move_stone_visual(stone_id, pos)
		_sync_stone_position(stone_id, pos)
		var hit := _stone_hit_enemy(pos)
		if hit != null:
			_damage_enemy(hit, int(stone["damage"]))
			_remove_stone(stone_id)
			print("Net stone hit")
			continue
		if float(stone["life"]) <= 0.0:
			_remove_stone(stone_id)
			continue
		remaining.append(stone)
	_stones = remaining


func _tick_contact() -> void:
	for enemy in get_tree().get_nodes_in_group("net_enemies"):
		if enemy == null or not is_instance_valid(enemy) or enemy.hp <= 0:
			continue
		for player in get_tree().get_nodes_in_group("net_players"):
			if player == null or not is_instance_valid(player) or player.hp <= 0:
				continue
			if player.global_position.distance_to(enemy.global_position) > CONTACT_RADIUS:
				continue
			if player.has_method("server_receive_contact"):
				player.server_receive_contact(CONTACT_DAMAGE)


func _nearest_living_enemy(origin: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for enemy in get_tree().get_nodes_in_group("net_enemies"):
		if enemy == null or not is_instance_valid(enemy) or enemy.hp <= 0:
			continue
		var dist := origin.distance_squared_to(enemy.global_position)
		if dist < best_dist:
			best_dist = dist
			best = enemy
	return best


func _stone_hit_enemy(pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist := STONE_HIT_RADIUS * STONE_HIT_RADIUS
	for enemy in get_tree().get_nodes_in_group("net_enemies"):
		if enemy == null or not is_instance_valid(enemy) or enemy.hp <= 0:
			continue
		var dist := pos.distance_squared_to(enemy.global_position)
		if dist <= best_dist:
			best_dist = dist
			best = enemy
	return best


func _damage_enemy(enemy: Node, amount: int) -> void:
	if enemy == null or not enemy.has_method("apply_server_damage"):
		return
	var killed: bool = enemy.apply_server_damage(amount)
	if not killed:
		return
	var director := get_parent().get_node_or_null("WaveDirector")
	if director != null and director.has_method("confirm_enemy_killed"):
		director.confirm_enemy_killed(int(enemy.enemy_id))


func _spawn_stone(origin: Vector2, direction: Vector2) -> void:
	var stone_id := _next_stone_id
	_next_stone_id += 1
	_stones.append({
		"id": stone_id,
		"pos": origin,
		"dir": direction,
		"life": STONE_LIFE,
		"damage": SLING_DAMAGE,
	})
	_ensure_stone_visual(stone_id, origin)
	for peer_id in _ready_peers():
		rpc_spawn_stone.rpc_id(int(peer_id), stone_id, origin)


func _sync_stone_position(stone_id: int, pos: Vector2) -> void:
	for peer_id in _ready_peers():
		rpc_sync_stone.rpc_id(int(peer_id), stone_id, pos)


func _remove_stone(stone_id: int) -> void:
	var visual := _stones_root.get_node_or_null("s%d" % stone_id)
	if visual != null:
		visual.queue_free()
	for peer_id in _ready_peers():
		rpc_despawn_stone.rpc_id(int(peer_id), stone_id)


func _ready_peers() -> Array:
	var arena := get_parent()
	if arena != null and arena.has_method("get_replication_peer_ids"):
		return arena.get_replication_peer_ids()
	return []


func _ensure_stone_visual(stone_id: int, pos: Vector2) -> void:
	var node_name := "s%d" % stone_id
	if _stones_root.get_node_or_null(node_name) != null:
		return
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.texture = STONE_TEXTURE
	sprite.global_position = pos
	_stones_root.add_child(sprite)


func _move_stone_visual(stone_id: int, pos: Vector2) -> void:
	var visual := _stones_root.get_node_or_null("s%d" % stone_id) as Node2D
	if visual != null:
		visual.global_position = pos


@rpc("authority", "reliable")
func rpc_spawn_stone(stone_id: int, pos: Vector2) -> void:
	_ensure_stone_visual(stone_id, pos)


@rpc("authority", "unreliable")
func rpc_sync_stone(stone_id: int, pos: Vector2) -> void:
	if multiplayer.is_server():
		return
	_move_stone_visual(stone_id, pos)


@rpc("authority", "reliable")
func rpc_despawn_stone(stone_id: int) -> void:
	var visual := _stones_root.get_node_or_null("s%d" % stone_id)
	if visual != null:
		visual.queue_free()
