class_name WeaponDefinition
extends Resource
## 静态武器定义。运行时装备与强化不得写回本资源。

enum AttackStyle {
	MELEE,
	RANGED,
}

## 品质五档只占位。样例保持 UNSET，不据此改变战斗。
enum QualityTier {
	UNSET,
	LOWEST,
	LOW,
	MID,
	HIGH,
	HIGHEST,
}

## 稀有度五档只占位。样例只用简陋和普通两档做识别，不实现其余档的行为。
enum RarityTier {
	CRUDE,
	COMMON,
	ADVANCED,
	ARTIFACT,
	EPIC,
}

@export var weapon_id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export_range(1.0, 2000.0) var projectile_speed: float = 420.0
@export_range(0.1, 10.0) var projectile_lifetime: float = 2.0
@export var attack_style: AttackStyle = AttackStyle.MELEE
## 一般适配用的武器类别标签，不是槽位规则。
@export var category_tag: String = ""
@export var category_label: String = ""
## 当前单人原型的基础战斗值；与品质、成长占位无关。
@export_range(1, 999) var damage: int = 1
@export_range(1.0, 2000.0) var attack_range: float = 72.0
@export_range(0.05, 10.0) var cooldown: float = 0.45
@export_range(0.0, 1.0) var windup_seconds: float = 0.06
@export_range(0.01, 1.0) var swing_seconds: float = 0.12
@export var quality: QualityTier = QualityTier.UNSET
@export var rarity: RarityTier = RarityTier.CRUDE
## 属性加成占位。空字典表示数值未定，预览不应用。
@export var stat_bonus_placeholders: Dictionary = {}
## 固有属性占位，例如钝器、弓类等方向尚未定效果。
@export var inherent_trait_id: String = ""
## 武器专属特效占位。空字符串表示未定义效果。
@export var unique_effect_id: String = ""
## 强化上限占位。-1 表示未定，不是“不可强化”或“无上限”。
@export var upgrade_cap: int = -1
## 掉落权重占位。-1 表示未定，不参与掉落。
@export var drop_weight: int = -1


func attack_style_label() -> String:
	match attack_style:
		AttackStyle.MELEE:
			return "近战"
		AttackStyle.RANGED:
			return "远程"
		_:
			return "未定"


func combat_summary() -> String:
	var result := "伤害 %d · 间隔 %.2f秒 · 范围 %.0f" % [damage, cooldown, attack_range]
	if attack_style == AttackStyle.MELEE:
		result += " · 前摇 %.2f秒 · 收招 %.2f秒" % [windup_seconds, swing_seconds]
	else:
		result += " · 弹速 %.0f · 存续 %.1f秒" % [projectile_speed, projectile_lifetime]
	return result


func quality_label() -> String:
	match quality:
		QualityTier.UNSET:
			return "未定"
		QualityTier.LOWEST:
			return "最下级"
		QualityTier.LOW:
			return "下级"
		QualityTier.MID:
			return "中级"
		QualityTier.HIGH:
			return "上级"
		QualityTier.HIGHEST:
			return "最上级"
		_:
			return "未定"


func rarity_label() -> String:
	match rarity:
		RarityTier.CRUDE:
			return "简陋"
		RarityTier.COMMON:
			return "普通"
		RarityTier.ADVANCED:
			return "高级"
		RarityTier.ARTIFACT:
			return "神器"
		RarityTier.EPIC:
			return "史诗"
		_:
			return "未定"
