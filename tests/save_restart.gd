extends Node
## 跨进程存档验证，由 run_regression.ps1 依次用两个独立进程运行：
## --phase=write：清空进度 → 外围拾取 → 走回村落（安全点保存）→ 退出。
## --phase=verify：新进程启动时读档 → 主菜单「继续」→ 村落出生点 → 外围拾取点不再出现。

const ProgressStore := preload("res://scripts/save/progress_store.gd")
const SceneFlow := preload("res://scripts/ui/scene_flow.gd")
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
	player.global_position = Vector2(-1000, -720)
	await _hold("move_down", 20)
	await _press_action("interact")
	_check(ProgressState.item_count(ITEM) == 1, "外围拾取得到 1 个测试材料")
	_check(not FileAccess.file_exists("user://progress.json"), "拾取本身不写盘（只在安全点保存）")
	player.global_position = Vector2(1260, 0)
	var village := await _walk_until_scene_change("move_right", 60)
	_check(village.scene_file_path == VILLAGE and FileAccess.file_exists("user://progress.json"), "回村安全点写入进度文件")
	_check(village.get_node("UI/InventoryLabel").text.ends_with("进度已保存"), "村落显示已保存")


func _verify_phase() -> void:
	_check(ProgressState.load_status == ProgressStore.LoadStatus.OK, "新进程启动时读取进度")
	_check(ProgressState.item_count(ITEM) == 1 and ProgressState.is_claimed(PICKUP_ID), "新进程恢复持有物与领取标记")
	_check(ProgressState.continue_location().get("entry_id") == &"from_outskirts", "新进程恢复继续位置")
	var menu := await _scene("res://scenes/menu/main_menu.tscn")
	var continue_button := menu.get_node("Center/Panel/Margin/VBox/ContinueButton") as Button
	_check(continue_button.visible, "主菜单显示继续")
	continue_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var village := get_tree().current_scene
	var marker: Vector2 = village.get_node("SpawnPoints/from_outskirts").global_position
	_check(village.scene_file_path == VILLAGE and village.get_node("VillagePlayer").global_position == marker, "继续回到村落的保存入口")
	_check(village.get_node("UI/InventoryLabel").text.begins_with("持有：测试材料 ×1"), "继续后村落显示持有数量")
	SceneFlow.go_to_entry(OUTSKIRTS, &"from_village")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not get_tree().current_scene.has_node("TestMaterialPickup"), "重启后已领取的拾取点不再出现")


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
