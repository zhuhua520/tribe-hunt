extends Node
## 单人远征中的临时构筑状态。只在本次运行内生效，不保存到玩家进度。

signal loadout_changed

const CATALOG_PATH := "res://data/build/sample_catalog.tres"
const EXTRACTION_EVERY_WAVE := 1
const EXTRACTION_EVERY_TWO_WAVES := 2

var prepared_module_ids: Array[String] = []
## 本次运行的撤离对照间隔。1 为每波，2 为每两波。不是最终节奏，也不写入存档。
var extraction_wave_interval: int = EXTRACTION_EVERY_WAVE
var _equipped_module_ids: Array[String] = []
var _modules: Array[ModuleDefinition] = []


func _ready() -> void:
	var catalog := load(CATALOG_PATH) as BuildCatalog
	if catalog == null:
		push_error("BuildRunService: 无法加载样例目录 %s" % CATALOG_PATH)
		return
	for module in catalog.modules:
		_modules.append(module)


func get_module_definitions() -> Array[ModuleDefinition]:
	return _modules


func get_module(module_id: String) -> ModuleDefinition:
	for module in _modules:
		if module.module_id == module_id:
			return module
	return null


func set_extraction_wave_interval(interval: int) -> void:
	if interval == EXTRACTION_EVERY_TWO_WAVES:
		extraction_wave_interval = EXTRACTION_EVERY_TWO_WAVES
	else:
		extraction_wave_interval = EXTRACTION_EVERY_WAVE


func set_prepared_module_ids(module_ids: Array[String]) -> void:
	prepared_module_ids = _valid_unique_ids(module_ids)
	loadout_changed.emit()


func begin_run() -> void:
	_equipped_module_ids = _copy_ids(prepared_module_ids)
	loadout_changed.emit()


func set_equipped_module_ids(module_ids: Array[String]) -> void:
	_equipped_module_ids = _valid_unique_ids(module_ids)
	loadout_changed.emit()


func is_prepared(module_id: String) -> bool:
	return prepared_module_ids.has(module_id)


func is_equipped(module_id: String) -> bool:
	return _equipped_module_ids.has(module_id)


func current_equipped_module_ids() -> Array[String]:
	return _copy_ids(_equipped_module_ids)


func get_effective_cooldown(base_cooldown: float, weapon_category: String) -> float:
	var attack_speed_bonus := _sum_effect_percent(
		weapon_category, ModuleDefinition.PrototypeEffect.ATTACK_SPEED_PERCENT
	)
	var speed_multiplier := maxf(0.1, 1.0 + attack_speed_bonus / 100.0)
	return maxf(0.05, base_cooldown / speed_multiplier)


func get_effective_attack_range(base_range: float, weapon_category: String) -> float:
	var range_bonus := _sum_effect_percent(
		weapon_category, ModuleDefinition.PrototypeEffect.ATTACK_RANGE_PERCENT
	)
	return maxf(1.0, base_range * (1.0 + range_bonus / 100.0))


func active_summary() -> String:
	var labels := PackedStringArray()
	for module in _modules:
		if _equipped_module_ids.has(module.module_id):
			labels.append("%s（%s）" % [module.display_name, module.prototype_effect_label()])
	if labels.is_empty():
		return "当前构筑：无模块"
	return "当前构筑：" + "、".join(labels)


func _sum_effect_percent(
	weapon_category: String, effect: int
) -> float:
	var total := 0.0
	for module in _modules:
		if not _equipped_module_ids.has(module.module_id):
			continue
		if module.weapon_category_tag != weapon_category:
			continue
		if module.prototype_effect == effect:
			total += module.prototype_effect_percent
	return total


func _valid_unique_ids(module_ids: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for module_id in module_ids:
		if get_module(module_id) == null or result.has(module_id):
			continue
		result.append(module_id)
	return result


func _copy_ids(module_ids: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for module_id in module_ids:
		result.append(module_id)
	return result
