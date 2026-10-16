extends Node
## 服务器权威波次与敌人。客户端只接收生成、位置、生命和波次/胜负状态。

const NET_ENEMY_SCENE := preload("res://scenes/combat/net_enemy.tscn")

@export var arena_half_size: Vector2 = Vector2(480, 270)
@export var delay_before_first_wave: float = 0.8
@export var delay_between_waves: float = 1.2

var wave_index: int = -1
var wave_total: int = 0
var phase: String = "idle"
var status_text: String = "等待服务器波次"

var _waves: Array[WaveConfig] = []
var _to_spawn: int = 0
var _spawn_interval: float = 0.5
var _cooldown: float = 0.0
var _next_enemy_id: int = 1
var _enemies: Node2D


func _ready() -> void:
	_enemies = get_parent().get_node("Enemies") as Node2D
	_waves = [
		load("res://data/waves/wave_1.tres"),
		load("res://data/waves/wave_2.tres"),
		load("res://data/waves/wave_3.tres"),
	]
	wave_total = _waves.size()
	if multiplayer.is_server():
		phase = "between"
		_cooldown = delay_before_first_wave
		status_text = "狩猎即将开始…"
		call_deferred("_publish_state")


func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	if phase != "ended" and _all_connected_players_down():
		_declare_loss()
		_sync_positions()
		return
	if phase == "ended":
		_sync_positions()
		return

	match phase:
		"between":
			_cooldown -= delta
			if _cooldown <= 0.0:
				_start_next_wave()
		"spawning":
			_cooldown -= delta
			if _cooldown <= 0.0 and _to_spawn > 0:
				_spawn_one()
				_to_spawn -= 1
				_cooldown = _spawn_interval
				if _to_spawn <= 0:
					phase = "clearing"
					status_text = "第 %d/%d 波：消灭剩余野兽" % [wave_index + 1, wave_total]
					_publish_state()
		"clearing":
			if _alive_count() == 0:
				if wave_index >= wave_total - 1:
					_declare_win()
				else:
					phase = "between"
					_cooldown = delay_between_waves
					status_text = "波次间隙…"
					_publish_state()
	_sync_positions()


func snapshot_to(peer_id: int) -> void:
	if not multiplayer.is_server() or peer_id <= 0:
		return
	rpc_wave_state.rpc_id(
		peer_id, wave_index, wave_total, phase, status_text, _alive_count()
	)
	for enemy in _enemies.get_children():
		rpc_spawn_enemy.rpc_id(peer_id, enemy.enemy_id, enemy.global_position, enemy.hp)
	for player in get_tree().get_nodes_in_group("net_players"):
		if player.has_method("rpc_sync_hp"):
			player.rpc_sync_hp.rpc_id(peer_id, player.hp)


func confirm_enemy_killed(enemy_id: int) -> void:
	if not multiplayer.is_server():
		return
	_despawn_everywhere(enemy_id)
	_publish_state()


func _all_connected_players_down() -> bool:
	var players := get_tree().get_nodes_in_group("net_players")
	if players.is_empty():
		return false
	for player in players:
		if player.hp > 0:
			return false
	return true


func _declare_win() -> void:
	if phase == "ended":
		return
	phase = "ended"
	status_text = "狩猎成功"
	print("Net run won")
	_publish_state()


func _declare_loss() -> void:
	if phase == "ended":
		return
	phase = "ended"
	# 原型临时规则、未定案：场上所有仍连接玩家生命归零才失败。不是最终合作失败设计。
	status_text = "狩猎失败（原型临时：全员倒下，未定案）"
	print("Net run lost")
	_publish_state()


func _start_next_wave() -> void:
	wave_index += 1
	if wave_index >= wave_total:
		_declare_win()
		return
	var cfg: WaveConfig = _waves[wave_index]
	_to_spawn = maxi(1, cfg.enemy_count)
	_spawn_interval = maxf(0.05, cfg.spawn_interval)
	_cooldown = 0.0
	phase = "spawning"
	status_text = "第 %d/%d 波" % [wave_index + 1, wave_total]
	print("Net wave start: ", wave_index + 1)
	_publish_state()


func _spawn_one() -> void:
	var enemy_id := _next_enemy_id
	_next_enemy_id += 1
	var pos := _spawn_position_for(enemy_id)
	_spawn_local(enemy_id, pos, 3)
	var arena := get_parent()
	if arena != null and arena.has_method("get_replication_peer_ids"):
		for peer_id in arena.get_replication_peer_ids():
			rpc_spawn_enemy.rpc_id(int(peer_id), enemy_id, pos, 3)
	_publish_state()


