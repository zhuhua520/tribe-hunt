extends RefCounted
## 本场探索收益。只活在当前场景，不写存档。

var items: Dictionary = {}


func add(item_id: StringName, amount: int) -> void:
	if amount <= 0:
		return
	var key := String(item_id)
	items[key] = int(items.get(key, 0)) + amount


func summary_text() -> String:
	var lines := PackedStringArray()
	lines.append(_gains_line())
	lines.append(mechanics_line())
	return "\n".join(lines)


func _gains_line() -> String:
	if items.is_empty():
		return "本次收益：无"
	var parts := PackedStringArray()
	var keys: Array = items.keys()
	keys.sort()
	for key in keys:
		var definition := ProgressState.get_definition(StringName(String(key)))
		var item_name := definition.display_name if definition != null else String(key)
		parts.append("%s ×%d" % [item_name, int(items[key])])
	return "本次收益：%s" % "、".join(parts)


static func mechanics_line() -> String:
	var mechanics := ProgressState.get_node_or_null("BuildMechanics")
	if mechanics == null:
		return "来源伤害 0 · 机制伤害 0 · 核心触发 0"
	return "来源伤害 %d · 机制伤害 %d · 核心触发 %d" % [
		int(mechanics.basic_damage),
		int(mechanics.mechanic_damage),
		int(mechanics.echo_triggers) + int(mechanics.break_triggers),
	]
