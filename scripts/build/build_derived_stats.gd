extends RefCounted
## 预览和自动攻击共用的派生。只读当前激活预设，不把旧样例模块算进来。

const Link := preload("res://scripts/items/weapon_effect_link.gd")
const AffixPool := preload("res://scripts/build/affix_pool.gd")
const Loadout := preload("res://scripts/build/build_loadout.gd")
const MIN_INTERVAL := 0.05
const MIN_RANGE := 1.0
const MIN_DAMAGE := 1


static func from_weapon(item_id: StringName) -> Dictionary:
	return apply(Link.combat_profile(item_id))


static func apply(base: Dictionary) -> Dictionary:
	var result := base.duplicate()
	var lines: PackedStringArray = PackedStringArray()
	var loadout = ProgressState.build_loadout
	var preset: Dictionary = loadout.active_preset()
	var core_id := String(preset.get("core", ""))
	var formed := core_id != "" and not loadout.instance(core_id).is_empty()
	result["formed"] = formed
	result["status"] = "已成型" if formed else "未成型"
	var tags := _weapon_tags(base)
	var mechanic := ""
	var echo_every := 0
	var echo_damage := 0
	var echo_range := 0.0
	var echo_delay := 0.0
	var armor_break := int(base.get("armor_break", 0))
	var shock_damage := 0
	var shock_range := 0.0
	var shield_amount := 0
	var shield_duration := 0.0
	var shield_cooldown := 0.0
	var shield_cap := 0
	var flat_damage := 0
	flat_damage += ProgressState.level_damage_bonus()
	if ProgressState.level_damage_bonus() > 0:
		lines.append("等级成长 +%d" % ProgressState.level_damage_bonus())
	var damage_percent := 0.0
	var interval_percent := 0.0
	var range_flat := 0.0
	var range_percent := 0.0
	var projectile_speed_percent := 0.0
	if not formed:
		lines.append("未成型：仍用基础武器，辅助不生效")
	else:
		var core_comp: Dictionary = loadout.definition(String(loadout.instance(core_id).get("definition_id", "")))
		mechanic = String(core_comp.get("mechanic", ""))
		echo_every = int(core_comp.get("echo_every", 0))
		echo_damage = int(core_comp.get("echo_damage", 0))
		echo_range = float(core_comp.get("echo_range", 0.0))
		echo_delay = float(core_comp.get("echo_delay", 0.0))
		armor_break += int(core_comp.get("armor_break", 0))
		shock_damage = int(core_comp.get("shock_damage", 0))
		shock_range = float(core_comp.get("shock_range", 0.0))
		shield_amount = int(core_comp.get("shield_amount", 0))
		shield_duration = float(core_comp.get("shield_duration", 0.0))
		shield_cooldown = float(core_comp.get("shield_cooldown", 0.0))
		shield_cap = int(core_comp.get("shield_cap", 0))
		for slot in ["core", "support_0", "support_1"]:
			var instance_id := String(preset.get(slot, ""))
			if instance_id == "":
				continue
			var inst: Dictionary = loadout.instance(instance_id)
			var comp: Dictionary = loadout.definition(String(inst.get("definition_id", "")))
			if comp.is_empty():
				lines.append("未知组件")
				continue
			var reason := _incompatible_reason(comp, tags, mechanic)
			if reason != "":
				lines.append("%s：%s" % [String(comp.get("name", "")), reason])
				continue
			flat_damage += int(comp.get("flat_damage", 0))
			var enhance_levels := maxi(0, int(inst.get("level", 1)) - 1)
			if enhance_levels > 0:
				flat_damage += enhance_levels * Loadout.ENHANCE_FLAT_DAMAGE
			damage_percent += float(comp.get("damage_percent", 0.0))
			interval_percent += float(comp.get("interval_percent", 0.0))
			range_flat += float(comp.get("range_flat", 0.0))
			range_percent += float(comp.get("range_percent", 0.0))
			projectile_speed_percent += float(comp.get("projectile_speed_percent", 0.0))
			echo_range += float(comp.get("echo_range_flat", 0.0))
			armor_break += int(comp.get("armor_break_flat", 0))
			shield_duration += float(comp.get("shield_duration_flat", 0.0))
			var affix_mods: Dictionary = AffixPool.mods_for(inst)
			flat_damage += int(affix_mods.get("flat_damage", 0))
			range_flat += float(affix_mods.get("range_flat", 0.0))
			interval_percent += float(affix_mods.get("interval_percent", 0.0))
			var affix_lines: PackedStringArray = affix_mods.get("lines", PackedStringArray())
			var bits := PackedStringArray()
			bits.append("%s 生效" % String(comp.get("name", "")))
			if enhance_levels > 0:
				bits.append("强化 +%d" % (enhance_levels * Loadout.ENHANCE_FLAT_DAMAGE))
			if not affix_lines.is_empty():
				bits.append(" / ".join(affix_lines))
			lines.append(" · ".join(bits))
	var base_damage := int(base.get("damage", 1))
	var scaled := float(base_damage + flat_damage) * (1.0 + damage_percent / 100.0)
	result["damage"] = maxi(MIN_DAMAGE, int(round(scaled)))
	var base_interval := float(base.get("interval", 0.5))
	result["interval"] = maxf(MIN_INTERVAL, base_interval * (1.0 + interval_percent / 100.0))
	var base_range := float(base.get("range", 78.0))
	result["range"] = maxf(MIN_RANGE, (base_range + range_flat) * (1.0 + range_percent / 100.0))
	var base_speed := float(base.get("projectile_speed", 0.0))
	if base_speed > 0.0:
		result["projectile_speed"] = maxf(1.0, base_speed * (1.0 + projectile_speed_percent / 100.0))
	else:
		result["projectile_speed"] = 0.0
	result["mechanic"] = mechanic
	result["echo_every"] = echo_every
	result["echo_damage"] = echo_damage
	result["echo_range"] = echo_range
	result["echo_delay"] = echo_delay
	result["armor_break"] = armor_break
	result["shock_damage"] = shock_damage
	result["shock_range"] = shock_range
	result["shield_amount"] = shield_amount
	result["shield_duration"] = shield_duration
	result["shield_cooldown"] = shield_cooldown
	result["shield_cap"] = shield_cap
	result["lines"] = lines
	var summary := "伤害 %d · 间隔 %.2f秒 · 范围 %.0f · 破甲 %d · %s" % [
		int(result["damage"]),
		float(result["interval"]),
		float(result["range"]),
		int(result["armor_break"]),
		String(base.get("style_name", "")),
	]
	if float(result.get("projectile_speed", 0.0)) > 0.0:
		summary += " · 弹速 %.0f" % float(result["projectile_speed"])
	result["summary"] = summary
	result["detail"] = result["status"] + "\n" + result["summary"] + "\n" + "\n".join(lines)
	return result


static func _weapon_tags(profile: Dictionary) -> PackedStringArray:
	var tags := PackedStringArray(["weapon"])
	var behavior := String(profile.get("behavior_id", ""))
	if behavior == "sector_sweep" or behavior == "area_strike":
		tags.append("melee")
	if behavior == "projectile":
		tags.append("projectile")
	return tags


static func _incompatible_reason(component: Dictionary, tags: PackedStringArray, mechanic: String) -> String:
	var required_mechanic := String(component.get("requires_mechanic", ""))
	if required_mechanic != "" and required_mechanic != mechanic:
		return "不适配，需要%s" % required_mechanic
	var required: Array = component.get("tags", [])
	for tag in required:
		if not tags.has(String(tag)):
			return "不适配，需要%s" % String(tag)
	return ""
