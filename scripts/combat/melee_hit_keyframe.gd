class_name MeleeHitKeyframe
extends Resource
## 近战生效阶段的一个采样姿态。time 为 0–1；offset 以瞄准方向为 +X；radius 为判定圆半径。测试值。

@export_range(0.0, 1.0, 0.01) var time: float = 0.0
@export var offset: Vector2 = Vector2(48, 0)
@export_range(1.0, 240.0, 1.0) var radius: float = 18.0
