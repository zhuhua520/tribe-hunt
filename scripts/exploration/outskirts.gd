extends Node2D
## 林地外围（灰盒）：从村落西侧道路进入，东侧出口回村。
## S1：往返、出生点、实心墙、相机边界与占位树遮挡。S2：西北支路一次性测试拾取、一只现有野兽。
## S5b：南侧一只野狼，活动范围外会返回。正式外观仍等 A3。
## 背包原型：野兽死亡掉落测试兽皮；鼠标指向地上物品由 UI/ItemDetailPopup 显示详情；I 打开 InventoryPanel。
## 持有物和领取状态在 ProgressState；本场景只负责布局、提示和倒下后的临时返回入口。

const SceneFlow = preload("res://scripts/ui/scene_flow.gd")
const PreviewArt := preload("res://scripts/systems/borrowed_preview_art.gd")
const SessionGains := preload("res://scripts/ui/session_gains.gd")

const DEFAULT_ENTRY := &"from_village"
const MESSAGE_SECONDS := 2.5

@export var camera_limits: Rect2i = Rect2i(-1264, -864, 2784, 1728)

@onready var _player: CharacterBody2D = $Player
@onready var _spawn_points: Node = $SpawnPoints
@onready var _tree_sprite: Sprite2D = $PlaceholderTree/Sprite2D
@onready var _inventory_label: Label = $UI/InventoryLabel
@onready var _message_label: Label = $UI/MessageLabel
@onready var _defeat_panel: Control = $UI/DefeatPanel
@onready var _return_button: Button = $UI/DefeatPanel/VBox/ReturnButton
@onready var _stats_label: Label = $UI/DefeatPanel/VBox/StatsLabel

var entry_id: StringName = &""
var _message_left: float = 0.0
var _gains = SessionGains.new()


func _ready() -> void:
	DisplayServer.window_set_title("TribeHunt - 林地外围（灰盒）")
	entry_id = SceneFlow.place_at_entry(_player, _spawn_points, DEFAULT_ENTRY)
	_tree_sprite.texture = PreviewArt.texture("tree_round.png")
	_configure_camera()
	ProgressState.items_changed.connect(_refresh_inventory)
	ProgressState.item_received.connect(_on_item_received)
	_refresh_inventory()
	_player.defeated.connect(_on_player_defeated)
	_return_button.pressed.connect(_on_return_pressed)
	_message_label.text = ""


func _process(delta: float) -> void:
	if _message_left > 0.0:
		_message_left = maxf(0.0, _message_left - delta)
		if _message_left <= 0.0:
			_message_label.text = ""


func _configure_camera() -> void:
	var camera := _player.get_node("Camera2D") as Camera2D
	camera.position_smoothing_enabled = false
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.limit_left = camera_limits.position.x
	camera.limit_top = camera_limits.position.y
	camera.limit_right = camera_limits.end.x
	camera.limit_bottom = camera_limits.end.y
	camera.enabled = true
	camera.make_current()
	camera.reset_smoothing()


func _refresh_inventory() -> void:
	_inventory_label.text = ProgressState.summary_text()


func _on_item_received(item_id: StringName, amount: int) -> void:
	var definition := ProgressState.get_definition(item_id)
	var item_name := definition.display_name if definition != null else String(item_id)
	_message_label.text = "获得 %s ×%d" % [item_name, amount]
	_message_left = MESSAGE_SECONDS
	_gains.add(item_id, amount)


func _on_player_defeated() -> void:
	_defeat_panel.visible = true
	_stats_label.text = _gains.summary_text()
	_return_button.grab_focus()


func _on_return_pressed() -> void:
	SceneFlow.go_to(SceneFlow.VILLAGE)
