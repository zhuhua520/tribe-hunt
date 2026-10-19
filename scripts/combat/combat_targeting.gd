extends RefCounted
## 单人武器共用的目标与伤害入口，不保存全局玩家或可变 Resource。

const TERRAIN_LAYER := 16


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
			in_range.append([distance, candidate])
	in_range.sort_custom(func(a, b): return a[0] < b[0])
	for entry in in_range:
		if has_line_of_sight(source, entry[1]):
			return entry[1]
	return null


static func has_line_of_sight(source: Node2D, target: Node2D) -> bool:
	var space := source.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(source.global_position, target.global_position, TERRAIN_LAYER)
	return space.intersect_ray(query).is_empty()


static func hit(target: Node, damage: int) -> bool:
	if damage <= 0 or not is_live_target(target):
		return false
	target.take_damage(damage)
	return true
