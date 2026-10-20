extends RefCounted
## 一次攻击打到某个目标时的固定来源。结算过程中不回头读物品表。

var attack_instance_id: int = 0
var source: Node = null
var snapshot_id: String = ""
var target: Node = null
var tags: PackedStringArray = PackedStringArray()
var base_damage: int = 0
var armor_break: int = 0
var origin_effect_id: String = ""
var trigger_depth: int = 0
var snapshot_damage: int = 0


func fork() -> RefCounted:
	var copy: RefCounted = get_script().new()
	copy.attack_instance_id = attack_instance_id
	copy.source = source
	copy.snapshot_id = snapshot_id
	copy.target = target
	copy.tags = tags.duplicate()
	copy.base_damage = base_damage
	copy.armor_break = armor_break
	copy.origin_effect_id = origin_effect_id
	copy.trigger_depth = trigger_depth
	copy.snapshot_damage = snapshot_damage
	return copy
