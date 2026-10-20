extends RefCounted
## 一次结算的结果。无敌、被墙挡住或超过触发深度时，实际伤害为 0。

var damage_applied: int = 0
var rejected_invulnerable: bool = false
var blocked_by_wall: bool = false
var blocked_recursion: bool = false
var duplicate_hit: bool = false
var armor_broken: bool = false
var killed: bool = false
var delivered: bool = false
