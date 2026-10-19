class_name AppearanceLayer
extends Resource
## 只描述外观，不决定装备槽上限、属性或掉落规则。

@export var item_id: String = ""
@export var layer_id: String = ""
@export var profile_id: String = "ninja_preview_v1"
@export var texture: Texture2D
@export var tint: Color = Color.WHITE
@export var draw_order: int = 1
## 可按方向改变遮挡顺序，例如背面武器。
@export var direction_orders: Dictionary = {}
