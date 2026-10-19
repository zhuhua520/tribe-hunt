extends CharacterBody2D
## 普通装甲测试目标。只有这份场景启用护甲和破甲。
## 触发破甲的那一击仍按破甲前的减伤结算。破甲期间不积累下一轮。结束后护甲和破甲值都重置。
## 致死一击不进入破甲。数值是测试值。

signal defeated
signal break_started
signal break_ended

@export var max_hp: int = 12
@export var armor_reduction: int = 1
@export var armor_break_threshold: int = 3
@export var armor_break_seconds: float = 1.2

var hp: int
var armor_value: int = 0
var broken: bool = false

var _break_left: float = 0.0
var _defeat_sent: bool = false

@onready var _visual: Polygon2D = $Visual
@onready var _status: Label = $StatusLabel


func _ready() -> void:
	add_to_group("enemies")
	hp = max_hp
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_refresh()


func _physics_process(delta: float) -> void:
	if not broken:
		return
	_break_left = maxf(0.0, _break_left - delta)
	if _break_left <= 0.0:
		broken = false
		armor_value = 0
		break_ended.emit()
		_refresh()


func receive_hit(damage: int, armor_break: int) -> void:
	if damage <= 0 or hp <= 0:
		return
	var applied := damage if broken else maxi(0, damage - armor_reduction)
	hp = maxi(0, hp - applied)
	print("Armor HP: ", hp, "/", max_hp, " broken=", broken)
	if hp <= 0:
		_die()
		return
	if not broken and armor_break > 0:
		armor_value += armor_break
		if armor_value >= armor_break_threshold:
			broken = true
			armor_value = 0
			_break_left = armor_break_seconds
			break_started.emit()
	_refresh()


func take_damage(amount: int) -> void:
	receive_hit(amount, 0)


func refill() -> void:
	hp = max_hp
	armor_value = 0
	broken = false
	_break_left = 0.0
	_refresh()


func _die() -> void:
	hp = 0
	broken = false
	_break_left = 0.0
	velocity = Vector2.ZERO
	if not _defeat_sent:
		_defeat_sent = true
		print("Armor target defeated")
		defeated.emit()
	queue_free()


func _refresh() -> void:
	if _status != null:
		if broken:
			_status.text = "破甲中 %d/%d" % [hp, max_hp]
		else:
			_status.text = "装甲 %d/%d  破甲 %d/%d" % [hp, max_hp, armor_value, armor_break_threshold]
	if _visual != null:
		_visual.color = Color(0.72, 0.48, 0.28, 1) if broken else Color(0.55, 0.58, 0.62, 1)
