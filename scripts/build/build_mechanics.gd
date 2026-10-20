extends Node
## 听真实结算事件。回响不把自己再算成基础命中；破阵只在破甲从无到有时冲击一次。

const Derived := preload("res://scripts/build/build_derived_stats.gd")
const Targeting := preload("res://scripts/combat/combat_targeting.gd")
const Volume := preload("res://scripts/combat/melee_attack_volume.gd")
const ContextScript := preload("res://scripts/combat/hit_context.gd")
const PULSE_SCENE := preload("res://scenes/combat/build_pulse.tscn")

var basic_hits: int = 0
var echo_progress: int = 0
var echo_triggers: int = 0
var break_triggers: int = 0
var basic_damage: int = 0
var mechanic_damage: int = 0
var core_title: String = "无核心"
var progress_text: String = "—"
var detail_text: String = "未成型"
var stats_text: String = "触发 0 · 来源伤害 0 · 机制伤害 0"


func _ready() -> void:
	var bus = Targeting.event_bus()
	if not bus.damage_resolved.is_connected(_on_damage):
		bus.damage_resolved.connect(_on_damage)
	if not bus.target_killed.is_connected(_on_killed):
		bus.target_killed.connect(_on_killed)
	if not ProgressState.build_loadout.changed.is_connected(_on_loadout_changed):
		ProgressState.build_loadout.changed.connect(_on_loadout_changed)
	_refresh_text()


var _shield_cooldown_left: float = 0.0
var _watched_scene: Node
var gain_text: String = ""


func _process(delta: float) -> void:
	var scene := get_tree().current_scene
	if scene != _watched_scene:
		if _watched_scene != null:
			_shield_cooldown_left = 0.0
		_watched_scene = scene
	_shield_cooldown_left = maxf(0.0, _shield_cooldown_left - delta)
	if gain_text != "":
		_refresh_text()


func reset_counts() -> void:
	basic_hits = 0
	echo_progress = 0
	echo_triggers = 0
	break_triggers = 0
	basic_damage = 0
	mechanic_damage = 0
	_refresh_text()


func _on_loadout_changed() -> void:
	echo_progress = 0
	_refresh_text()


func _on_damage(result, context) -> void:
	var origin := String(context.origin_effect_id)
	if origin == "enemy_shot" or origin == "enemy_pounce":
		return
	var source = context.source
	if source != null and is_instance_valid(source) and source.is_in_group("enemies"):
		return
	if origin == "echo" or origin == "shock":
		if result.damage_applied > 0:
			mechanic_damage += result.damage_applied
			_refresh_text()
		return
	if origin == "projectile_extra":
		if result.damage_applied > 0:
			basic_damage += result.damage_applied
			_refresh_text()
		return
	if result.rejected_invulnerable or result.blocked_by_wall or result.duplicate_hit or result.blocked_recursion:
		return
	if result.damage_applied > 0:
		basic_hits += 1
		basic_damage += result.damage_applied
		_count_echo()
	if result.armor_broken:
		_shock(context)
	_refresh_text()


func _on_killed(result, context) -> void:
	if result.killed != true:
		return
	var source = context.source
	if source == null or not is_instance_valid(source) or not source.is_in_group("player"):
		return
	if not ("shield_hp" in source):
		return
	var profile: Dictionary = Derived.from_weapon(ProgressState.equipped_weapon_id())
	if String(profile.get("mechanic", "")) != "hunt":
		return
	if _shield_cooldown_left > 0.0:
		return
	var amount := int(profile.get("shield_amount", 0))
	var cap := maxi(amount, int(profile.get("shield_cap", amount)))
	source.shield_hp = mini(cap, amount)
	source.shield_left = float(profile.get("shield_duration", 0.0))
	_shield_cooldown_left = float(profile.get("shield_cooldown", 0.0))
	gain_text = "猎获：获得护盾 %d，持续 %.0f 秒" % [source.shield_hp, source.shield_left]
	_refresh_text()


func _count_echo() -> void:
	var profile: Dictionary = Derived.from_weapon(ProgressState.equipped_weapon_id())
	if String(profile.get("mechanic", "")) != "echo":
		return
	var every := maxi(1, int(profile.get("echo_every", 3)))
	echo_progress += 1
	if echo_progress < every:
		return
	echo_progress = 0
	var origin := _player_position()
	var damage := int(profile.get("echo_damage", 1))
	var radius := float(profile.get("echo_range", 40.0))
	var delay := float(profile.get("echo_delay", 0.2))
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		_emit_pulse(origin, damage, radius, "echo", Color(0.45, 0.82, 1.0, 0.9))
	)


