class_name ItemDefinition
extends Resource
## 静态物品定义。持有数量由 ProgressState 管理，不写回此资源。

@export var item_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
