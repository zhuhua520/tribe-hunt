class_name ModuleDefinition
extends Resource
## 静态模块定义。当前强化等级只存在运行时实例上，不写在这里。

## 只预留已确认的两类位置，不扩展更多类别。
enum ModuleCategory {
	SHARD,
	LARGE_SHARD,
}

## 最小原型只有无属性。不计算元素占比或元素效果。
enum ElementKind {
	NONE,
}

## 只供阶段 3.2 的少量战斗样例使用，不代表最终效果词条集合。
enum PrototypeEffect {
	NONE,
	ATTACK_SPEED_PERCENT,
	ATTACK_RANGE_PERCENT,
}

@export var module_id: String = ""
@export var display_name: String = ""
@export var category: ModuleCategory = ModuleCategory.SHARD
## 获得时的基础档位。不是玩家后来的强化等级。
@export var initial_star: int = 1
## 稳定星点 ID。收集完成度按这个 ID 去重。
@export var star_point_id: String = ""
@export var constellation_id: String = ""
## 一般适配用的武器类别标签。样例不绑定唯一武器。
@export var weapon_category_tag: String = ""
@export var weapon_category_label: String = ""
## 专属武器适配占位。空字符串表示这份样例不是专属模块。
@export var exclusive_weapon_id: String = ""
@export var element_kind: ElementKind = ElementKind.NONE
## 元素值占位。无属性样例保持 0，预览不应用。
@export var element_value: int = 0
## 属性加成占位。空字典表示数值未定，预览不应用。
@export var stat_bonus_placeholders: Dictionary = {}
## 特殊属性词条占位。空字符串表示未定义效果。
@export var special_affix_id: String = ""
## 阶段 3.2 的临时战斗效果。样例值用于原型对照，不是最终平衡数值。
@export var prototype_effect: PrototypeEffect = PrototypeEffect.NONE
@export var prototype_effect_percent: float = 0.0


func category_label() -> String:
	match category:
		ModuleCategory.SHARD:
			return "碎片"
		ModuleCategory.LARGE_SHARD:
			return "大碎片"
		_:
			return "未定"


func element_label() -> String:
	return "无属性"


func prototype_effect_label() -> String:
	var value_text := str(roundi(prototype_effect_percent)) + "%"
	match prototype_effect:
		PrototypeEffect.ATTACK_SPEED_PERCENT:
			return "%s 攻击速度 +%s" % [weapon_category_label, value_text]
		PrototypeEffect.ATTACK_RANGE_PERCENT:
			return "%s 攻击范围 +%s" % [weapon_category_label, value_text]
		_:
			return "无战斗效果"
