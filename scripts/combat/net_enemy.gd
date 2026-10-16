extends CharacterBody2D
## 联机敌人。服务器驱动位移并结算生命；客户端只显示权威位置和生命。

@export var move_speed: float = 120.0
@export var arena_half_size: Vector2 = Vector2(480, 270)
@export var max_hp: int = 3

var enemy_id: int = 0
var hp: int = 3

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _hp_label: Label = $HpLabel


func _ready() -> void:
	add_to_group("net_enemies")
	hp = max_hp
	if _sprite.texture == null:
		_sprite.texture = load("res://assets/sprites/enemies/enemy.png")
	refresh_hp_label()


func setup(p_enemy_id: int) -> void:
	enemy_id = p_enemy_id
	name = "e%d" % enemy_id


func _physics_process(_delta: float) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	var target := _nearest_net_player()
	if target == null:
		velocity = Vector2.ZERO
	else:
		var to_target := target.global_position - global_position
		if to_target.length_squared() > 1.0:
			velocity = to_target.normalized() * move_speed
		else:
			velocity = Vector2.ZERO
	move_and_slide()
	global_position = global_position.clamp(-arena_half_size, arena_half_size)


func _nearest_net_player() -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("net_players"):
		if node == null or not is_instance_valid(node):
			continue
		if "hp" in node and node.hp <= 0:
			continue
		var dist := global_position.distance_squared_to(node.global_position)
		if dist < best_dist:
			best_dist = dist
			best = node
	return best


func apply_server_damage(amount: int) -> bool:
	if not multiplayer.is_server() or amount <= 0 or hp <= 0:
		return false
	hp = maxi(0, hp - amount)
	refresh_hp_label()
	_broadcast_hp()
	print("Net enemy HP: ", hp, "/", max_hp)
	return hp <= 0


func refresh_hp_label() -> void:
	if _hp_label != null:
		_hp_label.text = "%d/%d" % [hp, max_hp]


func _broadcast_hp() -> void:
	var arena := get_parent().get_parent() if get_parent() != null else null
	if arena == null or not arena.has_method("get_replication_peer_ids"):
		return
	for peer_id in arena.get_replication_peer_ids():
		rpc_sync_hp.rpc_id(int(peer_id), hp)


@rpc("authority", "reliable")
func rpc_sync_hp(new_hp: int) -> void:
	if multiplayer.is_server():
		return
	hp = new_hp
	refresh_hp_label()
	if OS.get_cmdline_user_args().has("--session-probe"):
		print("SESSION_PROBE enemy=%d hp=%d/%d" % [enemy_id, hp, max_hp])


@rpc("authority", "unreliable")
func rpc_sync_position(pos: Vector2) -> void:
	if multiplayer.is_server():
		return
	global_position = pos
	if (
		enemy_id == 1
		and OS.get_cmdline_user_args().has("--session-probe")
		and Engine.get_physics_frames() % 20 == 0
	):
		print("SESSION_PROBE enemy1 pos=%.1f,%.1f" % [pos.x, pos.y])
