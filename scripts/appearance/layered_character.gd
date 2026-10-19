extends Sprite2D
## 绑定到现有身体精灵；装备层同步身体帧、锚点、缩放及受击颜色。
## 不把已经合成的角色图片误当成可脱卸衣服；仅接受真正的透明叠加层。

signal appearance_changed

@export var profile: AppearanceProfile = preload("res://data/appearance/preview_profile.tres")
@export_file("*.tres") var initial_layer_paths: PackedStringArray = PackedStringArray()
var _layers: Dictionary = {}
var _definitions: Dictionary = {}
var _direction: String = "down"
var _state: String = "idle"
var _clock: float = 0.0


func _ready() -> void:
	if profile != null:
		hframes = maxi(1, profile.grid.x)
		vframes = maxi(1, profile.grid.y)
	for path in initial_layer_paths:
		var definition := load(path) as AppearanceLayer
		if definition != null:
			equip_layer(definition)
	_sync_frames()


func update_motion(motion: Vector2, delta: float) -> void:
	var next_state := "walk" if motion.length_squared() > 0.001 else "idle"
	if next_state != _state:
		_clock = 0.0
	_state = next_state
	if next_state == "walk":
		if absf(motion.x) > absf(motion.y):
			_direction = "right" if motion.x > 0 else "left"
		else:
			_direction = "down" if motion.y > 0 else "up"
	_clock += delta
	_sync_frames()


## 攻击等动作期间按瞄准方向朝向，不改变待机/行走状态和帧时钟。
func set_facing(direction: Vector2) -> void:
	if direction.length_squared() < 0.0001:
		return
	if absf(direction.x) > absf(direction.y):
		_direction = "right" if direction.x > 0 else "left"
	else:
		_direction = "down" if direction.y > 0 else "up"
	_sync_frames()


func equip_layer(definition: AppearanceLayer) -> bool:
	if definition == null or profile == null or definition.texture == null:
		return false
	if definition.layer_id.is_empty() or definition.item_id.is_empty() or definition.profile_id != profile.profile_id:
		return false
	if texture == null or definition.texture.get_size() != texture.get_size():
		return false
	remove_layer(definition.layer_id, false)
	var layer := Sprite2D.new()
	layer.texture = definition.texture
	layer.hframes = hframes
	layer.vframes = vframes
	layer.offset = offset
	layer.centered = centered
	layer.modulate = definition.tint
	layer.texture_filter = texture_filter
	# 身体为父节点，缩放和受击闪烁自然一致，不复制可变人物状态。
	add_child(layer)
	_layers[definition.layer_id] = layer
	_definitions[definition.layer_id] = definition
	_sync_frames()
	appearance_changed.emit()
	return true


func remove_layer(layer_id: String, notify: bool = true) -> void:
	if not _layers.has(layer_id):
		return
	var layer: Sprite2D = _layers[layer_id]
	remove_child(layer)
	layer.queue_free()
	_layers.erase(layer_id)
	_definitions.erase(layer_id)
	if notify:
		appearance_changed.emit()


func equipped_ids() -> Dictionary:
	var result := {}
	for key in _definitions:
		result[key] = _definitions[key].item_id
	return result


func _sync_frames() -> void:
	if profile == null:
		return
	frame_coords = profile.frame_for(_state, _direction, _clock)
	# 层序只用子节点顺序和 show_behind_parent；z_index 会让衣服层脱离世界 Y 排序，盖到树冠等前景上。
	var keys := _layers.keys()
	keys.sort_custom(func(a, b): return _layer_order(a) < _layer_order(b))
	for index in keys.size():
		var layer: Sprite2D = _layers[keys[index]]
		layer.frame_coords = frame_coords
		layer.show_behind_parent = _layer_order(keys[index]) < 0
		if layer.get_index() != index:
			move_child(layer, index)


func _layer_order(layer_id: String) -> int:
	var definition: AppearanceLayer = _definitions[layer_id]
	return int(definition.direction_orders.get(_direction, definition.draw_order))
