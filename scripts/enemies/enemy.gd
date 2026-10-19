extends CharacterBody2D
const PreviewArt := preload("res://scripts/systems/borrowed_preview_art.gd")
## 野兽占位：追踪玩家，接触造成伤害；可被武器击杀。

signal defeated

const DROP_SCENE := preload("res://scenes/props/world_drop.tscn")
const ItemCatalog := preload("res://scripts/items/item_catalog.gd")

@export var move_speed: float = 120.0
@export var contact_damage: int = 1
@export var max_hp: int = 3
@export var arena_half_size: Vector2 = Vector2(480, 270)
## 可选：死亡时在原地生成的掉落物。为空则不掉落（竞技场敌人保持原行为）。
@export var drop_item: ItemDefinition
## 物品表里的 id。drop_item 为空时才用它。新掉落写这个，不要再新增物品资源。
@export var drop_item_id: StringName = &""
@export var drop_amount: int = 1

var hp: int

@onready var sprite: Sprite2D = $Sprite2D
@onready var contact_area: Area2D = $ContactArea

var _player: Node2D
var _hurt_flash: float = 0.0
var _walk_clock: float = 0.0


func _ready() -> void:
	add_to_group("enemies")
	hp = max_hp
	if sprite.texture == null:
		sprite.texture = PreviewArt.texture("boar_sheet.png")
	sprite.hframes = 2
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
		sprite.rotation = to_player.angle() - PI
	else:
		velocity = Vector2.ZERO
	move_and_slide()
	global_position = global_position.clamp(-arena_half_size, arena_half_size)
	_walk_clock += delta
	sprite.frame = int(_walk_clock * 5.0) % 2
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
		_spawn_drop()
		queue_free()


func _spawn_drop() -> void:
	var definition := drop_item
	if definition == null and drop_item_id != &"":
		definition = ItemCatalog.make_definition(drop_item_id)
	if definition == null or drop_amount <= 0 or get_parent() == null:
		return
	var drop := DROP_SCENE.instantiate()
	drop.item = definition
	drop.amount = drop_amount
	drop.position = position
	# 死亡可能发生在物理回调中，新增 Area2D 要延后到回调之外。
	get_parent().add_child.call_deferred(drop)


func _resolve_player() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node2D


func _try_contact_damage() -> void:
	for body in contact_area.get_overlapping_bodies():
		if body != null and body.has_method("take_damage") and body.is_in_group("player"):
			body.take_damage(contact_damage)
