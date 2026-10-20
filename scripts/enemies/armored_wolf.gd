extends "res://scripts/enemies/wolf.gd"
## 用野狼的巡逻、预警、追击和恢复，加上装甲目标的减伤与破甲。不是另一套 AI。

signal break_started
signal break_ended

@export var armor_reduction: int = 1
@export var armor_break_threshold: int = 3
@export var armor_break_seconds: float = 1.2

var armor_value: int = 0
var broken: bool = false
var _break_left: float = 0.0


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not broken:
		return
	_break_left = maxf(0.0, _break_left - delta)
	if _break_left <= 0.0:
		broken = false
		armor_value = 0
		break_ended.emit()


func take_damage(amount: int) -> void:
	receive_hit(amount, 0)


func receive_hit(damage: int, armor_break: int) -> void:
	if damage <= 0 or hp <= 0 or state == State.DEAD:
		return
	var applied := damage if broken else maxi(0, damage - armor_reduction)
	hp = maxi(0, hp - applied)
	print("Armor wolf HP: ", hp, "/", max_hp, " broken=", broken)
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
	if applied > 0:
		_hit_samples.clear()
		_enter(State.HURT, hurt_seconds)
