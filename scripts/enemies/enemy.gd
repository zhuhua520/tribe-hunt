extends CharacterBody2D
## 野兽占位：追踪玩家，接触造成伤害；可被武器击杀。

signal defeated

@export var move_speed: float = 120.0
@export var contact_damage: int = 1
@export var max_hp: int = 3
@export var arena_half_size: Vector2 = Vector2(480, 270)

var hp: int

@onready var sprite: Sprite2D = $Sprite2D
@onready var contact_area: Area2D = $ContactArea

var _player: Node2D
var _hurt_flash: float = 0.0


func _ready() -> void:
	add_to_group("enemies")
	hp = max_hp
	if sprite.texture == null:
		sprite.texture = load("res://assets/sprites/enemies/enemy.png")
	_resolve_player()
	var stats := get_tree().get_first_node_in_group("run_stats")
	if stats != null and stats.has_method("watch_enemy"):
		stats.watch_enemy(self)


func _physics_process(delta: float) -> void:
	if _hurt_flash > 0.0:
		_hurt_flash = maxf(0.0, _hurt_flash - delta)
		sprite.modulate = Color(1.0, 0.7, 0.7, 1.0)
	else:
		sprite.modulate = Color.WHITE

	if _player == null or not is_instance_valid(_player):
		_resolve_player()
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var to_player := _player.global_position - global_position
	if to_player.length_squared() > 0.0001:
		velocity = to_player.normalized() * move_speed
	else:
		velocity = Vector2.ZERO
	move_and_slide()
	global_position = global_position.clamp(-arena_half_size, arena_half_size)
	_try_contact_damage()


func take_damage(amount: int) -> void:
	if amount <= 0 or hp <= 0:
		return
	hp = maxi(0, hp - amount)
	_hurt_flash = 0.12
	print("Enemy HP: ", hp, "/", max_hp)
	if hp <= 0:
		print("Enemy defeated")
		defeated.emit()
		queue_free()


func _resolve_player() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node2D


func _try_contact_damage() -> void:
	for body in contact_area.get_overlapping_bodies():
		if body != null and body.has_method("take_damage") and body.is_in_group("player"):
			body.take_damage(contact_damage)
