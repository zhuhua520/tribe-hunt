class_name ConstellationDefinition
extends Resource
## 静态星座定义。已发现星点和当前装备件数都由运行时状态计算。

@export var constellation_id: String = ""
@export var display_name: String = ""
@export var star_point_ids: PackedStringArray = PackedStringArray()
## 套装门槛与奖励占位。空字符串表示尚未定义，不代表任何件数会触发。
@export var set_bonus_placeholder: String = ""
## 完整收集奖励占位。空字符串表示尚未定义。
@export var completion_reward_placeholder: String = ""
