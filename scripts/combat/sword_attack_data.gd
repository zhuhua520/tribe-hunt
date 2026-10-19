extends RefCounted
## 剑的测试动作数据。改这里的时长和关键帧，不必改扫掠或连击状态机。数值不是最终手感。

const WEAPON := preload("res://data/build/weapon_sword.tres")

## 后摇走过这个比例之后，才允许闪避取消。前摇和生效始终不可取消。
const RECOVERY_DODGE_OPEN_RATIO := 0.4
## 按住攻击超过这个时间进入蓄力；短按仍是连击。点按在松手时出手。
const CHARGE_THRESHOLD_SECONDS := 0.28
const CHARGE_MOVE_SCALE := 0.45


static func weapon() -> WeaponDefinition:
	return WEAPON


static func combo_attacks() -> Array[MeleeAttackDefinition]:
	return [
		_slash("sword_slash_1", 0.12, 0.08, 0.22, 1.0, [Vector2(44, -34), Vector2(44, 34)], 20.0),
		_slash("sword_slash_2", 0.10, 0.08, 0.20, 1.0, [Vector2(46, 36), Vector2(46, -36)], 20.0),
		_slash("sword_slash_3", 0.14, 0.10, 0.26, 1.0, [Vector2(38, -30), Vector2(64, 0), Vector2(38, 30)], 22.0),
	]


static func charged_attack() -> MeleeAttackDefinition:
	return _slash("sword_charge", 0.06, 0.12, 0.32, 2.0, [Vector2(40, -50), Vector2(48, 0), Vector2(40, 50)], 26.0)


static func _slash(
	attack_id: String,
	windup: float,
	active: float,
	recovery: float,
	multiplier: float,
	offsets: Array,
	radius: float,
) -> MeleeAttackDefinition:
	var attack := MeleeAttackDefinition.new()
	attack.attack_id = attack_id
	attack.windup_seconds = windup
	attack.active_seconds = active
	attack.recovery_seconds = recovery
	attack.damage_multiplier = multiplier
	attack.armor_break = 1
	var frames: Array[MeleeHitKeyframe] = []
	for i in offsets.size():
		var keyframe := MeleeHitKeyframe.new()
		keyframe.time = 0.0 if offsets.size() <= 1 else float(i) / float(offsets.size() - 1)
		keyframe.offset = offsets[i]
		keyframe.radius = radius
		frames.append(keyframe)
	attack.keyframes = frames
	return attack
