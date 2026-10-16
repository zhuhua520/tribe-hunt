extends Node
## 最小联机会话：ENet 创建 / 加入 / 离开，以及多人测试场景同步入口。

signal status_changed

enum ConnectionStatus {
	DISCONNECTED,
	HOSTING,
	CONNECTING,
	CONNECTED,
	FAILED,
}

const DEFAULT_PORT := 7777
const MAX_CLIENTS := 4
const CONNECT_TIMEOUT_SEC := 8.0
const ONLINE_LOBBY_SCENE := "res://scenes/menu/online_lobby.tscn"
const MP_MOVE_ARENA_SCENE := "res://scenes/combat/mp_move_arena.tscn"

var connection_status: ConnectionStatus = ConnectionStatus.DISCONNECTED
var status_text: String = "未连接"
var peer_count: int = 0
var listen_port: int = DEFAULT_PORT
var join_address: String = "127.0.0.1"
## 服务器当前同步的玩法场景；空表示停在菜单/大厅。
var synced_scene_path: String = ""

var _connect_timer: Timer


func _ready() -> void:
	_connect_timer = Timer.new()
	_connect_timer.name = "ConnectTimeout"
	_connect_timer.one_shot = true
	_connect_timer.wait_time = CONNECT_TIMEOUT_SEC
	_connect_timer.timeout.connect(_on_connect_timeout)
	add_child(_connect_timer)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	status_changed.connect(_on_status_changed_for_probe)
	call_deferred("_maybe_run_cmdline_probe")


func _maybe_run_cmdline_probe() -> void:
	# 仅用于本机双开探测：godot --path . -- --session-host / --session-join [--session-move-test]
	var args := OS.get_cmdline_user_args()
	if args.has("--session-host"):
		create_room(DEFAULT_PORT)
		if args.has("--session-move-test"):
			call_deferred("start_move_test")
	elif args.has("--session-join"):
		join_room("127.0.0.1", DEFAULT_PORT)
		if args.has("--session-move-test"):
			# 等连接成功后再进场景；由 status_changed 触发。
			status_changed.connect(_cmdline_enter_move_test_when_connected, CONNECT_ONE_SHOT)


func _on_status_changed_for_probe() -> void:
	if not OS.get_cmdline_user_args().has("--session-probe"):
		return
	print(
		"SESSION_PROBE status=%s peers=%d text=%s"
		% [ConnectionStatus.keys()[connection_status], peer_count, status_text]
	)


func _cmdline_enter_move_test_when_connected() -> void:
	if connection_status == ConnectionStatus.CONNECTED:
		start_move_test()
	elif connection_status == ConnectionStatus.CONNECTING:
		status_changed.connect(_cmdline_enter_move_test_when_connected, CONNECT_ONE_SHOT)


func can_start_session() -> bool:
	return (
		connection_status == ConnectionStatus.DISCONNECTED
		or connection_status == ConnectionStatus.FAILED
	)


func is_in_session() -> bool:
	return (
		connection_status == ConnectionStatus.HOSTING
		or connection_status == ConnectionStatus.CONNECTING
		or connection_status == ConnectionStatus.CONNECTED
	)


func create_room(port: int = DEFAULT_PORT) -> void:
	if not can_start_session():
		_emit_busy_hint()
		return
	if not _is_valid_port(port):
		_set_status(ConnectionStatus.FAILED, "端口无效，请输入 1–65535。")
		return

	synced_scene_path = ""
	_clear_peer()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		_set_status(
			ConnectionStatus.FAILED,
			"创建房间失败（错误码 %d）。端口可能已被占用。" % err
		)
		return

	multiplayer.multiplayer_peer = peer
	listen_port = port
	_refresh_peer_count()
	_set_status(
		ConnectionStatus.HOSTING,
		"已创建测试房间，监听端口 %d。等待其他实例加入…" % port
	)


func join_room(address: String, port: int = DEFAULT_PORT) -> void:
	if not can_start_session():
		_emit_busy_hint()
		return

	address = address.strip_edges()
	if address.is_empty():
		_set_status(ConnectionStatus.FAILED, "请输入服务器地址。")
		return
	if not _is_valid_port(port):
		_set_status(ConnectionStatus.FAILED, "端口无效，请输入 1–65535。")
		return

	synced_scene_path = ""
	_clear_peer()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		_set_status(
			ConnectionStatus.FAILED,
			"无法开始连接（错误码 %d）。请检查地址与端口。" % err
		)
		return

	multiplayer.multiplayer_peer = peer
	join_address = address
	listen_port = port
	_refresh_peer_count()
	_set_status(ConnectionStatus.CONNECTING, "正在连接 %s:%d…" % [address, port])
	_connect_timer.start()


func leave_session() -> void:
	_connect_timer.stop()
	var was_active := is_in_session() or connection_status == ConnectionStatus.FAILED
	synced_scene_path = ""
	_clear_peer()
	peer_count = 0
	if was_active:
		_set_status(ConnectionStatus.DISCONNECTED, "已离开会话。")
	else:
		_set_status(ConnectionStatus.DISCONNECTED, "未连接")


func can_enter_move_test() -> bool:
	return (
		connection_status == ConnectionStatus.HOSTING
		or connection_status == ConnectionStatus.CONNECTED
	)


func start_move_test() -> void:
	if not can_enter_move_test():
		status_text = "需要先创建或加入会话，才能进入移动测试。"
		status_changed.emit()
		return
	if multiplayer.is_server():
		_change_all_to_scene(MP_MOVE_ARENA_SCENE)
	else:
		rpc_request_start_move_test.rpc_id(1)


