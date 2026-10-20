extends Node
## Autoload：持有物与世界对象领取状态。场景切换会释放场景节点，所以由这里跨场景持有。
## 启动时从 ProgressStore 读档；只在安全点（进入村落）调用 save_at_safe_point 写盘。
## 场景只通过这里的方法读写，不在节点或共享 Resource 上保存数量。

signal items_changed
signal item_received(item_id: StringName, amount: int)
signal equipment_changed
signal growth_changed

const DEFAULT_WEAPON_ID := &"sword_training"

const ProgressStore := preload("res://scripts/save/progress_store.gd")
const ItemCatalog := preload("res://scripts/items/item_catalog.gd")
const RecipeCatalog := preload("res://scripts/items/recipe_catalog.gd")
const BuildLoadout := preload("res://scripts/build/build_loadout.gd")
const GrowthCatalog := preload("res://scripts/progression/growth_catalog.gd")
const Targeting := preload("res://scripts/combat/combat_targeting.gd")
const ITEM_DEFINITIONS: Array[ItemDefinition] = [
	preload("res://data/items/item_test_material.tres"),
	preload("res://data/items/item_test_hide.tres"),
]

var load_status: int = ProgressStore.LoadStatus.MISSING
var last_save_ok: bool = false

var _store: ProgressStore = ProgressStore.new()
var _items: Dictionary = {}
var _claimed: Dictionary = {}
var _saved_location: Dictionary = {}
var _write_blocked: bool = false
var _equipped_weapon_id: StringName = DEFAULT_WEAPON_ID
## 只活在本进程。换场景和换装都不把它清零，也不写入存档。
var attack_cooldown_left: float = 0.0
var build_loadout = BuildLoadout.new()
var _craft_busy: bool = false
var _xp: int = 0
var _level: int = 1
var _techs: Dictionary = {}


func _ready() -> void:
	var mechanics := preload("res://scripts/build/build_mechanics.gd").new()
	mechanics.name = "BuildMechanics"
	add_child(mechanics)
	var bus = Targeting.event_bus()
	if not bus.target_killed.is_connected(_on_target_killed):
		bus.target_killed.connect(_on_target_killed)
	load_from_disk()


func item_count(item_id: StringName) -> int:
	return int(_items.get(item_id, 0))


func is_claimed(object_id: StringName) -> bool:
	return _claimed.has(object_id)


## 领取标记与物品数量在同一调用内一起改变，因此任何保存快照都同时包含两者。
func claim_pickup(object_id: StringName, item_id: StringName, amount: int) -> bool:
	if object_id == &"" or item_id == &"" or amount <= 0 or _claimed.has(object_id):
		return false
	if get_definition(item_id) == null:
		return false
	_claimed[object_id] = true
	_items[item_id] = mini(item_count(item_id) + amount, ProgressStore.MAX_ITEM_COUNT)
	items_changed.emit()
	item_received.emit(item_id, amount)
	return true


const STARTER_CLAIM := &"village.starter_kit"
const STARTER_CORE := "core_echo"


## 村落一次性基础武装：试验短剑和回响核心一起记入领取标记。重复领取不会再发一份。
func claim_starter_kit() -> String:
	if is_claimed(STARTER_CLAIM):
		return "已经领取"
	if build_loadout.definition(STARTER_CORE).is_empty():
		return "未知组件"
	if item_count(DEFAULT_WEAPON_ID) < 1:
		_items[DEFAULT_WEAPON_ID] = 1
	var reason := build_loadout.add_instance("claim.village.starter_kit", STARTER_CORE)
	if reason != "" and reason != "已经拥有这个实例":
		return reason
	_claimed[STARTER_CLAIM] = true
	items_changed.emit()
	return ""


## 唯一领取标记和组件实例在同一次调用里更新。重复或未知定义不会复制实例。
func grant_claimed_instance(object_id: StringName, definition_id: String) -> String:
	if object_id == &"":
		return "没有领取标记"
	if is_claimed(object_id):
		return "已经领取"
	var instance_id := "claim.%s" % String(object_id)
	var reason := build_loadout.add_instance(instance_id, definition_id)
	if reason != "" and reason != "已经拥有这个实例":
		return reason
	_claimed[object_id] = true
	items_changed.emit()
	return ""


