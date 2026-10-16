class_name BuildProbeState
extends RefCounted
## 预览用的本次运行状态。不写入存档，也不修改共享定义资源。
## 装备列表没有槽位上限。重复添加同一模块只为核对件数，不表示已经允许同时装备。

var _discovered_star_ids: Dictionary = {}
var _equipped: Array[ProbeInstance] = []
var _next_instance_number: int = 1


func discover_star(star_point_id: String) -> bool:
	if star_point_id.is_empty():
		return false
	if _discovered_star_ids.has(star_point_id):
		return false
	_discovered_star_ids[star_point_id] = true
	return true


func has_discovered(star_point_id: String) -> bool:
	return _discovered_star_ids.has(star_point_id)


func equip(module_id: String) -> String:
	var instance := ProbeInstance.new()
	instance.instance_id = "probe_%d" % _next_instance_number
	_next_instance_number += 1
	instance.module_id = module_id
	instance.upgrade_level = 0
	_equipped.append(instance)
	return instance.instance_id


func unequip_one(module_id: String) -> bool:
	for index in range(_equipped.size() - 1, -1, -1):
		var instance: ProbeInstance = _equipped[index]
		if instance.module_id == module_id:
			_equipped.remove_at(index)
			return true
	return false


func raise_upgrade(module_id: String) -> int:
	for index in range(_equipped.size() - 1, -1, -1):
		var instance: ProbeInstance = _equipped[index]
		if instance.module_id == module_id:
			instance.upgrade_level += 1
			return instance.upgrade_level
	return -1


func equipped_count_for(module_id: String) -> int:
	var count := 0
	for instance in _equipped:
		if instance.module_id == module_id:
			count += 1
	return count


func latest_upgrade_level(module_id: String) -> int:
	for index in range(_equipped.size() - 1, -1, -1):
		var instance: ProbeInstance = _equipped[index]
		if instance.module_id == module_id:
			return instance.upgrade_level
	return -1


func unique_discovered_count(constellation: ConstellationDefinition) -> int:
	var count := 0
	for star_point_id in constellation.star_point_ids:
		if _discovered_star_ids.has(String(star_point_id)):
			count += 1
	return count


func equipped_piece_count(
	constellation: ConstellationDefinition,
	modules: Array[ModuleDefinition]
) -> int:
	var star_ids: Dictionary = {}
	for star_point_id in constellation.star_point_ids:
		star_ids[String(star_point_id)] = true
	var count := 0
	for instance in _equipped:
		var star_point_id := _star_point_id_for(instance.module_id, modules)
		if star_ids.has(star_point_id):
			count += 1
	return count


func _star_point_id_for(module_id: String, modules: Array[ModuleDefinition]) -> String:
	for module in modules:
		if module.module_id == module_id:
			return module.star_point_id
	return ""


class ProbeInstance:
	var instance_id: String = ""
	var module_id: String = ""
	var upgrade_level: int = 0
