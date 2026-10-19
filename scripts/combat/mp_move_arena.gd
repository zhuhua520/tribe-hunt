extends Node2D
## 多人测试场：玩家移动、服务器权威敌人/波次，以及临时自动攻击结算。

const SceneFlow = preload("res://scripts/ui/scene_flow.gd")
const PreviewArt := preload("res://scripts/systems/borrowed_preview_art.gd")
const NET_PLAYER_SCENE := preload("res://scenes/combat/net_player.tscn")

const SPAWN_OFFSETS: Array[Vector2] = [
	Vector2(-96, 0),
	Vector2(96, 0),
	Vector2(0, -96),
	Vector2(0, 96),
]

@export var half_size: Vector2 = Vector2(480, 270)

@onready var _bounds_line: Line2D = $BoundsLine
@onready var _players: Node2D = $Players
@onready var _wave_director: Node = $WaveDirector
@onready var _status_label: Label = $CanvasLayer/Hud/Margin/VBox/StatusLabel
@onready var _back_button: Button = $CanvasLayer/Hud/Margin/VBox/BackButton
@onready var _leave_button: Button = $CanvasLayer/Hud/Margin/VBox/LeaveButton

## 已完成本场景复制就绪的 peer（可安全接收生成/位移 RPC）。
var _replication_ready_peers: Dictionary = {}


func _ready() -> void:
	var ground_art := $GroundArt as Sprite2D
	ground_art.texture = PreviewArt.texture("arena_ground.png")
	_draw_bounds()
	_back_button.pressed.connect(_on_back_pressed)
	_leave_button.pressed.connect(_on_leave_pressed)
	SessionService.status_changed.connect(_on_session_status_changed)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_refresh_status()
	if multiplayer.is_server():
		_replication_ready_peers[multiplayer.get_unique_id()] = true
		await get_tree().process_frame
		for peer_id in _connected_peer_ids():
			_spawn_local(peer_id, _spawn_position_for(peer_id))
		_refresh_status()
	else:
		# 等本机场景就绪后再向服务器拉全量玩家，避免 RPC 打空路径。
		rpc_request_spawn_sync.rpc_id(1)


func _exit_tree() -> void:
	if SessionService.status_changed.is_connected(_on_session_status_changed):
		SessionService.status_changed.disconnect(_on_session_status_changed)
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)


func get_replication_peer_ids() -> Array[int]:
	var ids: Array[int] = []
	for peer_id in _replication_ready_peers.keys():
		if int(peer_id) == multiplayer.get_unique_id():
			continue
		ids.append(int(peer_id))
	return ids


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed("ui_cancel"):
		return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
	_on_back_pressed()


func _draw_bounds() -> void:
	var hx := half_size.x
	var hy := half_size.y
	_bounds_line.points = PackedVector2Array([
		Vector2(-hx, -hy),
		Vector2(hx, -hy),
		Vector2(hx, hy),
		Vector2(-hx, hy),
		Vector2(-hx, -hy),
	])


func _connected_peer_ids() -> Array[int]:
	var ids: Array[int] = [multiplayer.get_unique_id()]
	for peer_id in multiplayer.get_peers():
		ids.append(peer_id)
	ids.sort()
	return ids


func _spawn_position_for(peer_id: int) -> Vector2:
	var ids := _connected_peer_ids()
	var index := ids.find(peer_id)
	if index < 0:
		index = posmod(peer_id - 1, SPAWN_OFFSETS.size())
	else:
		index = posmod(index, SPAWN_OFFSETS.size())
	return SPAWN_OFFSETS[index]


func _spawn_local(peer_id: int, spawn_pos: Vector2) -> void:
	if _players.get_node_or_null(str(peer_id)) != null:
		return
	var player := NET_PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.peer_id = peer_id
	player.position = spawn_pos
	_players.add_child(player, true)
	if player.has_method("setup"):
		player.setup(peer_id)


func _despawn_local(peer_id: int) -> void:
	var node := _players.get_node_or_null(str(peer_id))
	if node != null:
		node.queue_free()


@rpc("any_peer", "reliable")
func rpc_request_spawn_sync() -> void:
	if not multiplayer.is_server():
		return
	var requester := multiplayer.get_remote_sender_id()
	if requester <= 0:
		return
	_replication_ready_peers[requester] = true
	for peer_id in _connected_peer_ids():
		var spawn_pos := _spawn_position_for(peer_id)
		_spawn_local(peer_id, spawn_pos)
		rpc_spawn_player.rpc_id(requester, peer_id, spawn_pos)
	if _wave_director != null and _wave_director.has_method("snapshot_to"):
		_wave_director.snapshot_to(requester)
	_refresh_status()


@rpc("authority", "reliable")
func rpc_spawn_player(peer_id: int, spawn_pos: Vector2) -> void:
	_spawn_local(peer_id, spawn_pos)
	_refresh_status()


@rpc("authority", "reliable")
func rpc_despawn_player(peer_id: int) -> void:
	_despawn_local(peer_id)
	call_deferred("_refresh_status")


func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var spawn_pos := _spawn_position_for(peer_id)
	_spawn_local(peer_id, spawn_pos)
	for ready_id in get_replication_peer_ids():
		rpc_spawn_player.rpc_id(ready_id, peer_id, spawn_pos)
	_refresh_status()


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_replication_ready_peers.erase(peer_id)
	_despawn_local(peer_id)
	for ready_id in get_replication_peer_ids():
		rpc_despawn_player.rpc_id(ready_id, peer_id)
	call_deferred("_refresh_status")


func _on_session_status_changed() -> void:
	_refresh_status()
	if not SessionService.is_in_session():
		SceneFlow.go_to(SceneFlow.ONLINE_LOBBY)


func _refresh_status() -> void:
	if _players == null or _status_label == null:
		return
	var count := _players.get_child_count()
	var wave_line := "等待波次"
	var enemy_count := 0
	if _wave_director != null:
		wave_line = str(_wave_director.status_text)
	if has_node("Enemies"):
		enemy_count = $Enemies.get_child_count()
	var hp_line := ""
	for player in get_tree().get_nodes_in_group("net_players"):
		if player.has_method("is_local_player") and player.is_local_player():
			hp_line = "你的生命：%d/%d\n" % [player.hp, player.max_hp]
			break
	_status_label.text = (
		"%s\n%s场上玩家：%d　敌人：%d\n%s\nWASD 只控制「你」。攻击由服务器自动结算（临时对齐单人木棍/弹弓）"
		% [wave_line, hp_line, count, enemy_count, SessionService.status_text]
	)
	DisplayServer.window_set_title(
		"TribeHunt  波次测试  玩家 %d  敌人 %d" % [count, enemy_count]
	)
	if OS.get_cmdline_user_args().has("--session-probe"):
		print(
			"SESSION_PROBE players=%d enemies=%d scene=MpMoveArena"
			% [count, enemy_count]
		)


func _on_back_pressed() -> void:
	SessionService.return_to_online_lobby()


func _on_leave_pressed() -> void:
	SessionService.leave_session()
	SceneFlow.go_to(SceneFlow.ONLINE_LOBBY)
