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
