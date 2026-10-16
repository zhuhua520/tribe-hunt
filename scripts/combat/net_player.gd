extends CharacterBody2D
## 联机移动测试用玩家：客户端提交移动意图，服务器权威位移并同步位置。

const TINTS: Array[Color] = [
	Color(1.0, 1.0, 1.0),
	Color(0.45, 0.78, 1.0),
	Color(1.0, 0.72, 0.38),
	Color(0.55, 0.95, 0.55),
]

@export var move_speed: float = 220.0
@export var arena_half_size: Vector2 = Vector2(480, 270)
@export var max_hp: int = 8
@export var hurt_invuln_seconds: float = 0.6

var peer_id: int = 1
var hp: int = 8

var _input_dir: Vector2 = Vector2.ZERO
var _invuln_left: float = 0.0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _name_label: Label = $NameLabel


func _ready() -> void:
	add_to_group("net_players")
	hp = max_hp
	if _sprite.texture == null:
		_sprite.texture = load("res://assets/sprites/player/player.png")
	_apply_identity_visuals()


func setup(p_peer_id: int) -> void:
	peer_id = p_peer_id
	name = str(peer_id)
	if is_node_ready():
		_apply_identity_visuals()


func is_local_player() -> bool:
	if multiplayer.multiplayer_peer == null:
		return false
	return peer_id == multiplayer.get_unique_id()


func _apply_identity_visuals() -> void:
	var tint_index := posmod(peer_id - 1, TINTS.size())
	_sprite.modulate = TINTS[tint_index]
	if _name_label != null:
		var who := "你" if is_local_player() else "同伴"
		_name_label.text = "%s %d/%d" % [who, hp, max_hp]


func _physics_process(_delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return

	if is_local_player():
		var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		dir = dir.limit_length(1.0)
		if multiplayer.is_server():
			_input_dir = dir
		else:
			rpc_submit_input.rpc_id(1, dir)

	if not multiplayer.is_server():
		return

	if _invuln_left > 0.0:
		_invuln_left = maxf(0.0, _invuln_left - _delta)
	if hp <= 0:
		_input_dir = Vector2.ZERO
	velocity = _input_dir * move_speed
	move_and_slide()
	global_position = global_position.clamp(-arena_half_size, arena_half_size)
	_broadcast_position_to_ready_peers()


func _broadcast_position_to_ready_peers() -> void:
	var arena := get_parent().get_parent() if get_parent() != null else null
	if arena == null or not arena.has_method("get_replication_peer_ids"):
		return
	for target_id in arena.get_replication_peer_ids():
		rpc_sync_position.rpc_id(int(target_id), global_position)


@rpc("any_peer", "reliable")
func rpc_submit_input(dir: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != peer_id:
		return
	if hp <= 0:
		return
	_input_dir = dir.limit_length(1.0)


func server_receive_contact(amount: int) -> void:
	if not multiplayer.is_server() or amount <= 0 or hp <= 0 or _invuln_left > 0.0:
		return
	hp = maxi(0, hp - amount)
	_invuln_left = hurt_invuln_seconds
	_apply_identity_visuals()
	_broadcast_hp()
	print("Net player HP: ", hp, "/", max_hp)
	if hp <= 0:
		_input_dir = Vector2.ZERO
		print("Net player down: ", peer_id)


func _broadcast_hp() -> void:
	var arena := get_parent().get_parent() if get_parent() != null else null
	if arena == null or not arena.has_method("get_replication_peer_ids"):
		return
	for target_id in arena.get_replication_peer_ids():
		rpc_sync_hp.rpc_id(int(target_id), hp)


@rpc("authority", "reliable")
func rpc_sync_hp(new_hp: int) -> void:
	if multiplayer.is_server():
		return
	hp = new_hp
	if hp <= 0:
		_input_dir = Vector2.ZERO
	_apply_identity_visuals()
	if OS.get_cmdline_user_args().has("--session-probe"):
		print("SESSION_PROBE player=%d hp=%d/%d" % [peer_id, hp, max_hp])


@rpc("authority", "unreliable")
func rpc_sync_position(pos: Vector2) -> void:
	if multiplayer.is_server():
		return
	global_position = pos
	if OS.get_cmdline_user_args().has("--session-probe") and peer_id == 1:
		# 仅抽样打印房主位置，便于确认客户端收到权威同步。
		if Engine.get_physics_frames() % 30 == 0:
			print("SESSION_PROBE sync_host pos=%.1f,%.1f" % [pos.x, pos.y])
