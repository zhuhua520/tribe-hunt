class_name WeaponEffectLink
extends RefCounted
## 武器物品指向特效表。具体剑不在武器脚本里写死攻击方式。

const Catalog := preload("res://scripts/items/item_catalog.gd")


static func resolve(item_id: StringName) -> Dictionary:
	var item: Dictionary = Catalog.get_item(item_id)
	if item.is_empty() or String(item.get("category_id", "")) != "weapon":
		return {}
	return Catalog.get_effect(String(item.get("effect_id", "")))


static func attack_style(item_id: StringName) -> String:
	return String(resolve(item_id).get("attack_style", ""))


## 正式自动攻击和装备面板共用这一份。伤害来自物品表，间隔和范围来自特效表。
static func combat_profile(item_id: StringName) -> Dictionary:
	var resolved_id := item_id
	var item: Dictionary = Catalog.get_item(resolved_id)
	var effect: Dictionary = resolve(resolved_id)
	if item.is_empty() or effect.is_empty():
		resolved_id = &"sword_training"
		item = Catalog.get_item(resolved_id)
		effect = resolve(resolved_id)
	var behavior := String(effect.get("behavior_id", "sector_sweep"))
	if behavior != "sector_sweep" and behavior != "area_strike" and behavior != "projectile":
		behavior = "sector_sweep"
	var damage := int(item.get("attack", 1))
	if damage < 1:
		damage = 1
	var interval := maxf(0.05, float(effect.get("interval", 0.5)))
	var reach := maxf(1.0, float(effect.get("range", 78.0)))
	var arc := clampf(float(effect.get("arc_degrees", 110.0)), 1.0, 360.0)
	var armor_break := maxi(0, int(effect.get("armor_break", 0)))
	var projectile_speed := maxf(0.0, float(effect.get("projectile_speed", 0.0)))
	var lifetime := maxf(0.05, float(effect.get("lifetime", 1.4)))
	var pierce_count := maxi(1, int(effect.get("pierce_count", 1)))
	var falloff := clampf(float(effect.get("damage_falloff", 1.0)), 0.05, 1.0)
	var reload: bool = effect.get("reload", false) == true
	var style_name := String(effect.get("name", behavior))
	var summary := "伤害 %d · 间隔 %.2f秒 · 范围 %.0f · 破甲 %d · %s" % [damage, interval, reach, armor_break, style_name]
	if behavior == "projectile":
		summary += " · 弹速 %.0f" % projectile_speed
	if reload:
		summary += " · 装填 %.2f秒" % interval
	if pierce_count > 1:
		summary += " · 穿透 %d" % pierce_count
	return {
		"item_id": resolved_id,
		"display_name": String(item.get("name", "试验短剑")),
		"damage": damage,
		"interval": interval,
		"range": reach,
		"arc_degrees": arc,
		"armor_break": armor_break,
		"projectile_speed": projectile_speed,
		"lifetime": lifetime,
		"pierce_count": pierce_count,
		"damage_falloff": falloff,
		"reload": reload,
		"behavior_id": behavior,
		"style_name": style_name,
		"attack_style": String(effect.get("attack_style", "")),
		"summary": summary,
	}
