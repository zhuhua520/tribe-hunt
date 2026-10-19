extends Area2D
## 地图出口：玩家层（碰撞层 1）的角色走入后，切换到目标场景的指定入口。每个实例只触发一次。

const SceneFlow = preload("res://scripts/ui/scene_flow.gd")

signal used

@export_file("*.tscn") var target_scene: String = ""
@export var target_entry_id: StringName = &""

var _used: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitorable = false
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _used or not body is CharacterBody2D:
		return
	_used = true
	used.emit()
	SceneFlow.go_to_entry(target_scene, target_entry_id)