func mark_claimed(object_id: StringName) -> void:
	if object_id == &"" or _claimed.has(object_id):
		return
	_claimed[object_id] = true
	items_changed.emit()


## 普通掉落物：只增加数量，不记领取状态。未知物品或无效数量会被拒绝。
func add_item(item_id: StringName, amount: int) -> bool:
	if amount <= 0 or get_definition(item_id) == null:
		return false
	_items[item_id] = mini(item_count(item_id) + amount, ProgressStore.MAX_ITEM_COUNT)
	items_changed.emit()
	item_received.emit(item_id, amount)
	return true


func get_definition(item_id: StringName) -> ItemDefinition:
	for definition in ITEM_DEFINITIONS:
		if definition.item_id == item_id:
			return definition
	return ItemCatalog.make_definition(item_id)


## 先列原有测试物品，再列物品表里持有的条目：[{definition, count}]。
func inventory_entries() -> Array:
	var entries: Array = []
	var seen: Dictionary = {}
	for definition in ITEM_DEFINITIONS:
		seen[definition.item_id] = true
		var count := item_count(definition.item_id)
		if count > 0:
			entries.append({"definition": definition, "count": count})
	for item_id in ItemCatalog.item_ids():
		if seen.has(item_id):
			continue
		var count := item_count(item_id)
		if count <= 0:
			continue
		var definition := get_definition(item_id)
		if definition == null:
			continue
		entries.append({"definition": definition, "count": count})
	return entries


func summary_text() -> String:
	var parts := PackedStringArray()
	for entry in inventory_entries():
		parts.append("%s ×%d" % [entry.definition.display_name, entry.count])
	return "持有：" + ("、".join(parts) if not parts.is_empty() else "无")


func equipped_weapon_id() -> StringName:
	return _equipped_weapon_id


## 空字符串表示可以制作。不改数量。
func craft_blocked_reason(recipe_id: String) -> String:
	var recipe: Dictionary = RecipeCatalog.recipe(recipe_id)
	if recipe.is_empty():
		return "没有这个配方"
	var output_id := StringName(recipe.get("output_item_id", ""))
	var output: Dictionary = ItemCatalog.get_item(output_id)
	if output.is_empty() or String(output.get("category_id", "")) != "weapon":
		return "产出还没有实现"
	var blueprint_id := String(recipe.get("blueprint_item_id", ""))
	if blueprint_id != "" and item_count(StringName(blueprint_id)) < 1:
		return "需要图纸"
	var tech_id := String(recipe.get("tech_id", ""))
	if tech_id != "" and not has_tech(tech_id):
		return "需要技术"
	for entry in recipe.get("ingredients", []):
		var item_id := StringName(entry.get("item_id", ""))
		var need := int(entry.get("count", 0))
		if item_id == &"" or need <= 0 or get_definition(item_id) == null:
			return "未知材料"
		if item_count(item_id) < need:
			return "材料不足"
	return ""


## 先检查再扣除材料并发已实现武器，然后写入当前安全点。失败会回滚，不重复发奖。
func craft_recipe(recipe_id: String) -> String:
	if _craft_busy:
		return "正在制作"
	_craft_busy = true
	var reason := craft_blocked_reason(recipe_id)
	if reason != "":
		_craft_busy = false
		return reason
	var recipe: Dictionary = RecipeCatalog.recipe(recipe_id)
	var before: Dictionary = _items.duplicate()
	for entry in recipe.get("ingredients", []):
		var item_id := StringName(entry.get("item_id", ""))
		var left := item_count(item_id) - int(entry.get("count", 0))
		if left <= 0:
			_items.erase(item_id)
		else:
			_items[item_id] = left
	var output_id := StringName(recipe.get("output_item_id", ""))
	var output_count := int(recipe.get("output_count", 1))
	_items[output_id] = mini(item_count(output_id) + output_count, ProgressStore.MAX_ITEM_COUNT)
	var scene_id: StringName = &"village"
	var entry_id: StringName = &"default"
	if not _saved_location.is_empty():
		scene_id = StringName(_saved_location.scene_id)
		entry_id = StringName(_saved_location.entry_id)
	if not save_at_safe_point(scene_id, entry_id):
		_items = before
		items_changed.emit()
		_craft_busy = false
		return "存档失败，没有扣除也没有发放"
	items_changed.emit()
	item_received.emit(output_id, output_count)
	_craft_busy = false
	return ""


