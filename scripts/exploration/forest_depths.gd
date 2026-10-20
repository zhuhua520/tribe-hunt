extends Node2D
## 森林深处：从林地外围西北支路进入，东侧返回外围，南侧进入野猪王巢穴。
## 区域 ID、敌群、掉落和唯一奖励来自区域表，不随玩家等级改。

const SceneFlow = preload("res://scripts/ui/scene_flow.gd")
const RegionCatalog := preload("res://scripts/exploration/region_catalog.gd")
const SessionGains := preload("res://scripts/ui/session_gains.gd")

const REGION_ID := "forest_depths"
const DEFAULT_ENTRY := &"from_outskirts"
const MESSAGE_SECONDS := 2.5

@export var camera_limits: Rect2i = Rect2i(-664, -424, 1328, 848)

@onready var _player: CharacterBody2D = $Player
@onready var _spawn_points: Node = $SpawnPoints
@onready var _inventory_label: Label = $UI/InventoryLabel
@onready var _message_label: Label = $UI/MessageLabel
@onready var _threat_label: Label = $UI/ThreatLabel
@onready var _defeat_panel: Control = $UI/DefeatPanel
@onready var _return_button: Button = $UI/DefeatPanel/VBox/ReturnButton
@onready var _stats_label: Label = $UI/DefeatPanel/VBox/StatsLabel

var entry_id: StringName = &""
var _message_left: float = 0.0
var _gains = SessionGains.new()


func _ready() -> void:
	var info: Dictionary = RegionCatalog.region(REGION_ID)
	DisplayServer.window_set_title("TribeHunt - %s" % String(info.get("name", "森林深处")))
	entry_id = SceneFlow.place_at_entry(_player, _spawn_points, DEFAULT_ENTRY)
	_threat_label.text = String(info.get("threat", ""))
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
