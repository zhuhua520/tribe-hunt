extends Node2D
## S4 测试攻击：固定位置的圆形预警攻击，用来验证闪避。空闲 → 地面预警 → 结算一次 → 空闲，循环。
## 只对 player 组结算，伤害走玩家自己的 take_damage（闪避无敌、受击无敌都在那里判断）。数值是测试值。

signal struck(hit: bool)

enum Phase { IDLE, WARNING }

@export var idle_seconds: float = 1.2
@export var warning_seconds: float = 0.7
@export var radius: float = 64.0
@export var damage: int = 1

var phase: int = Phase.IDLE
var strike_count: int = 0

var _left: float = 0.0

@onready var _warning: Polygon2D = $Warning


func _ready() -> void:
	var points := PackedVector2Array()
	for i in 24:
		points.append(Vector2.RIGHT.rotated(TAU * float(i) / 24.0) * radius)
	_warning.polygon = points
	_warning.visible = false
	_left = idle_seconds


func _physics_process(delta: float) -> void:
	_left -= delta
	if phase == Phase.IDLE:
		if _left <= 0.0:
			phase = Phase.WARNING
			_left = warning_seconds
			_warning.visible = true
	else:
		_warning.color = Color(1.0, 0.3, 0.2, 0.15 + 0.45 * (1.0 - clampf(_left / warning_seconds, 0.0, 1.0)))
		if _left <= 0.0:
			_strike()
			phase = Phase.IDLE
			_left = idle_seconds
			_warning.visible = false


## 预警阶段距离结算还有多少秒；空闲阶段返回 -1。
func time_to_strike() -> float:
	return _left if phase == Phase.WARNING else -1.0


func _strike() -> void:
	strike_count += 1
	var hit := false
	for player in get_tree().get_nodes_in_group("player"):
		if player.hp > 0 and player.global_position.distance_to(global_position) <= radius:
			var before: int = player.hp
			player.take_damage(damage)
			hit = hit or player.hp < before
	struck.emit(hit)