func dismantle_blocked_reason(instance_id: String, confirm_unequip: bool = false) -> String:
	return build_loadout.dismantle_blocked_reason(instance_id, confirm_unequip)


## 先检查再拆实例，然后写入当前安全点。失败会回滚。装在预设里的要先确认卸下。
func dismantle_component(instance_id: String, confirm_unequip: bool = false) -> String:
	if _craft_busy:
		return "正在处理"
	_craft_busy = true
	var reason := dismantle_blocked_reason(instance_id, confirm_unequip)
	if reason != "":
		_craft_busy = false
		return reason
	var before_build: Dictionary = build_loadout.export_state()
	reason = build_loadout.dismantle(instance_id, confirm_unequip)
	if reason != "":
		_craft_busy = false
		return reason
	var scene_id: StringName = &"village"
	var entry_id: StringName = &"default"
	if not _saved_location.is_empty():
		scene_id = StringName(_saved_location.scene_id)
		entry_id = StringName(_saved_location.entry_id)
	if not save_at_safe_point(scene_id, entry_id):
		build_loadout.replace_from_save(before_build)
		_craft_busy = false
		return "存档失败，没有拆解"
	_craft_busy = false
	return ""


func enhance_blocked_reason(instance_id: String) -> String:
	var reason := build_loadout.enhance_blocked_reason(instance_id)
	if reason != "":
		return reason
	var cost_id: StringName = StringName(BuildLoadout.ENHANCE_COST_ITEM)
	if get_definition(cost_id) == null:
		return "未知材料"
	if item_count(cost_id) < BuildLoadout.ENHANCE_COST_COUNT:
		return "材料不足"
	return ""


## 强化只加测试数值。先扣材料再写盘，失败回滚。不改核心机制和词条数量。
func enhance_component(instance_id: String) -> String:
	if _craft_busy:
		return "正在处理"
	_craft_busy = true
	var reason := enhance_blocked_reason(instance_id)
	if reason != "":
		_craft_busy = false
		return reason
	var before_items: Dictionary = _items.duplicate()
	var before_build: Dictionary = build_loadout.export_state()
	var cost_id: StringName = StringName(BuildLoadout.ENHANCE_COST_ITEM)
	var left: int = item_count(cost_id) - BuildLoadout.ENHANCE_COST_COUNT
	if left <= 0:
		_items.erase(cost_id)
	else:
		_items[cost_id] = left
	reason = build_loadout.enhance(instance_id)
	if reason != "":
		_items = before_items
		_craft_busy = false
		return reason
	var scene_id: StringName = &"village"
	var entry_id: StringName = &"default"
	if not _saved_location.is_empty():
		scene_id = StringName(_saved_location.scene_id)
		entry_id = StringName(_saved_location.entry_id)
	if not save_at_safe_point(scene_id, entry_id):
		_items = before_items
		build_loadout.replace_from_save(before_build)
		items_changed.emit()
		_craft_busy = false
		return "存档失败，没有强化"
	items_changed.emit()
	_craft_busy = false
	return ""


## 空字符串表示装备成功。未持有、未知或非武器会被拒绝，也不改冷却。
func equip_weapon(item_id: StringName) -> String:
	var item: Dictionary = ItemCatalog.get_item(item_id)
	if item.is_empty():
		return "未知物品"
	if String(item.get("category_id", "")) != "weapon":
		return "不是武器，不能装备"
	if item_count(item_id) <= 0:
		return "未持有"
	if _equipped_weapon_id != item_id:
		_equipped_weapon_id = item_id
		equipment_changed.emit()
	return ""


func known_item_ids() -> Array:
	var ids: Array = []
	for definition in ITEM_DEFINITIONS:
		ids.append(definition.item_id)
	for item_id in ItemCatalog.item_ids():
		if not ids.has(item_id):
			ids.append(item_id)
	return ids


