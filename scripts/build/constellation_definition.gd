class_name ConstellationDefinition
extends Resource
## 静态星宿定义。保留内部类名和字段兼容已有资源。

@export var constellation_id: String = ""
@export var display_name: String = ""
@export var celestial_quadrant: String = "北方玄武"
@export_multiline var description: String = ""
@export var star_point_ids: PackedStringArray = PackedStringArray()
## 套装门槛与奖励占位。空字符串表示尚未定义，不代表任何件数会触发。
@export var set_bonus_placeholder: String = ""
## 完整收集奖励占位。空字符串表示尚未定义。
@export var completion_reward_placeholder: String = ""
