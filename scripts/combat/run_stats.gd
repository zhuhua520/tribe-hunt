extends Node
## 本次单人运行的观察统计。只活在当前竞技场，不写入存档。

const Targeting := preload("res://scripts/combat/combat_targeting.gd")
const SessionGains := preload("res://scripts/ui/session_gains.gd")

enum Outcome { ONGOING, VICTORY, DEFEAT, EXTRACTED }

var elapsed_seconds: float = 0.0
var kill_count: int = 0
var damage_taken: int = 0
var damage_dealt: int = 0
var outcome: Outcome = Outcome.ONGOING
var boar_active: bool = false
var boar_defeated: bool = false
var boar_encounter_seconds: float = 0.0

var _running: bool = true
var _boar_timing: bool = false


func _ready() -> void:
	add_to_group("run_stats")
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_signal("damage_taken"):
		player.damage_taken.connect(_on_damage_taken)
	var wave_manager := get_parent().get_node_or_null("WaveManager")
	if wave_manager != null:
		if wave_manager.has_signal("run_won"):
			wave_manager.run_won.connect(_on_run_won)
		if wave_manager.has_signal("run_lost"):
			wave_manager.run_lost.connect(_on_run_lost)
		if wave_manager.has_signal("run_extracted"):
			wave_manager.run_extracted.connect(_on_run_extracted)
		if wave_manager.has_signal("run_returned_to_village"):
			wave_manager.run_returned_to_village.connect(_on_run_extracted)
	print("Run stats begin elapsed=0 kills=0 damage_taken=0")
	var bus := Targeting.event_bus()
	if not bus.damage_resolved.is_connected(_on_damage_resolved):
		bus.damage_resolved.connect(_on_damage_resolved)


func _process(delta: float) -> void:
	# 默认跟随场景暂停：暂停菜单、撤离选择和波间构筑调整不计入用时。
	if _running:
		elapsed_seconds += delta
		if _boar_timing:
			boar_encounter_seconds += delta


func watch_enemy(enemy: Node) -> void:
	if enemy.has_signal("defeated") and not enemy.defeated.is_connected(_on_enemy_defeated):
		enemy.defeated.connect(_on_enemy_defeated)
	if enemy.is_in_group("boar_king") and enemy.has_signal("defeated") and not enemy.defeated.is_connected(_on_boar_defeated):
		enemy.defeated.connect(_on_boar_defeated)


func note_boar_started() -> void:
	if boar_active:
		return
	boar_active = true
	boar_defeated = false
	boar_encounter_seconds = 0.0
	_boar_timing = true
	print("Run stats boar start")


func summary_text() -> String:
	var text := "结局：%s\n用时 %.1f 秒\n击杀 %d\n受到伤害 %d" % [
		outcome_label(),
		elapsed_seconds,
		kill_count,
		damage_taken,
	]
	if boar_active:
		var boar_label := "已击败" if boar_defeated else "未击败"
		text += "\n野猪王：%s（遭遇 %.1f 秒）" % [boar_label, boar_encounter_seconds]
	text += "\n造成伤害 %d" % damage_dealt
	text += "\n%s" % SessionGains.mechanics_line()
	text += "\n本次收益：竞技场不发放"
	return text


func outcome_label() -> String:
	match outcome:
		Outcome.VICTORY:
			return "狩猎成功"
		Outcome.DEFEAT:
			return "狩猎失败"
		Outcome.EXTRACTED:
			return "撤离"
		_:
			return "进行中"


func _on_damage_resolved(result, context) -> void:
	if not _running or result.rejected_invulnerable or result.damage_applied <= 0:
		return
	var source: Node = context.source
	if source != null and is_instance_valid(source) and source.is_in_group("player"):
		damage_dealt += result.damage_applied


func _on_damage_taken(amount: int) -> void:
	if not _running or amount <= 0:
		return
	damage_taken += amount


func _on_enemy_defeated() -> void:
	if not _running:
		return
	kill_count += 1


func _on_boar_defeated() -> void:
	boar_defeated = true
	_boar_timing = false


func _on_run_won() -> void:
	_finish(Outcome.VICTORY)


func _on_run_lost() -> void:
	_finish(Outcome.DEFEAT)


func _on_run_extracted() -> void:
	_finish(Outcome.EXTRACTED)


func _finish(next: Outcome) -> void:
	if not _running:
		return
	_running = false
	outcome = next
	print(
		"Run stats outcome=%s elapsed=%.1f kills=%d damage_taken=%d boar_active=%s boar_defeated=%s boar_seconds=%.1f"
		% [
			_outcome_id(next),
			elapsed_seconds,
			kill_count,
			damage_taken,
			boar_active,
			boar_defeated,
			boar_encounter_seconds,
		]
	)


func _outcome_id(next: Outcome) -> String:
	match next:
		Outcome.VICTORY:
			return "victory"
		Outcome.DEFEAT:
			return "defeat"
		Outcome.EXTRACTED:
			return "extracted"
		_:
			return "ongoing"