func load_from_disk() -> void:
	_items.clear()
	_claimed.clear()
	_saved_location = {}
	_write_blocked = false
	_equipped_weapon_id = DEFAULT_WEAPON_ID
	attack_cooldown_left = 0.0
	_replace_growth({})
	var result := _store.load_data(known_item_ids())
	load_status = result.status
	match load_status:
		ProgressStore.LoadStatus.NEWER_VERSION:
			_write_blocked = true
			push_warning("ProgressState: 进度文件来自更新版本，本次不读取也不覆盖")
		ProgressStore.LoadStatus.CORRUPT:
			push_warning("ProgressState: 进度文件和备份都无法读取，已另存为 .corrupt，从空进度开始")
			_store.quarantine_corrupt()
	if result.data != null:
		for item_id in result.data.items:
			_items[StringName(item_id)] = result.data.items[item_id]
		for object_id in result.data.claimed_objects:
			_claimed[StringName(object_id)] = true
		_saved_location = result.data.location
		_equipped_weapon_id = _weapon_or_default(StringName(result.data.get("equipped_weapon_id", DEFAULT_WEAPON_ID)))
		build_loadout.replace_from_save(result.data.get("build", {}))
		_replace_growth(result.data.get("growth", {}))
	else:
		build_loadout.replace_from_save(BuildLoadout.saved_build(null, PackedStringArray()))
	items_changed.emit()
	equipment_changed.emit()
	growth_changed.emit()


func save_at_safe_point(scene_id: StringName, entry_id: StringName) -> bool:
	last_save_ok = false
	if _write_blocked:
		push_warning("ProgressState: 进度文件版本较新，未保存")
		return false
	var data := snapshot(scene_id, entry_id)
	last_save_ok = _store.save_data(data, known_item_ids())
	if last_save_ok:
		_saved_location = data.location
	return last_save_ok


func snapshot(scene_id: StringName, entry_id: StringName) -> Dictionary:
	var items := {}
	for item_id in _items:
		items[String(item_id)] = _items[item_id]
	var claimed: Array = []
	for object_id in _claimed:
		claimed.append(String(object_id))
	claimed.sort()
	return {
		"schema_version": ProgressStore.SCHEMA_VERSION,
		"saved_at": Time.get_datetime_string_from_system(true),
		"location": {"scene_id": String(scene_id), "entry_id": String(entry_id)},
		"items": items,
		"claimed_objects": claimed,
		"equipped_weapon_id": String(_equipped_weapon_id),
		"build": build_loadout.export_state(),
		"growth": _export_growth(),
	}


func is_write_blocked() -> bool:
	return _write_blocked


func has_continue() -> bool:
	return not _saved_location.is_empty()


## 返回 {scene_path, entry_id}；没有可继续进度时为空。
func continue_location() -> Dictionary:
	if _saved_location.is_empty():
		return {}
	return {
		"scene_path": ProgressStore.SAFE_SCENES[_saved_location.scene_id],
		"entry_id": StringName(_saved_location.entry_id),
	}


## 测试用：替换存档位置并重新读取。
func use_store_for_tests(store: ProgressStore) -> void:
	_store = store
	load_from_disk()


## 只清空内存状态，不删除存档文件。
func reset() -> void:
	_items.clear()
	_claimed.clear()
	_equipped_weapon_id = DEFAULT_WEAPON_ID
	attack_cooldown_left = 0.0
	_craft_busy = false
	_replace_growth({})
	build_loadout.replace_from_save(BuildLoadout.saved_build(null, PackedStringArray()))
	items_changed.emit()
	equipment_changed.emit()
	growth_changed.emit()


func player_level() -> int:
	return _level


func player_xp() -> int:
	return _xp


func has_tech(tech_id: String) -> bool:
	return _techs.has(tech_id)


func level_damage_bonus() -> int:
	return maxi(0, _level - 1) * GrowthCatalog.flat_damage_per_level()


func player_max_hp(base_hp: int = -1) -> int:
	var base := base_hp
	if base < 0:
		base = GrowthCatalog.base_max_hp()
	return base + maxi(0, _level - 1) * GrowthCatalog.hp_per_level()