func _spawn_position_for(enemy_id: int) -> Vector2:
	var hx := arena_half_size.x - 36.0
	var hy := arena_half_size.y - 36.0
	var side := posmod(enemy_id - 1, 4)
	match side:
		0:
			return Vector2(0.0, -hy)
		1:
			return Vector2(hx, 0.0)
		2:
			return Vector2(0.0, hy)
		_:
			return Vector2(-hx, 0.0)


func _spawn_local(enemy_id: int, pos: Vector2, enemy_hp: int = 3) -> void:
	var node_name := "e%d" % enemy_id
	if _enemies.get_node_or_null(node_name) != null:
		return
	var enemy := NET_ENEMY_SCENE.instantiate()
	enemy.name = node_name
	enemy.enemy_id = enemy_id
	enemy.hp = enemy_hp
	enemy.position = pos
	_enemies.add_child(enemy, true)
	if enemy.has_method("setup"):
		enemy.setup(enemy_id)
	enemy.hp = enemy_hp
	if enemy.has_method("refresh_hp_label"):
		enemy.refresh_hp_label()


func _despawn_everywhere(enemy_id: int) -> void:
	_despawn_local(enemy_id)
	var arena := get_parent()
	if arena != null and arena.has_method("get_replication_peer_ids"):
		for peer_id in arena.get_replication_peer_ids():
			rpc_despawn_enemy.rpc_id(int(peer_id), enemy_id)


func _despawn_local(enemy_id: int) -> void:
	var node := _enemies.get_node_or_null("e%d" % enemy_id)
	if node != null:
		node.queue_free()


func _sync_positions() -> void:
	var arena := get_parent()
	if arena == null or not arena.has_method("get_replication_peer_ids"):
		return
	var peers: Array = arena.get_replication_peer_ids()
	if peers.is_empty():
		return
	for enemy in _enemies.get_children():
		for peer_id in peers:
			enemy.rpc_sync_position.rpc_id(int(peer_id), enemy.global_position)


func _alive_count() -> int:
	return _enemies.get_child_count()


func _publish_state() -> void:
	var alive := _alive_count()
	var arena := get_parent()
	if arena != null and arena.has_method("get_replication_peer_ids"):
		for peer_id in arena.get_replication_peer_ids():
			rpc_wave_state.rpc_id(
				int(peer_id), wave_index, wave_total, phase, status_text, alive
			)
	if arena != null and arena.has_method("_refresh_status"):
		arena._refresh_status()
	if multiplayer.is_server() and OS.get_cmdline_user_args().has("--session-probe"):
		print(
			"SESSION_PROBE wave=%d/%d phase=%s enemies=%d text=%s"
			% [wave_index + 1, wave_total, phase, alive, status_text]
		)


@rpc("authority", "reliable")
func rpc_wave_state(
	p_index: int, p_total: int, p_phase: String, p_text: String, p_alive: int
) -> void:
	wave_index = p_index
	wave_total = p_total
	phase = p_phase
	status_text = p_text
	var arena := get_parent()
	if arena != null and arena.has_method("_refresh_status"):
		arena._refresh_status()
	if OS.get_cmdline_user_args().has("--session-probe"):
		print(
			"SESSION_PROBE wave=%d/%d phase=%s enemies=%d text=%s"
			% [wave_index + 1, wave_total, phase, p_alive, p_text]
		)


@rpc("authority", "reliable")
func rpc_spawn_enemy(enemy_id: int, pos: Vector2, enemy_hp: int) -> void:
	_spawn_local(enemy_id, pos, enemy_hp)
	var arena := get_parent()
	if arena != null and arena.has_method("_refresh_status"):
		arena._refresh_status()
	if OS.get_cmdline_user_args().has("--session-probe"):
		print("SESSION_PROBE spawn enemy=%d count=%d" % [enemy_id, _alive_count()])


@rpc("authority", "reliable")
func rpc_despawn_enemy(enemy_id: int) -> void:
	_despawn_local(enemy_id)
	var arena := get_parent()
	if arena != null and arena.has_method("_refresh_status"):
		arena.call_deferred("_refresh_status")
	if OS.get_cmdline_user_args().has("--session-probe"):
		print("SESSION_PROBE despawn enemy=%d count=%d" % [enemy_id, _alive_count()])
