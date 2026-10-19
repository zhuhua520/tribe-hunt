extends CharacterBody2D
const PreviewArt := preload("res://scripts/systems/borrowed_preview_art.gd")
## 部落战士：移动、生命；手动动作由 ActionController 负责，自动木棍 + 弹弓为可开关辅助（默认关闭）。
## collision_mask 24 = 野猪王身体（8）+ 实心地形（16）。普通敌人仍靠接触区域造成伤害。

signal defeated
signal damage_taken(amount: int)

@export var move_speed: float = 220.0
@export var arena_half_size: Vector2 = Vector2(1200, 800)
@export var max_hp: int = 8
@export var hurt_invuln_seconds: float = 0.6

var hp: int

@onready var sprite: Sprite2D = $Sprite2D
@onready var actions = get_node_or_null("ActionController")

var _invuln_left: float = 0.0
var _defeated_emitted: bool = false


func _ready() -> void:
	add_to_group("player")
	hp = max_hp
	if sprite.texture == null:
		sprite.texture = PreviewArt.texture("player_sheet.png")


func _physics_process(delta: float) -> void:
	if hp > 0:
		var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		velocity = actions.movement_velocity(input_vector, move_speed) if actions != null else input_vector * move_speed
		move_and_slide()
		global_position = global_position.clamp(-arena_half_size, arena_half_size)
		_update_sprite_frame(input_vector, delta)

	if _invuln_left > 0.0:
		_invuln_left = maxf(0.0, _invuln_left - delta)
		var blink := fmod(_invuln_left, 0.1) < 0.05
		sprite.modulate = Color(1.0, 0.55, 0.55, 0.45 if blink else 1.0)
	elif hp > 0 and actions != null and actions.is_invulnerable():
		sprite.modulate = Color(1.0, 1.0, 1.0, 0.55)
	elif hp > 0:
		sprite.modulate = Color.WHITE


func _update_sprite_frame(input_vector: Vector2, delta: float) -> void:
	sprite.update_motion(input_vector, delta)
	if actions != null and actions.is_attacking():
		sprite.set_facing(actions.aim_direction)


func take_damage(amount: int) -> void:
	if amount <= 0 or hp <= 0:
		return
	if _invuln_left > 0.0 or (actions != null and actions.is_invulnerable()):
		return

	var applied := mini(amount, hp)
	hp -= applied
	_invuln_left = hurt_invuln_seconds
	print("Player HP: ", hp, "/", max_hp)
	damage_taken.emit(applied)

	if hp <= 0:
		_on_defeated()
	elif actions != null:
		actions.on_hurt()


func _on_defeated() -> void:
	print("Player defeated")
	velocity = Vector2.ZERO
	sprite.modulate = Color(0.4, 0.4, 0.4, 1.0)
	if actions != null:
		actions.on_defeated()
	if not _defeated_emitted:
		_defeated_emitted = true
		defeated.emit()