func return_to_online_lobby() -> void:
	if multiplayer.multiplayer_peer == null:
		_go_local_scene(ONLINE_LOBBY_SCENE)
		return
	if multiplayer.is_server():
		_change_all_to_scene(ONLINE_LOBBY_SCENE)
	else:
		rpc_request_return_to_lobby.rpc_id(1)


@rpc("any_peer", "reliable")
func rpc_request_start_move_test() -> void:
	if not multiplayer.is_server():
		return
	if can_enter_move_test():
		_change_all_to_scene(MP_MOVE_ARENA_SCENE)


@rpc("any_peer", "reliable")
func rpc_request_return_to_lobby() -> void:
	if not multiplayer.is_server():
		return
	_change_all_to_scene(ONLINE_LOBBY_SCENE)


func _change_all_to_scene(scene_path: String) -> void:
	synced_scene_path = scene_path
	rpc_change_scene.rpc(scene_path)


@rpc("authority", "call_local", "reliable")
func rpc_change_scene(scene_path: String) -> void:
	synced_scene_path = scene_path
	_go_local_scene(scene_path)


func _go_local_scene(scene_path: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_error("SessionService: 找不到场景 %s" % scene_path)
		return
	tree.paused = false
	# 已在目标场景则跳过，避免重复加载打乱复制就绪状态。
	var current := tree.current_scene
	if current != null and current.scene_file_path == scene_path:
		return
	# 联机下尽快切场景，减少生成 RPC 早到；仍用 deferred 避开树锁定。
	tree.call_deferred("change_scene_to_file", scene_path)


func _emit_busy_hint() -> void:
	# 保持当前状态，只刷新文案，避免重复点击把会话拆掉。
	match connection_status:
		ConnectionStatus.CONNECTING:
			status_text = "正在连接中，请稍候或先离开会话。"
		ConnectionStatus.HOSTING, ConnectionStatus.CONNECTED:
			status_text = "当前已有会话，请先离开后再创建或加入。"
		_:
			status_text = "请先离开当前会话。"
	status_changed.emit()


func _is_valid_port(port: int) -> bool:
	return port >= 1 and port <= 65535


func _clear_peer() -> void:
	_connect_timer.stop()
	var peer := multiplayer.multiplayer_peer
	if peer != null:
		peer.close()
	multiplayer.multiplayer_peer = null


func _refresh_peer_count() -> void:
	if multiplayer.multiplayer_peer == null:
		peer_count = 0
		return
	peer_count = multiplayer.get_peers().size() + 1


func _set_status(new_status: ConnectionStatus, message: String) -> void:
	connection_status = new_status
	status_text = message
	status_changed.emit()


func _status_with_peers(base: String) -> String:
	return "%s\n连接人数：%d" % [base, peer_count]


func _on_peer_connected(id: int) -> void:
	_refresh_peer_count()
	if connection_status == ConnectionStatus.HOSTING:
		_set_status(
			ConnectionStatus.HOSTING,
			_status_with_peers("房主在线，端口 %d。有玩家加入。" % listen_port)
		)
		# 晚加入：若已在玩法场景，拉新客户端进入同一场景。
		if not synced_scene_path.is_empty() and synced_scene_path != ONLINE_LOBBY_SCENE:
			rpc_change_scene.rpc_id(id, synced_scene_path)
	elif connection_status == ConnectionStatus.CONNECTED:
		_set_status(
			ConnectionStatus.CONNECTED,
			_status_with_peers("已连接到 %s:%d。" % [join_address, listen_port])
		)


func _on_peer_disconnected(_id: int) -> void:
	_refresh_peer_count()
	if connection_status == ConnectionStatus.HOSTING:
		_set_status(
			ConnectionStatus.HOSTING,
			_status_with_peers("房主在线，端口 %d。有玩家离开。" % listen_port)
		)
	elif connection_status == ConnectionStatus.CONNECTED:
		_set_status(
			ConnectionStatus.CONNECTED,
			_status_with_peers("已连接到 %s:%d。" % [join_address, listen_port])
		)


func _on_connected_to_server() -> void:
	_connect_timer.stop()
	_refresh_peer_count()
	_set_status(
		ConnectionStatus.CONNECTED,
		_status_with_peers("连接成功：%s:%d。" % [join_address, listen_port])
	)


func _on_connection_failed() -> void:
	_connect_timer.stop()
	synced_scene_path = ""
	_clear_peer()
	peer_count = 0
	_set_status(
		ConnectionStatus.FAILED,
		"连接失败：无法到达 %s:%d。请确认房主已创建房间，且地址/端口正确。"
		% [join_address, listen_port]
	)


func _on_server_disconnected() -> void:
	_connect_timer.stop()
	synced_scene_path = ""
	_clear_peer()
	peer_count = 0
	_set_status(ConnectionStatus.FAILED, "与房主断开连接。可重新加入或返回菜单。")
	_go_local_scene(ONLINE_LOBBY_SCENE)


func _on_connect_timeout() -> void:
	if connection_status != ConnectionStatus.CONNECTING:
		return
	synced_scene_path = ""
	_clear_peer()
	peer_count = 0
	_set_status(
		ConnectionStatus.FAILED,
		"连接超时：%s:%d 无响应。请检查地址、端口与防火墙。"
		% [join_address, listen_port]
	)
