class_name MeleeAttackVolume
extends RefCounted
## 把一份近战攻击数据采样成判定圆，并覆盖相邻采样之间的空隙。
## 采样间距不超过 MAX_SAMPLE_GAP，调试圈与命中查询使用同一批圆。

const MAX_SAMPLE_GAP := 12.0


static func body_radius(target: Node) -> float:
	if target is Node2D:
		var shape_node := target.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if shape_node != null and shape_node.shape is RectangleShape2D:
			var rect := shape_node.shape as RectangleShape2D
			return maxf(rect.size.x, rect.size.y) * 0.5
		if shape_node != null and shape_node.shape is CircleShape2D:
			return (shape_node.shape as CircleShape2D).radius
	return 12.0


static func sample_at(attack: MeleeAttackDefinition, origin: Vector2, aim: Vector2, t: float) -> Dictionary:
	var pose := _pose_at(attack, t)
	var facing := aim.normalized() if aim.length_squared() > 0.0001 else Vector2.RIGHT
	return {
		"center": origin + (pose.offset as Vector2).rotated(facing.angle()),
		"radius": float(pose.radius),
	}


static func samples_between(
	attack: MeleeAttackDefinition,
	origin_a: Vector2,
	origin_b: Vector2,
	aim: Vector2,
	t_a: float,
	t_b: float,
) -> Array:
	var start_t := minf(t_a, t_b)
	var end_t := maxf(t_a, t_b)
	var from := origin_a if t_a <= t_b else origin_b
	var to := origin_b if t_a <= t_b else origin_a
	if is_equal_approx(start_t, end_t) and from.distance_squared_to(to) <= 0.01:
		return [sample_at(attack, from, aim, start_t)]
	var length := _approx_length(attack, from, to, aim, start_t, end_t)
	var steps := clampi(ceili(length / MAX_SAMPLE_GAP), 1, 40)
	var result: Array = []
	for i in steps + 1:
		var u := float(i) / float(steps)
		result.append(sample_at(attack, from.lerp(to, u), aim, lerpf(start_t, end_t, u)))
	return result


static func overlaps(samples: Array, point: Vector2, point_radius: float) -> bool:
	for i in samples.size():
		var sample: Dictionary = samples[i]
		var radius := float(sample.radius)
		var center: Vector2 = sample.center
		if center.distance_to(point) <= radius + point_radius:
			return true
		if i + 1 < samples.size():
			var nxt: Dictionary = samples[i + 1]
			if _segment_hits(point, point_radius, center, radius, nxt.center, float(nxt.radius)):
				return true
	return false


static func _pose_at(attack: MeleeAttackDefinition, t: float) -> MeleeHitKeyframe:
	var frames: Array[MeleeHitKeyframe] = []
	for keyframe in attack.keyframes:
		if keyframe is MeleeHitKeyframe:
			frames.append(keyframe)
	frames.sort_custom(func(a: MeleeHitKeyframe, b: MeleeHitKeyframe) -> bool: return a.time < b.time)
	if frames.is_empty():
		var fallback := MeleeHitKeyframe.new()
		fallback.offset = Vector2(48, 0)
		fallback.radius = 18.0
		return fallback
	var clamped := clampf(t, 0.0, 1.0)
	if frames.size() == 1 or clamped <= frames[0].time:
		return frames[0]
	if clamped >= frames[-1].time:
		return frames[-1]
	for i in frames.size() - 1:
		var before := frames[i]
		var after := frames[i + 1]
		if clamped > after.time:
			continue
		var span := maxf(0.0001, after.time - before.time)
		var weight := (clamped - before.time) / span
		var posed := MeleeHitKeyframe.new()
		posed.time = clamped
		posed.offset = before.offset.lerp(after.offset, weight)
		posed.radius = lerpf(before.radius, after.radius, weight)
		return posed
	return frames[-1]


static func _approx_length(
	attack: MeleeAttackDefinition,
	origin_a: Vector2,
	origin_b: Vector2,
	aim: Vector2,
	t_a: float,
	t_b: float,
) -> float:
	var length := 0.0
	var previous: Vector2 = sample_at(attack, origin_a, aim, t_a).center
	for i in 8:
		var u := float(i + 1) / 8.0
		var center: Vector2 = sample_at(attack, origin_a.lerp(origin_b, u), aim, lerpf(t_a, t_b, u)).center
		length += previous.distance_to(center)
		previous = center
	return length


static func _segment_hits(
	point: Vector2,
	point_radius: float,
	from: Vector2,
	from_radius: float,
	to: Vector2,
	to_radius: float,
) -> bool:
	var segment := to - from
	var length_squared := segment.length_squared()
	var weight := 0.0 if length_squared <= 0.0001 else clampf((point - from).dot(segment) / length_squared, 0.0, 1.0)
	var closest := from + segment * weight
	return closest.distance_to(point) <= lerpf(from_radius, to_radius, weight) + point_radius
