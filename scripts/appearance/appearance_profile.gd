class_name AppearanceProfile
extends Resource
## 精灵表协议。所有叠加层共享网格、锚点和同一动画时钟。

@export var profile_id: String = "ninja_preview_v1"
@export var grid: Vector2i = Vector2i(4, 7)
@export var frames_per_second: float = 8.0
## LPC 等图集把方向放在行、动画帧放在列；旧预览图则相反。
@export var directions_in_rows: bool = false
@export var direction_order: PackedStringArray = PackedStringArray(["down", "up", "left", "right"])
@export var idle_frame_index: int = 0
@export var walk_frame_count: int = 3
## 键为状态_方向，方向顺序 down/up/left/right。值为帧坐标数组。
@export var clips: Dictionary = {}


func frame_for(state: String, direction: String, elapsed: float) -> Vector2i:
	var key := state + "_" + direction
	if clips.has(key) and clips[key] is Array and not clips[key].is_empty():
		var sequence: Array = clips[key]
		var index := int(maxf(0.0, elapsed) * maxf(0.0, frames_per_second)) % sequence.size()
		var frame: Vector2i = sequence[index]
		return frame.clamp(Vector2i.ZERO, grid - Vector2i.ONE)
	var direction_index := maxi(0, direction_order.find(direction))
	var animation_index := idle_frame_index
	if state == "walk" and walk_frame_count > 0:
		animation_index = int(maxf(0.0, elapsed) * maxf(0.0, frames_per_second)) % walk_frame_count
	if directions_in_rows:
		return Vector2i(animation_index, direction_index).clamp(Vector2i.ZERO, grid - Vector2i.ONE)
	# 旧预览图的第 0 行是待机，第 1 行开始是行走帧。
	var legacy_row := animation_index + 1 if state == "walk" else idle_frame_index
	return Vector2i(direction_index, legacy_row).clamp(Vector2i.ZERO, grid - Vector2i.ONE)
