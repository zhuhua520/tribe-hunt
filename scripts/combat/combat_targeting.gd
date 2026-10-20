extends RefCounted
## 单人武器共用的目标与伤害入口。hit() 仍是旧调用方式，内部走 resolve()。

const TERRAIN_LAYER := 16
const MAX_TRIGGER_DEPTH := 1
const ContextScript := preload("res://scripts/combat/hit_context.gd")
const ResultScript := preload("res://scripts/combat/hit_result.gd")
const BusScript := preload("res://scripts/combat/combat_event_bus.gd")

static var _next_attack_id: int = 1
static var _attack_hits: Dictionary = {}
static var _bus: RefCounted


static func event_bus() -> RefCounted:
	if _bus == null:
		_bus = BusScript.new()
	return _bus


static func begin_attack() -> int:
	var attack_id := _next_attack_id
	_next_attack_id += 1
	_attack_hits[attack_id] = {}
	return attack_id


static func close_attack(attack_id: int) -> void:
	_attack_hits.erase(attack_id)


static func is_live_target(target: Node) -> bool:
	return is_instance_valid(target) and not target.is_queued_for_deletion() \
		and target is Node2D and target.has_method("take_damage") \
		and target.is_in_group("enemies") and (not "hp" in target or target.hp > 0)


## 范围内距离最近、且与 source 之间没有实心地形（碰撞层 16）遮挡的有效敌人。
static func nearest_enemy(source: Node2D, radius: float) -> Node2D:
	var in_range: Array = []
	var radius_squared := radius * radius
	for candidate in source.get_tree().get_nodes_in_group("enemies"):
		if not is_live_target(candidate):
			continue
		var distance := source.global_position.distance_squared_to(candidate.global_position)
		if distance <= radius_squared:
			in_range.append([distance, candidate.get_instance_id(), candidate])
	in_range.sort_custom(func(a: Array, b: Array) -> bool:
		if not is_equal_approx(float(a[0]), float(b[0])):
			return float(a[0]) < float(b[0])
		return int(a[1]) < int(b[1])
	)
	for entry in in_range:
		if has_line_of_sight(source, entry[2]):
			return entry[2]
	return null


static func has_line_of_sight(source: Node2D, target: Node2D) -> bool:
	var space := source.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(source.global_position, target.global_position, TERRAIN_LAYER)
	return space.intersect_ray(query).is_empty()


static func hit(target: Node, damage: int, armor_break: int = 0) -> bool:
	var context = ContextScript.new()
	context.attack_instance_id = begin_attack()
	context.target = target
	context.base_damage = damage
	context.snapshot_damage = damage
	context.armor_break = armor_break
	var result = resolve(context)
	close_attack(context.attack_instance_id)
	return result.delivered


static func resolve(context):
	var result = ResultScript.new()
	if context.trigger_depth > MAX_TRIGGER_DEPTH:
		result.blocked_recursion = true
		return result
	var target: Node = context.target
	if not _is_damage_target(target):
		return result
	if context.attack_instance_id <= 0:
		context.attack_instance_id = begin_attack()
	if _already_hit(context.attack_instance_id, target.get_instance_id()):
		result.duplicate_hit = true
		return result
	if context.source is Node2D and not has_line_of_sight(context.source, target):
		result.blocked_by_wall = true
		return result
	if target.has_method("accepts_hit") and not target.accepts_hit():
		result.rejected_invulnerable = true
		return result
	if context.attack_instance_id > 0 and not _attack_hits.has(context.attack_instance_id):
		_attack_hits[context.attack_instance_id] = {}
	var announced: Dictionary = _attack_hits[context.attack_instance_id]
	if not announced.has(&"started"):
		announced[&"started"] = true
		event_bus().attack_started.emit(context)
	var damage: int = context.snapshot_damage if context.snapshot_damage > 0 else context.base_damage
	var hp_before := int(target.hp)
	var broken_before := false
	if "broken" in target and target.broken:
		broken_before = true
	if target.has_method("receive_hit"):
		target.receive_hit(damage, context.armor_break)
	else:
		target.take_damage(damage)
	result.delivered = true
	if not is_instance_valid(target):
		result.damage_applied = hp_before
		result.killed = hp_before > 0
	else:
		result.damage_applied = maxi(0, hp_before - int(target.hp))
		result.killed = hp_before > 0 and int(target.hp) <= 0
		var broken_now := false
		if "broken" in target and target.broken:
			broken_now = true
		result.armor_broken = (not broken_before) and broken_now
	event_bus().damage_resolved.emit(result, context)
	if result.killed:
		event_bus().target_killed.emit(result, context)
	return result


static func _is_damage_target(target: Node) -> bool:
	return is_instance_valid(target) and not target.is_queued_for_deletion() \
		and target is Node2D and ("hp" in target) and int(target.hp) > 0 \
		and (target.has_method("take_damage") or target.has_method("receive_hit"))


static func _already_hit(attack_id: int, target_id: int) -> bool:
	if not _attack_hits.has(attack_id):
		_attack_hits[attack_id] = {}
	var seen: Dictionary = _attack_hits[attack_id]
	if seen.has(target_id):
		return true
	seen[target_id] = true
	return false
