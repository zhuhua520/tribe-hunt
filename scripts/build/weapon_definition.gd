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
@export var attack_style: AttackStyle = AttackStyle.MELEE
## 一般适配用的武器类别标签，不是槽位规则。
@export var category_tag: String = ""
@export var category_label: String = ""
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
