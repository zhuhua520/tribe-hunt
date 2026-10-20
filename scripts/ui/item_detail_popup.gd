extends Control
## 鼠标指向地上可拾取物（inspectable_items 组）时显示物品详情。
## 放进任意场景的 CanvasLayer 即可使用；不处理拾取，只读 ItemDefinition 与数量。

const LootTable := preload("res://scripts/loot/loot_table.gd")
const THEME := preload("res://data/ui/ui_theme.tres")

const SCREEN_OFFSET := Vector2(20, 20)

## 测试可关闭鼠标跟随，改为手动调用 update_for_world_point。
@export var follow_mouse: bool = true

@onready var _panel: PanelContainer = $Panel
@onready var _name_label: Label = $Panel/VBox/NameLabel
@onready var _amount_label: Label = $Panel/VBox/AmountLabel
@onready var _description_label: Label = $Panel/VBox/DescriptionLabel
@onready var _source_label: Label = $Panel/VBox/SourceLabel
@onready var _hint_label: Label = $Panel/VBox/HintLabel

var current_target: Node2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	_panel.theme = THEME


func _process(_delta: float) -> void:
	if not follow_mouse:
		return
	var viewport := get_viewport()
	update_for_world_point(viewport.get_canvas_transform().affine_inverse() * viewport.get_mouse_position())


func update_for_world_point(world_point: Vector2) -> void:
	var target = _find_target(world_point)
	current_target = target
	if target == null or target.item == null:
		_panel.visible = false
		return
	_name_label.text = target.item.display_name
	_amount_label.text = "数量：%d" % target.amount
	_description_label.text = target.item.description
	_source_label.text = LootTable.sources_text_for_item(String(target.item.item_id))
	_hint_label.text = "按 E 拾取" if target.is_player_in_range() else "靠近后按 E 拾取"
	_panel.visible = true
	_panel.reset_size()
	var screen_position: Vector2 = get_viewport().get_canvas_transform() * target.global_position + SCREEN_OFFSET
	var limit := get_viewport_rect().size - _panel.size
	_panel.position = screen_position.clamp(Vector2.ZERO, limit.max(Vector2.ZERO))


func is_showing() -> bool:
	return _panel.visible


func _find_target(world_point: Vector2) -> Node2D:
	var best: Node2D = null
	var best_distance := INF
	for candidate in get_tree().get_nodes_in_group("inspectable_items"):
		if not is_instance_valid(candidate) or candidate.is_queued_for_deletion():
			continue
		if not candidate.contains_point(world_point):
			continue
		var distance: float = candidate.global_position.distance_squared_to(world_point)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best
