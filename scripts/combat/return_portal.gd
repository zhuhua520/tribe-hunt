extends Area2D
## 波次结束后的回城传送门。走进后返回部落村落；不走进就可以留在副本里。

const SceneFlow = preload("res://scripts/ui/scene_flow.gd")

var _leaving: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false
	_build_visual()
	body_entered.connect(_on_body_entered)


func _build_visual() -> void:
	var outline := PackedVector2Array([
		Vector2(-28, -70),
		Vector2(28, -70),
		Vector2(36, 0),
		Vector2(28, 70),
		Vector2(-28, 70),
		Vector2(-36, 0),
	])
	var fill := Polygon2D.new()
	fill.color = Color(0.25, 0.45, 0.85, 0.92)
	fill.polygon = outline
	add_child(fill)
	var border := Line2D.new()
	border.width = 4.0
	border.default_color = Color(0.75, 0.9, 1.0, 1.0)
	border.closed = true
	border.points = outline
	add_child(border)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(72, 140)
	shape.shape = rect
	add_child(shape)
	var label := Label.new()
	label.text = "传送门"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.offset_left = -48.0
	label.offset_top = -14.0
	label.offset_right = 48.0
	label.offset_bottom = 16.0
	add_child(label)


func _on_body_entered(body: Node) -> void:
	if _leaving or not body.is_in_group("player"):
		return
	_leaving = true
	SceneFlow.go_to(SceneFlow.VILLAGE)
