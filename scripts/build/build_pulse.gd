extends Node2D
## 回响和破阵的占位圈。半径和颜色由生成它的机制写入。

var radius: float = 40.0
var color: Color = Color(0.4, 0.85, 1.0, 0.85)
var _left: float = 0.25


func _process(delta: float) -> void:
	_left -= delta
	queue_redraw()
	if _left <= 0.0:
		queue_free()


func _draw() -> void:
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, color, 2.0)
