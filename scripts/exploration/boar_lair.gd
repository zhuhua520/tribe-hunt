extends Node2D
## 独立野猪王巢穴。从森林深处进入。倒下保留当前内存所得，回村才保存。
## 再进会重置这场战斗。首次破阵只在这里发一次，竞技场那头不发。

const SceneFlow = preload("res://scripts/ui/scene_flow.gd")
const RegionCatalog := preload("res://scripts/exploration/region_catalog.gd")
const SessionGains := preload("res://scripts/ui/session_gains.gd")

const REGION_ID := "boar_lair"
const DEFAULT_ENTRY := &"from_depths"
const FIRST_CLAIM := &"boar_lair.first_core"
const FIRST_CORE := "core_break"
const MESSAGE_SECONDS := 2.5

@export var camera_limits: Rect2i = Rect2i(-512, -320, 1024, 640)

@onready var _player: CharacterBody2D = $Player
@onready var _spawn_points: Node = $SpawnPoints
@onready var _boar: Node = $BoarKing
@onready var _inventory_label: Label = $UI/InventoryLabel
@onready var _message_label: Label = $UI/MessageLabel
@onready var _threat_label: Label = $UI/ThreatLabel
@onready var _defeat_panel: Control = $UI/DefeatPanel
@onready var _return_button: Button = $UI/DefeatPanel/VBox/ReturnButton
@onready var _stats_label: Label = $UI/DefeatPanel/VBox/StatsLabel

var entry_id: StringName = &""
var _message_left: float = 0.0
var _reward_sent: bool = false
var _gains = SessionGains.new()


func _ready() -> void:
	var info: Dictionary = RegionCatalog.region(REGION_ID)
	DisplayServer.window_set_title("TribeHunt - %s" % String(info.get("name", "野猪王巢穴")))
	entry_id = SceneFlow.place_at_entry(_player, _spawn_points, DEFAULT_ENTRY)
	_threat_label.text = String(info.get("threat", ""))
	_configure_camera()
	ProgressState.items_changed.connect(_refresh_inventory)
	ProgressState.item_received.connect(_on_item_received)
	_refresh_inventory()
	_player.defeated.connect(_on_player_defeated)
	_return_button.pressed.connect(_on_return_pressed)
	if _boar != null and _boar.has_signal("defeated"):
		_boar.defeated.connect(_on_boar_defeated)
	_message_label.text = ""
	if ProgressState.is_claimed(FIRST_CLAIM):
		_message_label.text = "首次破阵已经领取，这场可以再打。"
		_message_left = MESSAGE_SECONDS


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


func _on_boar_defeated() -> void:
	if _reward_sent:
		return
	_reward_sent = true
	var reason := ProgressState.grant_claimed_instance(FIRST_CLAIM, FIRST_CORE)
	if reason == "":
		_message_label.text = "首次获得破阵"
		_message_left = MESSAGE_SECONDS


func _on_player_defeated() -> void:
	_defeat_panel.visible = true
	_stats_label.text = _gains.summary_text()
	_return_button.grab_focus()


func _on_return_pressed() -> void:
	SceneFlow.go_to(SceneFlow.VILLAGE)
