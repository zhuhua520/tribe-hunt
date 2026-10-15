extends Node
## 三波刷怪与胜负：读 data/waves 配置，清场后推进，玩家死亡则失败。

signal wave_changed(wave_index: int, total_waves: int)
signal status_changed(text: String)
signal run_won
signal run_lost

@export var enemy_scene: PackedScene
@export var waves: Array[WaveConfig] = []
@export var arena_half_size: Vector2 = Vector2(480, 270)
@export var delay_before_first_wave: float = 0.8
@export var delay_between_waves: float = 1.2

var _wave_index: int = -1
var _to_spawn: int = 0
var _spawn_cooldown: float = 0.0
var _spawn_interval: float = 0.5
var _phase: String = "idle" # idle, spawning, clearing, between, ended
var _player: Node


func _ready() -> void:
	if enemy_scene == null:
		enemy_scene = load("res://scenes/combat/enemy.tscn")
	if waves.is_empty():
		waves = [
			load("res://data/waves/wave_1.tres"),
			load("res://data/waves/wave_2.tres"),
			load("res://data/waves/wave_3.tres"),
		]
	_player = get_tree().get_first_node_in_group("player")
	if _player != null and _player.has_signal("defeated"):
		_player.defeated.connect(_on_player_defeated)
	_phase = "between"
	_spawn_cooldown = delay_before_first_wave
	# 延后一帧，确保 HUD 已连接信号。
	call_deferred("_emit_prepare_status")


func _emit_prepare_status() -> void:
	status_changed.emit("狩猎即将开始…")


func _physics_process(delta: float) -> void:
	if _phase == "ended":
		return

	if _player != null and "hp" in _player and _player.hp <= 0:
		_finish_loss()
		return

	match _phase:
		"between":
			_spawn_cooldown -= delta
			if _spawn_cooldown <= 0.0:
				_start_next_wave()
		"spawning":
			_spawn_cooldown -= delta
			if _spawn_cooldown <= 0.0 and _to_spawn > 0:
				_spawn_one_enemy()
				_to_spawn -= 1
				_spawn_cooldown = _spawn_interval
				if _to_spawn <= 0:
					_phase = "clearing"
					status_changed.emit("第 %d/%d 波：消灭剩余野兽" % [_wave_index + 1, waves.size()])
		"clearing":
			if _alive_enemy_count() == 0:
				if _wave_index >= waves.size() - 1:
					_finish_win()
				else:
					_phase = "between"
					_spawn_cooldown = delay_between_waves
					status_changed.emit("波次间隙…")


func _start_next_wave() -> void:
	_wave_index += 1
	if _wave_index >= waves.size():
		_finish_win()
		return
	var cfg: WaveConfig = waves[_wave_index]
	_to_spawn = maxi(1, cfg.enemy_count)
	_spawn_interval = maxf(0.05, cfg.spawn_interval)
	_spawn_cooldown = 0.0
	_phase = "spawning"
	wave_changed.emit(_wave_index + 1, waves.size())
	status_changed.emit("第 %d/%d 波" % [_wave_index + 1, waves.size()])
	print("Wave start: ", _wave_index + 1)


func _spawn_one_enemy() -> void:
	if enemy_scene == null:
		return
	var enemy := enemy_scene.instantiate() as Node2D
	var host := get_parent()
	host.add_child(enemy)
	enemy.global_position = _pick_spawn_position()
	if "arena_half_size" in enemy:
		enemy.arena_half_size = arena_half_size


func _pick_spawn_position() -> Vector2:
	var hx := arena_half_size.x - 24.0
	var hy := arena_half_size.y - 24.0
	var side := randi() % 4
	match side:
		0:
			return Vector2(randf_range(-hx, hx), -hy)
		1:
			return Vector2(randf_range(-hx, hx), hy)
		2:
			return Vector2(-hx, randf_range(-hy, hy))
		_:
			return Vector2(hx, randf_range(-hy, hy))


func _alive_enemy_count() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("enemies"):
		if node != null and is_instance_valid(node):
			if "hp" in node and node.hp <= 0:
				continue
			count += 1
	return count


func _on_player_defeated() -> void:
	_finish_loss()


func _finish_win() -> void:
	if _phase == "ended":
		return
	_phase = "ended"
	status_changed.emit("狩猎成功")
	print("Run won")
	run_won.emit()


func _finish_loss() -> void:
	if _phase == "ended":
		return
	_phase = "ended"
	status_changed.emit("狩猎失败")
	print("Run lost")
	run_lost.emit()
