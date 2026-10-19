extends CanvasLayer
## 左侧开发者菜单。节点和文案在 scenes/ui/developer_panel.tscn。
## 物品走 ProgressState.add_item，进村才存档。木桩只在当前场景生成。
## 金钱规则未定：按钮只提示，不写存档、不新增货币字段。

const DUMMY_SCENE := preload("res://scenes/combat/enemy.tscn")
const ITEM_BUTTON := preload("res://scenes/ui/developer_item_button.tscn")
const MONEY_NOTE := "金钱尚未定义，没有写入存档"

var _open := false
var _note := ""

@onready var _tab: Button = $Tab
@onready var _panel: Control = $Panel
@onready var _status: Label = $Panel/Scroll/Box/Status
@onready var _items: VBoxContainer = $Panel/Scroll/Box/Items
@onready var _slash1: Button = $Panel/Scroll/Box/Slash1
@onready var _slash2: Button = $Panel/Scroll/Box/Slash2
@onready var _slash3: Button = $Panel/Scroll/Box/Slash3
@onready var _begin_charge: Button = $Panel/Scroll/Box/BeginCharge
@onready var _charged_slash: Button = $Panel/Scroll/Box/ChargedSlash
@onready var _dodge: Button = $Panel/Scroll/Box/Dodge
@onready var _aim_right: Button = $Panel/Scroll/Box/AimRight
@onready var _aim_left: Button = $Panel/Scroll/Box/AimLeft
@onready var _refill: Button = $Panel/Scroll/Box/Refill
@onready var _place_dummy: Button = $Panel/Scroll/Box/PlaceDummy
@onready var _clear_dummies: Button = $Panel/Scroll/Box/ClearDummies
@onready var _grant_money: Button = $Panel/Scroll/Box/GrantMoney


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_tab.pressed.connect(func() -> void: set_open(not _open))
	_slash1.pressed.connect(start_combo_step.bind(0))
	_slash2.pressed.connect(start_combo_step.bind(1))
	_slash3.pressed.connect(start_combo_step.bind(2))
	_begin_charge.pressed.connect(begin_charge)
	_charged_slash.pressed.connect(start_charged_slash)
	_dodge.pressed.connect(request_dodge)
	_aim_right.pressed.connect(aim_player.bind(Vector2.RIGHT))
	_aim_left.pressed.connect(aim_player.bind(Vector2.LEFT))
	_refill.pressed.connect(refill_targets)
	_place_dummy.pressed.connect(place_dummy)
	_clear_dummies.pressed.connect(clear_dummies)
	_grant_money.pressed.connect(grant_money_note)
	set_open(false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed("developer_menu"):
		return
	get_viewport().set_input_as_handled()
	set_open(not _open)


func _process(_delta: float) -> void:
	if _open:
		_refresh_status()


func is_open() -> bool:
	return _open


func set_open(open: bool) -> void:
	_open = open
	_panel.visible = open
	if open:
		_rebuild_item_buttons()
		_refresh_status()


func grant_item(item_id: StringName, amount: int = 1) -> bool:
	var ok := ProgressState.add_item(item_id, amount)
	_note = "已加入物品，进村才会存档" if ok else "未知物品，没有加入"
	_refresh_status()
	return ok


func grant_money_note() -> String:
	_note = MONEY_NOTE
	_refresh_status()
	return MONEY_NOTE


func place_dummy() -> bool:
	var player := _player()
	var host := get_tree().current_scene
	if player == null or host == null:
		_note = "当前没有战斗玩家，不能放置木桩"
		_refresh_status()
		return false
	var dummy := DUMMY_SCENE.instantiate()
	dummy.move_speed = 0.0
	dummy.contact_damage = 0
	dummy.max_hp = 30
	dummy.arena_half_size = Vector2(4000, 4000)
	dummy.set_physics_process(false)
	dummy.add_to_group("developer_dummies")
	host.add_child(dummy)
	dummy.global_position = player.global_position + _aim_direction(player) * 78.0
	_note = "已在瞄准方向放置木桩"
	_refresh_status()
	return true


func clear_dummies() -> void:
	for node in get_tree().get_nodes_in_group("developer_dummies"):
		node.queue_free()
	_note = "已清除开发者木桩"
	_refresh_status()


func refill_targets() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("enemies"):
		if node.has_method("refill"):
			node.refill()
			count += 1
		elif "hp" in node and "max_hp" in node:
			node.hp = node.max_hp
			count += 1
	_note = "已回满 %d 个目标" % count
	_refresh_status()
	return count


func aim_player(direction: Vector2) -> bool:
	var player := _player()
	var actions := _actions()
	if player == null or actions == null:
		_note = "当前没有战斗玩家"
		_refresh_status()
		return false
	actions.test_aim_point = player.global_position + direction.normalized() * 300.0
	_note = "瞄准已设为测试点"
	_refresh_status()
	return true


func start_combo_step(index: int) -> bool:
	var actions := _actions()
	if actions == null or not actions.debug_start_combo_step(index):
		_note = "当前没有战斗玩家"
		_refresh_status()
		return false
	_note = "已打出第 %d 段" % (index + 1)
	_refresh_status()
	return true


func begin_charge() -> bool:
	var actions := _actions()
	if actions == null or not actions.debug_begin_charge():
		_note = "当前没有战斗玩家"
		_refresh_status()
		return false
	_note = "已进入蓄力"
	_refresh_status()
	return true


func start_charged_slash() -> bool:
	var actions := _actions()
	if actions == null or not actions.debug_start_charged_slash():
		_note = "当前没有战斗玩家"
		_refresh_status()
		return false
	_note = "已打出蓄力斩"
	_refresh_status()
	return true


func set_physics_ticks(ticks: int) -> int:
	var previous := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = maxi(ticks, 1)
	return previous


func request_dodge() -> bool:
	var actions := _actions()
	if actions == null:
		_note = "当前没有战斗玩家"
		_refresh_status()
		return false
	actions.request(&"dodge")
	_note = "已请求闪避"
	_refresh_status()
	return true


func _player() -> Node2D:
	var player := get_tree().get_first_node_in_group("player")
	return player as Node2D


func _actions() -> Node:
	var player := _player()
	if player == null:
		return null
	return player.get_node_or_null("ActionController")


func _aim_direction(player: Node2D) -> Vector2:
	var actions := _actions()
	if actions != null and actions.test_aim_point is Vector2:
		var offset: Vector2 = actions.test_aim_point - player.global_position
		if offset.length() > 4.0:
			return offset.normalized()
	if actions != null:
		return actions.aim_direction
	return Vector2.RIGHT


func _rebuild_item_buttons() -> void:
	for child in _items.get_children():
		child.queue_free()
	for item_id in ProgressState.known_item_ids():
		var definition := ProgressState.get_definition(item_id)
		var label := definition.display_name if definition != null else String(item_id)
		var row := ITEM_BUTTON.instantiate()
		row.setup(StringName(item_id), label)
		row.grant_requested.connect(grant_item)
		_items.add_child(row)


func _refresh_status() -> void:
	if _status == null:
		return
	var lines := PackedStringArray()
	var scene := get_tree().current_scene
	lines.append("场景：%s" % (scene.name if scene != null else "无"))
	var actions := _actions()
	var player := _player()
	if actions == null or player == null:
		lines.append("战斗：当前场景没有玩家")
	else:
		var hp := str(player.hp) if "hp" in player else "-"
		var attack_id: String = actions.current_attack_id()
		lines.append("状态：%s  段：%d  血：%s" % [actions.state_label(), actions.combo_index(), hp])
		lines.append("招式：%s  次数：%d" % [attack_id if attack_id != "" else "无", actions.attack_count])
		lines.append("最近目标：%s" % _nearest_enemy_text(player))
	lines.append(ProgressState.summary_text())
	if _note != "":
		lines.append(_note)
	_status.text = "\n".join(lines)


func _nearest_enemy_text(player: Node2D) -> String:
	var nearest: Node = null
	var best := INF
	for node in get_tree().get_nodes_in_group("enemies"):
		if not (node is Node2D) or not ("hp" in node):
			continue
		var distance := player.global_position.distance_to((node as Node2D).global_position)
		if distance < best:
			best = distance
			nearest = node
	if nearest == null:
		return "无"
	return "%s %d/%d" % [nearest.name, nearest.hp, nearest.max_hp]
