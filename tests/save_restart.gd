extends Node
## 跨进程存档验证，由 run_regression.ps1 依次用两个独立进程运行：
## --phase=write：清空进度 → 外围拾取 → 走回村落（安全点保存）→ 退出。
## --phase=verify：新进程启动时读档 → 主菜单「继续」→ 村落出生点 → 外围拾取点不再出现。

const ProgressStore := preload("res://scripts/save/progress_store.gd")
const SceneFlow := preload("res://scripts/ui/scene_flow.gd")
const Derived := preload("res://scripts/build/build_derived_stats.gd")
const AffixPool := preload("res://scripts/build/affix_pool.gd")
const OUTSKIRTS := "res://scenes/exploration/outskirts.tscn"
const VILLAGE := "res://scenes/village/village.tscn"
const ITEM := &"item_test_material"
const PICKUP_ID := &"outskirts.branch_test_material_01"

var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + label)


func _run() -> void:
	reparent(get_tree().root)
	var phase := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):
			phase = arg.trim_prefix("--phase=")
	if phase == "write":
		await _write_phase()
	elif phase == "verify":
		await _verify_phase()
	else:
		_check(false, "缺少 --phase=write|verify")
	print("SAVE_RESTART %s: %d checks, %d failures" % [phase, _checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _write_phase() -> void:
	ProgressStore.new().delete_files_for_tests()
	ProgressState.load_from_disk()
	_check(ProgressState.load_status == ProgressStore.LoadStatus.MISSING and ProgressState.item_count(ITEM) == 0, "写入阶段从空进度开始")
	var outskirts := await _scene(OUTSKIRTS)
	outskirts.get_node("BranchEnemy").queue_free()
	var player := outskirts.get_node("Player")
	player.get_node("MeleeWeapon").set_physics_process(false)
	player.get_node("RangedWeapon").set_physics_process(false)
	player.get_node("EquippedAutoWeapon").set_physics_process(false)
	player.global_position = Vector2(-1000, -720)
	await _hold("move_down", 20)
	await _press_action("interact")
	_check(ProgressState.item_count(ITEM) == 1, "外围拾取得到 1 个测试材料")
	_check(not FileAccess.file_exists("user://progress.json"), "拾取本身不写盘（只在安全点保存）")
	_check(ProgressState.add_item(&"sword_hunter", 1), "写档前获得猎手短剑")
	_check(ProgressState.equip_weapon(&"sword_hunter") == "", "写档前装备猎手短剑")
	var dev := get_node("/root/DeveloperPanel")
	var note: String = dev.grant_build_test_pack()
	var loadout = ProgressState.build_loadout
	_check(note.contains("没有写入存档") and loadout.set_slot("core", "inst_echo") == "" and loadout.set_slot("support_0", "inst_haste_a") == "", "写档前装好回响预设")
	_check(loadout.set_active_preset("preset_b") == "" and loadout.set_slot("core", "inst_break") == "" and loadout.set_slot("support_0", "inst_haste_a") == "", "第二套预设复用同一个辅助实例")
	_check(loadout.set_active_preset("preset_a") == "", "写档前激活第一套预设")
	_check(loadout.create_random_instance("rand_a", "support_haste", 4) == "" and loadout.create_random_instance("rand_b", "support_haste", 9) == "", "写档前生成两件带词条的急促")
	player.global_position = Vector2(1260, 0)
	var village := await _walk_until_scene_change("move_right", 60)
	_check(village.scene_file_path == VILLAGE and FileAccess.file_exists("user://progress.json"), "回村安全点写入进度文件")
	_check(village.get_node("UI/InventoryLabel").text.ends_with("进度已保存"), "村落显示已保存")
	village.get_node("UI/StarterButton").pressed.emit()
	_check(ProgressState.is_claimed(ProgressState.STARTER_CLAIM) and ProgressState.item_count(&"sword_training") >= 1, "村落领取基础武装")
	SceneFlow.go_to_entry(OUTSKIRTS, &"from_village")
	await get_tree().process_frame
	await get_tree().process_frame
	outskirts = get_tree().current_scene
	var chest: Node = outskirts.get_node("SupportChest")
	_check(chest.try_pickup(), "外围宝箱领取护持")
	var enemy: Node = outskirts.get_node("BranchEnemy")
	enemy.set_physics_process(false)
	enemy.take_damage(999)
	_check(ProgressState.is_claimed(&"outskirts.branch_hunt"), "击败敌人获得猎获")
	SceneFlow.go_to_entry(VILLAGE, &"from_outskirts")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(get_tree().current_scene.scene_file_path == VILLAGE, "带着领取结果再次回村")


func _verify_phase() -> void:
	_check(ProgressState.load_status == ProgressStore.LoadStatus.OK, "新进程启动时读取进度")
	_check(ProgressState.item_count(ITEM) == 1 and ProgressState.is_claimed(PICKUP_ID), "新进程恢复持有物与领取标记")
	_check(ProgressState.equipped_weapon_id() == &"sword_hunter", "新进程恢复装备的武器")
	var loadout = ProgressState.build_loadout
	var active: Dictionary = loadout.active_preset()
	var other := {}
	for preset in loadout.presets:
		if String(preset.get("build_id", "")) == "preset_b":
			other = preset
	var formed: Dictionary = Derived.from_weapon(ProgressState.equipped_weapon_id())
	_check(loadout.active_build_id == "preset_a" and String(active.get("core", "")) == "inst_echo" \
		and String(active.get("support_0", "")) == "inst_haste_a" and String(other.get("support_0", "")) == "inst_haste_a" \
		and String(other.get("core", "")) == "inst_break", "新进程恢复两套预设和同一个辅助实例")
	_check(String(formed.get("mechanic", "")) == "echo" and int(formed.get("armor_break", 0)) == 0 \
		and is_equal_approx(float(formed.get("interval", 1.0)), 0.84), "未激活的破阵不参与结算")
	var expected_a: Dictionary = AffixPool.roll(["affix_edge", "affix_span", "affix_tempo"], 4)
	var expected_b: Dictionary = AffixPool.roll(["affix_edge", "affix_span", "affix_tempo"], 9)
	var saved_a: Array = loadout.instance("rand_a").get("affixes", [])
	var saved_b: Array = loadout.instance("rand_b").get("affixes", [])
	_check(saved_a == expected_a.affixes and saved_b == expected_b.affixes and saved_a != saved_b, "新进程保持两条不同的副词条，没有重抽")
	_check(ProgressState.continue_location().get("entry_id") == &"from_outskirts", "新进程恢复继续位置")
	_check(ProgressState.is_claimed(ProgressState.STARTER_CLAIM) and ProgressState.is_claimed(&"outskirts.chest_shield") \
		and ProgressState.is_claimed(&"outskirts.branch_hunt"), "新进程恢复三份正式领取")
	var owned := int(ProgressState.build_loadout.instances.size())
	_check(ProgressState.claim_starter_kit() == "已经领取" and ProgressState.grant_claimed_instance(&"outskirts.chest_shield", "support_shield_time") == "已经领取" \
		and ProgressState.build_loadout.instances.size() == owned, "新进程里重复领取不会复制实例")
	var menu := await _scene("res://scenes/menu/main_menu.tscn")
	var continue_button := menu.get_node("Center/Panel/Margin/VBox/ContinueButton") as Button
	_check(continue_button.visible, "主菜单显示继续")
	continue_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var village := get_tree().current_scene
	var marker: Vector2 = village.get_node("SpawnPoints/from_outskirts").global_position
	_check(village.scene_file_path == VILLAGE and village.get_node("VillagePlayer").global_position == marker, "继续回到村落的保存入口")
	village.get_node("BuildPanel/Root/Center/Panel/Margin/VBox/PresetRow/PresetB").pressed.emit()
	var switched: Dictionary = Derived.from_weapon(ProgressState.equipped_weapon_id())
	_check(ProgressState.build_loadout.active_build_id == "preset_b" and int(switched.get("armor_break", 0)) == 1, "村落里可以切换到另一套预设")
	_check(village.get_node("UI/InventoryLabel").text.begins_with("持有：测试材料 ×1"), "继续后村落显示持有数量")
	SceneFlow.go_to_entry(OUTSKIRTS, &"from_village")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not get_tree().current_scene.has_node("TestMaterialPickup"), "重启后已领取的拾取点不再出现")
	_check(not get_tree().current_scene.has_node("SupportChest"), "重启后已打开的宝箱不再出现")
	var again: Node = get_tree().current_scene.get_node("BranchEnemy")
	again.set_physics_process(false)
	var owned_after_reload := int(ProgressState.build_loadout.instances.size())
	again.take_damage(999)
	_check(ProgressState.build_loadout.instances.has("claim.outskirts.branch_hunt") \
		and ProgressState.build_loadout.instances.size() == owned_after_reload, "第二轮击败敌人不再发放猎获")


func _scene(path: String) -> Node:
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	return get_tree().current_scene


func _hold(action: String, frames: int) -> void:
	Input.action_press(action)
	for i in frames:
		await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame


func _press_action(action: String) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _walk_until_scene_change(action: String, max_frames: int) -> Node:
	var start := get_tree().current_scene
	Input.action_press(action)
	for i in max_frames:
		await get_tree().physics_frame
		if get_tree().current_scene != start:
			break
	Input.action_release(action)
	await get_tree().process_frame
	return get_tree().current_scene
