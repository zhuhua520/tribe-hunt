extends CharacterBody2D
## 部落战士：移动、生命；近战木棍 + 远程弹弓挂为子节点。

signal defeated

@export var move_speed: float = 220.0
@export var arena_half_size: Vector2 = Vector2(480, 270)
@export var max_hp: int = 8
@export var hurt_invuln_seconds: float = 0.6

var hp: int

@onready var sprite: Sprite2D = $Sprite2D

var _invuln_left: float = 0.0
var _defeated_emitted: bool = false


func _ready() -> void:
	add_to_group("player")
	hp = max_hp
	if sprite.texture == null:
		sprite.texture = load("res://assets/sprites/player/player.png")


func _physics_process(delta: float) -> void:
	if hp > 0:
		var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		velocity = input_vector * move_speed
		move_and_slide()
		global_position = global_position.clamp(-arena_half_size, arena_half_size)

	if _invuln_left > 0.0:
		_invuln_left = maxf(0.0, _invuln_left - delta)
		var blink := fmod(_invuln_left, 0.1) < 0.05
		sprite.modulate = Color(1.0, 0.55, 0.55, 0.45 if blink else 1.0)
	elif hp > 0:
		sprite.modulate = Color.WHITE


func take_damage(amount: int) -> void:
	if amount <= 0 or hp <= 0:
		return
	if _invuln_left > 0.0:
		return

	hp = maxi(0, hp - amount)
	_invuln_left = hurt_invuln_seconds
	print("Player HP: ", hp, "/", max_hp)

	if hp <= 0:
		_on_defeated()


func _on_defeated() -> void:
	print("Player defeated")
	velocity = Vector2.ZERO
	sprite.modulate = Color(0.4, 0.4, 0.4, 1.0)
	if not _defeated_emitted:
		_defeated_emitted = true
		defeated.emit()
