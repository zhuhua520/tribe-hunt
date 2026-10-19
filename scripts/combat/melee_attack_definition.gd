class_name MeleeAttackDefinition
extends Resource
## 一次近战攻击实例的数据。连击的每一段、蓄力斩各用一份，不写运行时命中记录。

@export var attack_id: String = ""
@export_range(0.0, 2.0, 0.01) var windup_seconds: float = 0.12
@export_range(0.01, 2.0, 0.01) var active_seconds: float = 0.08
@export_range(0.0, 2.0, 0.01) var recovery_seconds: float = 0.22
## 乘在 WeaponDefinition 伤害上。普通段为 1，蓄力斩单独提高。测试值，不是最终平衡。
@export_range(0.1, 10.0, 0.1) var damage_multiplier: float = 1.0
## 命中装甲目标时增加的破甲值。测试值，不是最终平衡。无甲目标忽略它。
@export_range(0, 99, 1) var armor_break: int = 1
@export var keyframes: Array[MeleeHitKeyframe] = []
