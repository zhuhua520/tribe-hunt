extends CharacterBody2D
const PreviewArt := preload("res://scripts/systems/borrowed_preview_art.gd")
## 部落战士：移动、生命和闪避。正式攻击是过渡自动木棍和弹弓，不因出手减速。
## collision_mask 24 = 野猪王身体（8）+ 实心地形（16）。普通敌人仍靠接触区域造成伤害。

signal defeated
signal damage_taken(amount: int)

@export var move_speed: float = 220.0
@export var arena_half_size: Vector2 = Vector2(1200, 800)
@export var max_hp: int = 8
@export var hurt_invuln_seconds: float = 0.6
## 只有竞技场对照打开。正式场景改用装备武器，避免和木棍、弹弓一起出手。
@export var use_historical_auto_weapons: bool = false

var hp: int
var shield_hp: int = 0
var shield_left: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var actions = get_node_or_null("ActionController")

var _invuln_left: float = 0.0
var _defeated_emitted: bool = false


func _ready() -> void:
	add_to_group("player")
	if not ProgressState.growth_changed.is_connected(_on_growth_changed):
		ProgressState.growth_changed.connect(_on_growth_changed)
	_apply_growth(true)
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
	if shield_left > 0.0:
		shield_left = maxf(0.0, shield_left - delta)
		if shield_left <= 0.0:
			shield_hp = 0


func _cancel_pending_melee() -> void:
	var melee := get_node_or_null("MeleeWeapon")
	if melee != null and melee.has_method("cancel_pending"):
		melee.cancel_pending()


func _update_sprite_frame(input_vector: Vector2, delta: float) -> void:
	if actions != null and actions.locks_facing() and sprite.has_method("play_attack"):
		if sprite.state != "attack":
			sprite.play_attack(actions.aim_direction)
		else:
			sprite.set_facing(actions.aim_direction)
		return
	sprite.update_motion(input_vector, delta)
	if actions != null and actions.locks_facing():
		sprite.set_facing(actions.aim_direction)


func take_damage(amount: int) -> void:
	if amount <= 0 or hp <= 0:
		return
	if _invuln_left > 0.0 or (actions != null and actions.is_invulnerable()):
		return
	var incoming := amount
	if shield_hp > 0 and shield_left > 0.0:
		var absorbed := mini(incoming, shield_hp)
		shield_hp -= absorbed
		incoming -= absorbed
		if incoming <= 0:
			return
	var applied := mini(incoming, hp)
	hp -= applied
	_invuln_left = hurt_invuln_seconds
	print("Player HP: ", hp, "/", max_hp)
	damage_taken.emit(applied)

	if hp <= 0:
		_on_defeated()
	elif actions != null:
		actions.on_hurt()
	_cancel_pending_melee()


func _on_growth_changed() -> void:
	_apply_growth(false)


func _apply_growth(fill: bool) -> void:
	var grown := ProgressState.player_max_hp()
	var delta := grown - max_hp
	max_hp = grown
	if fill:
		hp = max_hp
	elif delta > 0 and hp > 0:
		hp = mini(max_hp, hp + delta)
	else:
		hp = mini(hp, max_hp)


func accepts_hit() -> bool:
	if hp <= 0:
		return false
	if _invuln_left > 0.0:
		return false
	if actions != null and actions.is_invulnerable():
		return false
	return true


func _on_defeated() -> void:
	print("Player defeated")
	velocity = Vector2.ZERO
	sprite.modulate = Color(0.4, 0.4, 0.4, 1.0)
	_cancel_pending_melee()
	if actions != null:
		actions.on_defeated()
	if not _defeated_emitted:
		_defeated_emitted = true
		defeated.emit()