func _shock(context) -> void:
	var profile: Dictionary = Derived.from_weapon(ProgressState.equipped_weapon_id())
	if String(profile.get("mechanic", "")) != "armor_break":
		return
	var target = context.target
	if target == null or not is_instance_valid(target) or not ("broken" in target):
		return
	var origin: Vector2 = target.global_position
	_emit_pulse(origin, int(profile.get("shock_damage", 1)), float(profile.get("shock_range", 48.0)), "shock", Color(0.95, 0.55, 0.2, 0.9))


func _emit_pulse(origin: Vector2, damage: int, radius: float, effect_id: String, color: Color) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var pulse = PULSE_SCENE.instantiate()
	scene.add_child(pulse)
	pulse.global_position = origin
	pulse.radius = radius
	pulse.color = color
	if effect_id == "echo":
		echo_triggers += 1
	else:
		break_triggers += 1
	var attack_id := Targeting.begin_attack()
	var player := get_tree().get_first_node_in_group("player")
	for candidate in get_tree().get_nodes_in_group("enemies"):
		if not Targeting.is_live_target(candidate):
			continue
		if origin.distance_to(candidate.global_position) > radius + Volume.body_radius(candidate):
			continue
		if _wall_between(scene, origin, candidate):
			continue
		var hit_context = ContextScript.new()
		hit_context.attack_instance_id = attack_id
		hit_context.source = player
		hit_context.target = candidate
		hit_context.snapshot_damage = damage
		hit_context.base_damage = damage
		hit_context.origin_effect_id = effect_id
		hit_context.trigger_depth = 1
		Targeting.resolve(hit_context)
	Targeting.close_attack(attack_id)
	_refresh_text()


func _wall_between(scene: Node, origin: Vector2, target: Node2D) -> bool:
	var world: World2D = scene.get_world_2d()
	if world == null:
		return false
	var query := PhysicsRayQueryParameters2D.create(origin, target.global_position, Targeting.TERRAIN_LAYER)
	return not world.direct_space_state.intersect_ray(query).is_empty()


func _player_position() -> Vector2:
	var player := get_tree().get_first_node_in_group("player")
	if player is Node2D:
		return player.global_position
	return Vector2.ZERO


func _refresh_text() -> void:
	var profile: Dictionary = Derived.from_weapon(ProgressState.equipped_weapon_id())
	var mechanic := String(profile.get("mechanic", ""))
	if mechanic == "echo":
		core_title = "◎ 回响"
		progress_text = "回响 %d/%d" % [echo_progress, int(profile.get("echo_every", 3))]
		detail_text = "每 %d 次有效命中，延迟 %.2f 秒，范围 %.0f\n标签：weapon" % [
			int(profile.get("echo_every", 3)),
			float(profile.get("echo_delay", 0.2)),
			float(profile.get("echo_range", 40.0)),
		]
	elif mechanic == "armor_break":
		core_title = "▣ 破阵"
		progress_text = "破甲冲击 %d 次" % break_triggers
		detail_text = "基础攻击破甲 %d。破甲开始时冲击一次，范围 %.0f\n标签：weapon" % [
			int(profile.get("armor_break", 0)),
			float(profile.get("shock_range", 48.0)),
		]
	elif mechanic == "hunt":
		core_title = "◇ 猎获"
		progress_text = "护盾冷却 %.1f 秒" % _shield_cooldown_left
		detail_text = "击杀获得护盾 %d，上限 %d，持续 %.0f 秒\n标签：weapon" % [
			int(profile.get("shield_amount", 0)),
			int(profile.get("shield_cap", 0)),
			float(profile.get("shield_duration", 0.0)),
		]
		if gain_text != "":
			detail_text += "\n" + gain_text
	else:
		core_title = "无核心"
		progress_text = "—"
		detail_text = "未成型" if profile.get("formed") != true else "当前核心没有触发机制"
	stats_text = "触发 %d · 来源伤害 %d · 机制伤害 %d" % [echo_triggers + break_triggers, basic_damage, mechanic_damage]
