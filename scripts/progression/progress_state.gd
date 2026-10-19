extends Node
## Autoload：持有物与世界对象领取状态。场景切换会释放场景节点，所以由这里跨场景持有。
## 启动时从 ProgressStore 读档；只在安全点（进入村落）调用 save_at_safe_point 写盘。
## 场景只通过这里的方法读写，不在节点或共享 Resource 上保存数量。

signal items_changed
signal item_received(item_id: StringName, amount: int)

const ProgressStore := preload("res://scripts/save/progress_store.gd")
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


func _ready() -> void:
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
	return null


## 按 ITEM_DEFINITIONS 顺序返回数量大于 0 的条目：[{definition, count}]。
func inventory_entries() -> Array:
	var entries: Array = []
	for definition in ITEM_DEFINITIONS:
		var count := item_count(definition.item_id)
		if count > 0:
			entries.append({"definition": definition, "count": count})
	return entries


func summary_text() -> String:
	var parts := PackedStringArray()
	for entry in inventory_entries():
		parts.append("%s ×%d" % [entry.definition.display_name, entry.count])
	return "持有：" + ("、".join(parts) if not parts.is_empty() else "无")


func known_item_ids() -> Array:
	var ids: Array = []
	for definition in ITEM_DEFINITIONS:
		ids.append(definition.item_id)
	return ids


func load_from_disk() -> void:
	_items.clear()
	_claimed.clear()
	_saved_location = {}
	_write_blocked = false
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
	items_changed.emit()


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
	items_changed.emit()