func xp_to_next() -> int:
	if _level >= GrowthCatalog.test_level_range():
		return 0
	return GrowthCatalog.xp_per_level()


func growth_text() -> String:
	var next := xp_to_next()
	var xp_line := "经验 %d" % _xp
	if next > 0:
		xp_line += "/%d" % next
	else:
		xp_line += " · 已到测试等级上限"
	return "等级 %d · %s · 生命 +%d · 伤害 +%d" % [
		_level,
		xp_line,
		maxi(0, _level - 1) * GrowthCatalog.hp_per_level(),
		level_damage_bonus(),
	]


func add_xp(amount: int) -> String:
	if amount <= 0:
		return "无效经验"
	_xp += amount
	var range_cap := GrowthCatalog.test_level_range()
	var need := GrowthCatalog.xp_per_level()
	while _level < range_cap and _xp >= need:
		_xp -= need
		_level += 1
	if _level >= range_cap:
		_xp = 0
	growth_changed.emit()
	return ""


func research_blocked_reason(tech_id: String) -> String:
	var spec: Dictionary = GrowthCatalog.tech(tech_id)
	if spec.is_empty():
		return "没有这项技术"
	if has_tech(tech_id):
		return "已经解锁"
	if _level < int(spec.get("required_level", 1)):
		return "需要等级"
	var cost_id: StringName = StringName(spec.get("cost_item_id", ""))
	var need := int(spec.get("cost_count", 0))
	if cost_id == &"" or need <= 0 or get_definition(cost_id) == null:
		return "未知材料"
	if item_count(cost_id) < need:
		return "材料不足"
	return ""


## 研究一项技术。先检查再扣材料，然后写入当前安全点。失败回滚。
func research_tech(tech_id: String) -> String:
	if _craft_busy:
		return "正在处理"
	_craft_busy = true
	var reason := research_blocked_reason(tech_id)
	if reason != "":
		_craft_busy = false
		return reason
	var spec: Dictionary = GrowthCatalog.tech(tech_id)
	var before_items: Dictionary = _items.duplicate()
	var before_techs: Dictionary = _techs.duplicate()
	var cost_id: StringName = StringName(spec.get("cost_item_id", ""))
	var left: int = item_count(cost_id) - int(spec.get("cost_count", 0))
	if left <= 0:
		_items.erase(cost_id)
	else:
		_items[cost_id] = left
	_techs[tech_id] = true
	var scene_id: StringName = &"village"
	var entry_id: StringName = &"default"
	if not _saved_location.is_empty():
		scene_id = StringName(_saved_location.scene_id)
		entry_id = StringName(_saved_location.entry_id)
	if not save_at_safe_point(scene_id, entry_id):
		_items = before_items
		_techs = before_techs
		items_changed.emit()
		growth_changed.emit()
		_craft_busy = false
		return "存档失败，没有研究"
	items_changed.emit()
	growth_changed.emit()
	_craft_busy = false
	return ""


func _weapon_or_default(item_id: StringName) -> StringName:
	var item: Dictionary = ItemCatalog.get_item(item_id)
	if item.is_empty() or String(item.get("category_id", "")) != "weapon":
		return DEFAULT_WEAPON_ID
	return item_id


func _export_growth() -> Dictionary:
	var techs: Array = _techs.keys()
	techs.sort()
	return {
		"xp": _xp,
		"level": _level,
		"techs": techs,
	}


func _replace_growth(data: Dictionary) -> void:
	_xp = int(data.get("xp", 0))
	_level = maxi(1, int(data.get("level", 1)))
	_techs.clear()
	for tech_id in data.get("techs", []):
		var id := String(tech_id)
		if id != "":
			_techs[id] = true


func _on_target_killed(result, context) -> void:
	if result == null or result.killed != true:
		return
	var source = context.source
	if source == null or not is_instance_valid(source) or not source.is_in_group("player"):
		return
	if not _exploration_grants_xp():
		return
	add_xp(GrowthCatalog.xp_per_kill())


func _exploration_grants_xp() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	var path := scene.scene_file_path
	if not path.begins_with("res://scenes/exploration/"):
		return false
	return path != "res://scenes/exploration/action_training.tscn"
