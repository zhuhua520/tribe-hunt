extends CanvasLayer
## 战斗里显示生命、武器、区域、当前核心、触发进度和伤害来源。控件都在场景里。

const RegionCatalog := preload("res://scripts/exploration/region_catalog.gd")
const Link := preload("res://scripts/items/weapon_effect_link.gd")

@onready var _vital_label: Label = $Panel/VitalLabel
@onready var _weapon_label: Label = $Panel/WeaponLabel
@onready var _region_label: Label = $Panel/RegionLabel
@onready var _core_label: Label = $Panel/CoreLabel
@onready var _progress_label: Label = $Panel/ProgressLabel
@onready var _detail_label: Label = $Panel/DetailLabel
@onready var _stats_label: Label = $Panel/StatsLabel
@onready var _reload_label: Label = $Panel/ReloadLabel
@onready var _reload_bar: ProgressBar = $Panel/ReloadBar


func _ready() -> void:
	if not ProgressState.build_loadout.changed.is_connected(_sync):
		ProgressState.build_loadout.changed.connect(_sync)
	_sync()


func _process(_delta: float) -> void:
	_sync()


func vital_text() -> String:
	return _vital_label.text


func weapon_text() -> String:
	return _weapon_label.text


func region_text() -> String:
	return _region_label.text


func _sync() -> void:
	_update_context()
	var mechanics := ProgressState.get_node_or_null("BuildMechanics")
	if mechanics != null:
		_core_label.text = mechanics.core_title
		_progress_label.text = mechanics.progress_text
		_detail_label.text = mechanics.detail_text
		_stats_label.text = mechanics.stats_text
	var profile: Dictionary = preload("res://scripts/build/build_derived_stats.gd").from_weapon(ProgressState.equipped_weapon_id())
	var reloading: bool = profile.get("reload", false) == true
	_reload_label.visible = reloading
	_reload_bar.visible = reloading
	if not reloading:
		return
	var interval := maxf(0.05, float(profile.get("interval", 1.0)))
	var left := clampf(ProgressState.attack_cooldown_left, 0.0, interval)
	_reload_bar.value = left / interval
	_reload_label.text = "装填 %.2f秒" % left if left > 0.0 else "装填完成"


func _update_context() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player != null and "hp" in player and "max_hp" in player:
		var shield := int(player.shield_hp) if "shield_hp" in player else 0
		if shield > 0:
			_vital_label.text = "生命 %d/%d · 护盾 %d" % [int(player.hp), int(player.max_hp), shield]
		else:
			_vital_label.text = "生命 %d/%d" % [int(player.hp), int(player.max_hp)]
	else:
		_vital_label.text = "生命 —"
	var weapon: Dictionary = Link.combat_profile(ProgressState.equipped_weapon_id())
	var cooldown := maxf(0.0, ProgressState.attack_cooldown_left)
	_weapon_label.text = "%s · 冷却 %.2f秒" % [String(weapon.get("display_name", "无武器")), cooldown]
	var scene := get_tree().current_scene
	var path := scene.scene_file_path if scene != null else ""
	_region_label.text = "区域：%s" % RegionCatalog.display_name_for_scene(path)
