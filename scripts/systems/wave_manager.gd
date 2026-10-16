extends Node
## 三波刷怪与胜负：读 data/waves 配置，清场后推进；第三波之后进入野猪王。

signal wave_changed(wave_index: int, total_waves: int)
signal status_changed(text: String)
signal build_adjustment_requested(wave_index: int, total_waves: int)
signal extraction_choice_requested(wave_index: int, total_waves: int)
signal run_won
signal run_lost
signal run_extracted

const BOAR_KING_SCENE := preload("res://scenes/combat/boar_king.tscn")
const RETURN_PORTAL_SCRIPT := preload("res://scripts/combat/return_portal.gd")

@export var enemy_scene: PackedScene
@export var waves: Array[WaveConfig] = []
@export var arena_half_size: Vector2 = Vector2(1200, 800)
@export var delay_before_first_wave: float = 0.8
@export var delay_between_waves: float = 1.2

var _wave_index: int = -1
var _to_spawn: int = 0
var _spawn_cooldown: float = 0.0
var _spawn_interval: float = 0.5
var _phase: String = "idle" # idle, spawning, clearing, extracting, adjusting, between, boss, portal, ended
var _player: Node
var _extraction_interval: int = 1
var _return_portal: Node2D


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
	_extraction_interval = _read_extraction_interval()
	_phase = "between"
	_spawn_cooldown = delay_before_first_wave
	print("Extraction interval: ", _extraction_interval)
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
					status_changed.emit("消灭剩余野兽")
		"clearing":
			if _alive_enemy_count() == 0:
				_on_wave_cleared()


func _start_next_wave() -> void:
	_wave_index += 1
	if _wave_index >= waves.size():
		_start_boar_king()
		return
	var cfg: WaveConfig = waves[_wave_index]
	_to_spawn = maxi(1, cfg.enemy_count)
	_spawn_interval = maxf(0.05, cfg.spawn_interval)
	_spawn_cooldown = 0.0
	_phase = "spawning"
	wave_changed.emit(_wave_index + 1, waves.size())
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


func _on_wave_cleared() -> void:
	if _wave_index >= waves.size() - 1:
		_start_boar_king()
		return
	if _is_extraction_checkpoint():
		_request_extraction_choice()
	else:
		_request_build_adjustment()


func _is_extraction_checkpoint() -> bool:
	var completed_waves := _wave_index + 1
	return completed_waves % _extraction_interval == 0


func _read_extraction_interval() -> int:
	if BuildRunService.extraction_wave_interval == BuildRunService.EXTRACTION_EVERY_TWO_WAVES:
		return BuildRunService.EXTRACTION_EVERY_TWO_WAVES
	return BuildRunService.EXTRACTION_EVERY_WAVE


func _request_extraction_choice() -> void:
	if _phase == "extracting":
		return
	_phase = "extracting"
	get_tree().paused = true
	print("Extraction choice wave=%d interval=%d" % [_wave_index + 1, _extraction_interval])
	extraction_choice_requested.emit(_wave_index + 1, waves.size())


func complete_extraction_continue() -> void:
	if _phase != "extracting":
		return
	print("Extraction continue")
	if _wave_index >= waves.size() - 1:
		get_tree().paused = false
		_start_boar_king()
		return
	_request_build_adjustment()


func complete_extraction_leave() -> void:
	if _phase != "extracting":
		return
	get_tree().paused = false
	_phase = "portal"
	_spawn_return_portal()
	print("Return portal open")


func _spawn_return_portal() -> void:
	if _return_portal != null and is_instance_valid(_return_portal):
		return
	var portal := Area2D.new()
	portal.set_script(RETURN_PORTAL_SCRIPT)
	portal.z_index = 2
	get_parent().add_child(portal)
	portal.global_position = _portal_position()
	_return_portal = portal


func _portal_position() -> Vector2:
	var origin := Vector2.ZERO
	if _player != null and is_instance_valid(_player):
		origin = _player.global_position
	var offset := Vector2(220.0, 0.0)
	var limit := arena_half_size - Vector2(90.0, 90.0)
	var pos := (origin + offset).clamp(-limit, limit)
	if pos.distance_to(origin) < 100.0:
		pos = (origin - offset).clamp(-limit, limit)
	return pos


func is_extraction_choice_active() -> bool:
	return _phase == "extracting"


func _request_build_adjustment() -> void:
	if _phase == "adjusting":
		return
	_phase = "adjusting"
	get_tree().paused = true
	build_adjustment_requested.emit(_wave_index + 1, waves.size())


func complete_build_adjustment() -> void:
	if _phase != "adjusting":
		return
	_phase = "between"
	_spawn_cooldown = delay_between_waves
	status_changed.emit("构筑已调整，下一波即将开始…")
	get_tree().paused = false


func is_build_adjustment_active() -> bool:
	return _phase == "adjusting"


func _start_boar_king() -> void:
	if _phase == "boss" or _phase == "ended":
		return
	_phase = "boss"
	var boar := BOAR_KING_SCENE.instantiate() as Node2D
	get_parent().add_child(boar)
	boar.global_position = _boss_spawn_position()
	if "arena_half_size" in boar:
		boar.arena_half_size = arena_half_size
	if boar.has_signal("defeated"):
		boar.defeated.connect(_on_boar_defeated)
	status_changed.emit("野猪王")
	print("Boar king start")


func _boss_spawn_position() -> Vector2:
	var origin := Vector2(180, 40)
	if _player != null and is_instance_valid(_player):
		origin = _player.global_position + Vector2(180, 50)
	var limit := arena_half_size - Vector2(96, 96)
	return Vector2(clampf(origin.x, -limit.x, limit.x), clampf(origin.y, -limit.y, limit.y))


func _on_boar_defeated() -> void:
	_finish_win()


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


func _finish_extract() -> void:
	if _phase == "ended":
		return
	_phase = "ended"
	get_tree().paused = false
	status_changed.emit("已撤离")
	print("Run extracted")
	run_extracted.emit()
