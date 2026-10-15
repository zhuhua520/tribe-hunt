extends Node2D
## 战斗场地：边界 + 读取玩家/波次信息更新窗口标题。

@export var half_size: Vector2 = Vector2(480, 270)

@onready var bounds_line: Line2D = $BoundsLine
@onready var player: Node = $Player
@onready var wave_manager: Node = $WaveManager

var _status: String = "准备狩猎"


func _ready() -> void:
	_draw_bounds()
	if wave_manager != null and wave_manager.has_signal("status_changed"):
		wave_manager.status_changed.connect(_on_status_changed)


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
