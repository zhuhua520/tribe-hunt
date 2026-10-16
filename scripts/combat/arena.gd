extends Node2D
## 战斗场地：边界 + 读取玩家/波次信息更新窗口标题。

@export var half_size: Vector2 = Vector2(1200, 800)

@onready var bounds_line: Line2D = $BoundsLine
@onready var player: Node = $Player
@onready var wave_manager: Node = $WaveManager

var _status: String = "准备狩猎"


func _ready() -> void:
	BuildRunService.begin_run()
	if player != null and "arena_half_size" in player:
		player.arena_half_size = half_size
	if wave_manager != null and "arena_half_size" in wave_manager:
		wave_manager.arena_half_size = half_size
	_layout_field()
	_configure_camera()
	if wave_manager != null and wave_manager.has_signal("status_changed"):
		wave_manager.status_changed.connect(_on_status_changed)


func _layout_field() -> void:
	var background := get_node_or_null("Background") as Polygon2D
	if background != null:
		background.polygon = PackedVector2Array([
			Vector2(-half_size.x, -half_size.y),
			Vector2(half_size.x, -half_size.y),
			Vector2(half_size.x, half_size.y),
			Vector2(-half_size.x, half_size.y),
		])
	_draw_bounds()


func _configure_camera() -> void:
	if player == null:
		return
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return
	camera.position_smoothing_enabled = false
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.limit_left = int(round(-half_size.x))
	camera.limit_top = int(round(-half_size.y))
	camera.limit_right = int(round(half_size.x))
	camera.limit_bottom = int(round(half_size.y))
	camera.enabled = true
	camera.make_current()


func _draw_bounds() -> void:
	var hx := half_size.x
	var hy := half_size.y
	bounds_line.points = PackedVector2Array([
		Vector2(-hx, -hy),
		Vector2(hx, -hy),
		Vector2(hx, hy),
		Vector2(-hx, hy),
		Vector2(-hx, -hy),
	])


func _on_status_changed(text: String) -> void:
	_status = text


func _process(_delta: float) -> void:
	var hp_text := "-/-"
	if player != null and "hp" in player and "max_hp" in player:
		hp_text = "%s/%s" % [player.hp, player.max_hp]
	DisplayServer.window_set_title("TribeHunt  %s  HP %s" % [_status, hp_text])
