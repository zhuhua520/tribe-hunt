extends Node
## 无第三方依赖的集成回归。测试用 APPDATA 重定向至 tmp，避免改动玩家设置。

const Targeting := preload("res://scripts/combat/combat_targeting.gd")
const SceneFlow := preload("res://scripts/ui/scene_flow.gd")
const SettingsStore := preload("res://scripts/save/settings_store.gd")
const ActionController := preload("res://scripts/combat/player_action_controller.gd")
const LayerDefinition := preload("res://scripts/appearance/appearance_layer.gd")
const Profile := preload("res://scripts/appearance/appearance_profile.gd")
var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + label)


func _scene(path: String) -> Node:
	get_tree().paused = false
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	return get_tree().current_scene


func _arena(interval: int = 1) -> Node:
	BuildRunService.set_extraction_wave_interval(interval)
	var arena := await _scene("res://scenes/combat/arena.tscn")
	arena.get_node("WaveManager").set_physics_process(false)
	var player := arena.get_node("Player")
	player.set_physics_process(false)
	player.get_node("MeleeWeapon").set_physics_process(false)
	player.get_node("RangedWeapon").set_physics_process(false)
	return arena


func _enemy(arena: Node, pos: Vector2) -> Node2D:
	var enemy := preload("res://scenes/combat/enemy.tscn").instantiate() as Node2D
	arena.add_child(enemy)
	enemy.position = pos
	enemy.set_physics_process(false)
	return enemy


func _run() -> void:
	reparent(get_tree().root)
	# 既有用例验证自动武器本身；D1 后自动攻击默认关闭，这里只在内存中打开，不写设置文件。
	SettingsStore.set_auto_attack(true, false)
	for directory in ["res://scripts", "res://data", "res://scenes"]:
		_load_resources(directory)
	var menu := await _scene("res://scenes/menu/main_menu.tscn")
	_check(menu != null, "主菜单加载")
	var village := await _scene("res://scenes/village/village.tscn")
	_check(village.get_node("VillagePlayer/Sprite2D").texture != null, "村落已导入纹理加载")
	_check(village.get_node("VillagePlayer/Sprite2D").equipped_ids().size() == 6, "村落加载 ULPC 分层外观")
	village._open_expedition_overlay()
	_check(village.get_node("UI/ExpeditionOverlay").visible, "村落出征入口")
	village._on_close_expedition_overlay()
	var arena := await _arena()
	_test_combat(arena)
	_test_layers(arena.get_node("Player/Sprite2D"))
	await get_tree().process_frame
	for interval in [1, 2]:
		arena = await _arena(interval)
		await _test_waves(arena, interval)
	arena = await _arena()
	var player := arena.get_node("Player")
	player.take_damage(999)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(arena.get_node("RunStats").outcome_label() == "狩猎失败", "失败结算")
	_check(player.process_mode == Node.PROCESS_MODE_DISABLED, "结果页停止玩家与武器")
	_check(arena.get_node("CombatHUD/Root/ResultPanel").visible, "失败结果面板")
	arena = await _arena()
	_check(arena.get_node("RunStats").kill_count == 0 and arena.get_node("Player").hp == 8, "重开清空统计与生命")
	var manager := arena.get_node("WaveManager")
	manager._phase = "clearing"
	manager._wave_index = 0
	manager._on_wave_cleared()
	manager.complete_extraction_leave()
	_check(not get_tree().paused and manager._phase == "portal", "回城选择生成传送门且解除暂停")
	var stats := arena.get_node("RunStats")
	manager._return_portal._on_body_entered(arena.get_node("Player"))
	_check(stats.outcome_label() == "撤离", "进传送门结束统计")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(get_tree().current_scene.scene_file_path == "res://scenes/village/village.tscn", "传送门返回村落")
	arena = await _arena()
	await _test_projectile_finishes_boss(arena)
	arena = await _arena()
	manager = arena.get_node("WaveManager")
	manager.waves[0] = null
	manager._start_next_wave()
	_check(manager._phase == "ended", "缺失配置安全停止而非空引用崩溃")
	await _test_outskirts_round_trips()
	await _test_outskirts_collision()
	await _test_outskirts_pickup()
	await _test_terrain_combat()
	_test_progress_store()
	await _test_drops_and_inventory()
	await _test_manual_actions()
	print("REGRESSION: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _test_combat(arena: Node) -> void:
	var player := arena.get_node("Player")
	var melee := player.get_node("MeleeWeapon")
	var ranged := player.get_node("RangedWeapon")
	_check(melee.definition.weapon_id == "weapon_club" and ranged.definition.attack_range == 320.0, "战斗引用静态武器定义")
	BuildRunService.set_equipped_module_ids(["module_hunt_melee", "module_hunt_ranged"])
	_check(is_equal_approx(BuildRunService.get_effective_cooldown(0.45, "melee"), 0.375), "近战模块生效")
	_check(is_equal_approx(BuildRunService.get_effective_attack_range(320.0, "ranged"), 384.0), "远程模块生效")
	_check(melee.definition.cooldown == 0.45 and ranged.definition.attack_range == 320.0, "共享定义不被模块改写")
	var first := _enemy(arena, Vector2(40, 0))
	var second := _enemy(arena, Vector2(60, 0))
	_check(Targeting.nearest_enemy(player, 72.0) == first, "最近有效目标")
	melee._physics_process(0.01)
	_check(first.hp == 3, "近战前摇无伤害")
	first.position = Vector2(200, 0)
	melee._physics_process(0.1)
	_check(first.hp == 3 and second.hp == 3, "锁定目标移出范围不会命中其他敌人")
	melee._physics_process(0.2)
	melee._physics_process(0.5)
	melee._physics_process(0.1)
	_check(second.hp == 2, "下一击实际命中一次")
	var stone := preload("res://scenes/weapons/stone_projectile.tscn").instantiate()
	arena.add_child(stone)
	stone._on_body_entered(first)
	stone._on_body_entered(second)
	_check(first.hp == 2 and second.hp == 2, "石弹同帧多碰撞只伤害一个目标")
	var kills: int = arena.get_node("RunStats").kill_count
	first.take_damage(99)
	first.take_damage(99)
	_check(arena.get_node("RunStats").kill_count == kills + 1, "死亡统计只增加一次")
	_check(Targeting.nearest_enemy(player, 400.0) == second, "不选择死亡或待删除目标")
	var projectile_count := get_tree().get_nodes_in_group("combat_projectiles").size()
	ranged._physics_process(0.01)
	_check(get_tree().get_nodes_in_group("combat_projectiles").size() == projectile_count + 1, "弹弓实例化真实石弹")
	ranged._physics_process(0.01)
	_check(get_tree().get_nodes_in_group("combat_projectiles").size() == projectile_count + 1, "弹弓冷却防止连续生成")
	second.queue_free()
	BuildRunService.set_equipped_module_ids([])


func _test_projectile_finishes_boss(arena: Node) -> void:
	# 走真实物理碰撞回调；直接调用 _on_body_entered 无法复现回调内禁用碰撞体的引擎报错。
	var manager := arena.get_node("WaveManager")
	manager._start_boar_king()
	var boss := arena.get_child(arena.get_child_count() - 1) as Node2D
	boss.set_physics_process(false)
	boss.hp = 1
	var stone := preload("res://scenes/weapons/stone_projectile.tscn").instantiate()
	arena.add_child(stone)
	stone.global_position = boss.global_position + Vector2(-80, 0)
	stone.setup(Vector2.RIGHT, 1)
	for i in 60:
		await get_tree().physics_frame
		if manager._phase == "ended":
			break
	await get_tree().process_frame
	_check(manager._phase == "ended" and (not is_instance_valid(boss) or boss.hp == 0), "石弹物理碰撞击败首领并结束战斗")
	_check(arena.get_node("RunStats").outcome_label() == "狩猎成功", "石弹击败首领计为狩猎成功")


## 按住移动动作跑物理帧，直到场景切换或超时；返回切换后的当前场景。
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


func _hold(action: String, frames: int) -> void:
	Input.action_press(action)
	for i in frames:
		await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame


func _idle_keeps_scene(frames: int) -> bool:
	var scene := get_tree().current_scene
	for i in frames:
		await get_tree().physics_frame
	return get_tree().current_scene == scene


func _test_outskirts_round_trips() -> void:
	const OUTSKIRTS := "res://scenes/exploration/outskirts.tscn"
	const VILLAGE := "res://scenes/village/village.tscn"
	var village := await _scene(VILLAGE)
	var trips_ok := 0
	for trip in 10:
		village.get_node("VillagePlayer").global_position = Vector2(-1560, 0)
		var outskirts := await _walk_until_scene_change("move_left", 60)
		var ok := outskirts != null and outskirts.scene_file_path == OUTSKIRTS
		if ok:
			var marker: Vector2 = outskirts.get_node("SpawnPoints/from_village").global_position
			ok = outskirts.entry_id == &"from_village" \
				and outskirts.get_node("Player").global_position.distance_to(marker) < 12.0 \
				and get_tree().get_nodes_in_group("player").size() == 1
			var stayed: bool = await _idle_keeps_scene(10)
			ok = ok and stayed
		if ok:
			outskirts.get_node("Player").global_position = Vector2(1260, 0)
			village = await _walk_until_scene_change("move_right", 60)
			ok = village != null and village.scene_file_path == VILLAGE
		if ok:
			var marker: Vector2 = village.get_node("SpawnPoints/from_outskirts").global_position
			ok = village.get_node("VillagePlayer").global_position.distance_to(marker) < 12.0 \
				and not village.get_node("UI/ExpeditionOverlay").visible \
				and get_tree().get_nodes_in_group("player").is_empty()
			var stayed: bool = await _idle_keeps_scene(10)
			ok = ok and stayed
		if not ok:
			break
		trips_ok += 1
	_check(trips_ok == 10, "村落与林地外围连续往返 10 次，出生点正确、单一玩家、不立即回传（%d/10）" % trips_ok)
	SceneFlow.go_to_entry(OUTSKIRTS, &"no_such_entry")
	await get_tree().process_frame
	await get_tree().process_frame
	var fallback := get_tree().current_scene
	_check(fallback.scene_file_path == OUTSKIRTS and fallback.entry_id == &"from_village", "未知入口回退到默认出生点")
	SceneFlow.go_to(VILLAGE)
	await get_tree().process_frame
	await get_tree().process_frame
	var default_marker: Vector2 = get_tree().current_scene.get_node("SpawnPoints/default").global_position
	_check(get_tree().current_scene.get_node("VillagePlayer").global_position == default_marker, "普通切场景不残留入口上下文")


func _test_outskirts_collision() -> void:
	var outskirts := await _scene("res://scenes/exploration/outskirts.tscn")
	var player := outskirts.get_node("Player") as CharacterBody2D
	player.get_node("MeleeWeapon").set_physics_process(false)
	player.get_node("RangedWeapon").set_physics_process(false)
	player.global_position = Vector2(-1120, 0)
	await _hold("move_left", 60)
	_check(player.global_position.x >= -1200.0 + 13.0, "西墙阻挡玩家（x=%.1f）" % player.global_position.x)
	player.global_position = Vector2(300, 0)
	await _hold("move_up", 60)
	_check(player.global_position.y >= -100.0 + 13.0, "岩石阻挡玩家（y=%.1f）" % player.global_position.y)
	player.global_position = Vector2(700, 320)
	await _hold("move_up", 60)
	_check(player.global_position.y > 250.0, "树干阻挡玩家（y=%.1f）" % player.global_position.y)
	player.global_position = Vector2(-1180, -780)
	await get_tree().physics_frame
	await get_tree().process_frame
	var center := (player.get_node("Camera2D") as Camera2D).get_screen_center_position()
	_check(center.x >= -1264.0 + 640.0 - 1.0 and center.y >= -864.0 + 360.0 - 1.0, "相机不越过地图左上边界")
	var tree := outskirts.get_node("PlaceholderTree") as Node2D
	_check(outskirts.y_sort_enabled and tree.get_parent() == player.get_parent() and tree.get_node("Sprite2D").texture != null, "占位树与玩家同一 Y 排序层")


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


func _disable_weapons(player: Node) -> void:
	player.get_node("MeleeWeapon").set_physics_process(false)
	player.get_node("RangedWeapon").set_physics_process(false)


func _test_outskirts_pickup() -> void:
	const OUTSKIRTS := "res://scenes/exploration/outskirts.tscn"
	const ITEM := &"item_test_material"
	ProgressState.reset()
	var outskirts := await _scene(OUTSKIRTS)
	outskirts.get_node("BranchEnemy").queue_free()
	var player := outskirts.get_node("Player") as CharacterBody2D
	_disable_weapons(player)
	var pickup := outskirts.get_node("TestMaterialPickup")
	player.global_position = Vector2(-1000, -720)
	await get_tree().physics_frame
	await _press_action("interact")
	_check(ProgressState.item_count(ITEM) == 0, "范围外交互不领取")
	await _hold("move_down", 20)
	_check(pickup.get_node("Prompt").visible, "进入拾取范围显示提示")
	get_tree().paused = true
	await _press_action("interact")
	_check(ProgressState.item_count(ITEM) == 0 and not pickup.is_queued_for_deletion(), "暂停时交互不执行")
	get_tree().paused = false
	await _press_action("interact")
	await _press_action("interact")
	_check(ProgressState.item_count(ITEM) == 1 and not is_instance_valid(pickup), "重复按交互只增加一次")
	_check(outskirts.get_node("UI/InventoryLabel").text == "持有：测试材料 ×1", "外围 HUD 显示持有数量")
	_check(outskirts.get_node("UI/MessageLabel").text == "获得 测试材料 ×1", "拾取反馈")
	outskirts = await _scene(OUTSKIRTS)
	_check(not outskirts.has_node("TestMaterialPickup") and ProgressState.item_count(ITEM) == 1, "重载场景后已领取对象不再出现")
	_disable_weapons(outskirts.get_node("Player"))
	outskirts.get_node("Player").global_position = Vector2(1260, 0)
	var village := await _walk_until_scene_change("move_right", 60)
	_check(village.scene_file_path == "res://scenes/village/village.tscn" and village.get_node("UI/InventoryLabel").text.begins_with("持有：测试材料 ×1"), "回村查看持有数量")
	village.get_node("VillagePlayer").global_position = Vector2(-1560, 0)
	outskirts = await _walk_until_scene_change("move_left", 60)
	_check(outskirts.scene_file_path == OUTSKIRTS and not outskirts.has_node("TestMaterialPickup") and ProgressState.item_count(ITEM) == 1, "往返后不重复领取")
	outskirts.get_node("Player").take_damage(999)
	await get_tree().process_frame
	_check(outskirts.get_node("UI/DefeatPanel").visible, "外围倒下显示临时返回入口")
	ProgressState.reset()


func _thin_wall(parent: Node, pos: Vector2, size: Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.collision_layer = Targeting.TERRAIN_LAYER
	wall.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	wall.add_child(shape)
	parent.add_child(wall)
	wall.global_position = pos
	return wall


func _fire_stone(parent: Node, pos: Vector2, speed: float) -> Node:
	var stone := preload("res://scenes/weapons/stone_projectile.tscn").instantiate()
	parent.add_child(stone)
	stone.global_position = pos
	stone.speed = speed
	stone.setup(Vector2.RIGHT, 1)
	return stone


func _physics_frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _test_terrain_combat() -> void:
	var outskirts := await _scene("res://scenes/exploration/outskirts.tscn")
	var player := outskirts.get_node("Player") as CharacterBody2D
	player.set_physics_process(false)
	_disable_weapons(player)
	var melee := player.get_node("MeleeWeapon")
	var ranged := player.get_node("RangedWeapon")
	var enemy := outskirts.get_node("BranchEnemy") as CharacterBody2D
	player.global_position = Vector2(-800, -600)
	enemy.global_position = Vector2(-420, -600)
	await _physics_frames(90)
	_check(enemy.global_position.x >= -476.0 + 12.0, "敌人追击时被实心墙挡住（x=%.1f）" % enemy.global_position.x)
	enemy.set_physics_process(false)
	var wall := _thin_wall(outskirts, Vector2(-800, 500), Vector2(16, 200))
	player.global_position = Vector2(-840, 500)
	enemy.global_position = Vector2(-770, 500)
	await _physics_frames(2)
	melee.set_physics_process(true)
	await _physics_frames(60)
	melee.set_physics_process(false)
	_check(enemy.hp == enemy.max_hp, "木棍不隔墙命中")
	var stones_before := get_tree().get_nodes_in_group("combat_projectiles").size()
	ranged.set_physics_process(true)
	await _physics_frames(30)
	ranged.set_physics_process(false)
	_check(get_tree().get_nodes_in_group("combat_projectiles").size() == stones_before, "弹弓不向墙后目标出手")
	var stone := _fire_stone(outskirts, Vector2(-860, 500), 6000.0)
	await _physics_frames(3)
	_check(enemy.hp == enemy.max_hp and not is_instance_valid(stone), "石弹同帧先遇墙时不命中墙后敌人")
	wall.queue_free()
	await _physics_frames(2)
	stone = _fire_stone(outskirts, Vector2(-900, 500), 6000.0)
	await _physics_frames(3)
	_check(enemy.hp == enemy.max_hp - 1 and not is_instance_valid(stone), "高速石弹不漏判薄目标")
	var hp_before_melee: int = enemy.hp
	melee.set_physics_process(true)
	await _physics_frames(60)
	_check(not is_instance_valid(enemy) or enemy.hp < hp_before_melee, "无遮挡时木棍正常命中")


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _test_progress_store() -> void:
	const Store := preload("res://scripts/save/progress_store.gd")
	var ids := ProgressState.known_item_ids()
	var store := Store.new("user://test_progress.json")
	store.delete_files_for_tests()
	var data := {
		"schema_version": 1,
		"location": {"scene_id": "village", "entry_id": "from_outskirts"},
		"items": {"item_test_material": 2},
		"claimed_objects": ["outskirts.test_object"],
	}
	_check(store.save_data(data, ids), "进度正常保存")
	var loaded := store.load_data(ids)
	_check(loaded.status == Store.LoadStatus.OK and loaded.data.items == {"item_test_material": 2} \
		and loaded.data.claimed_objects == ["outskirts.test_object"] and loaded.data.location.entry_id == "from_outskirts", "进度读回一致")
	data.items.item_test_material = 3
	store.save_data(data, ids)
	_check(FileAccess.file_exists(store.backup_path) and not FileAccess.file_exists(store.temp_path), "再次保存保留上一份为备份且不残留临时文件")
	_write_text(store.main_path, "{not json")
	loaded = store.load_data(ids)
	_check(loaded.status == Store.LoadStatus.RESTORED_FROM_BACKUP and loaded.data.items.item_test_material == 2, "主文件损坏时从备份恢复")
	DirAccess.remove_absolute(store.main_path)
	loaded = store.load_data(ids)
	_check(loaded.status == Store.LoadStatus.RESTORED_FROM_BACKUP and loaded.data.items.item_test_material == 2, "主文件缺失但备份存在时恢复")
	_write_text(store.main_path, "[]")
	_write_text(store.backup_path, "garbage")
	loaded = store.load_data(ids)
	_check(loaded.status == Store.LoadStatus.CORRUPT and loaded.data == null, "主文件与备份都损坏时报告无法读取")
	store.quarantine_corrupt()
	_check(FileAccess.file_exists(store.corrupt_path) and not FileAccess.file_exists(store.main_path), "损坏文件另存，之后保存不覆盖它")
	store.delete_files_for_tests()
	var newer := JSON.stringify({"schema_version": 99, "items": {}, "claimed_objects": []})
	_write_text(store.main_path, newer)
	ProgressState.use_store_for_tests(store)
	var blocked_save := ProgressState.save_at_safe_point(&"village", &"default")
	_check(ProgressState.load_status == Store.LoadStatus.NEWER_VERSION and not blocked_save \
		and not ProgressState.has_continue() and FileAccess.get_file_as_string(store.main_path) == newer, "较新版本不读取且拒绝覆盖")
	store.delete_files_for_tests()
	_write_text(store.main_path, JSON.stringify({
		"schema_version": 1,
		"location": {"scene_id": "moon_base", "entry_id": ""},
		"items": {"item_test_material": 1.5, "item_from_future": 5},
		"claimed_objects": ["ok.id", 7, ""],
	}))
	loaded = store.load_data(ids)
	_check(loaded.status == Store.LoadStatus.OK and loaded.data.items.is_empty() and loaded.data.claimed_objects == ["ok.id"] \
		and loaded.data.location == {"scene_id": "village", "entry_id": "default"} and loaded.warnings.size() == 6, "未知 ID 与无效字段被丢弃并给出警告")
	_write_text(store.main_path, JSON.stringify({"schema_version": 1, "items": [], "claimed_objects": []}))
	_check(store.load_data(ids).status == Store.LoadStatus.CORRUPT, "字段类型错误视为损坏")
	store.delete_files_for_tests()
	data.items.item_test_material = 3
	store.save_data(data, ids)
	store.fail_commit_after_backup = true
	data.items.item_test_material = 9
	_check(not store.save_data(data, ids), "模拟提交失败时返回失败")
	store.fail_commit_after_backup = false
	loaded = store.load_data(ids)
	_check(loaded.status == Store.LoadStatus.RESTORED_FROM_BACKUP and loaded.data.items.item_test_material == 3, "提交失败后仍可恢复上一份进度")
	store.delete_files_for_tests()
	ProgressState.use_store_for_tests(store)
	ProgressState.claim_pickup(&"outskirts.snapshot_test", &"item_test_material", 1)
	var snap := ProgressState.snapshot(&"village", &"default")
	_check(snap.items == {"item_test_material": 1} and snap.claimed_objects == ["outskirts.snapshot_test"], "领取标记与数量写入同一快照")
	_check(ProgressState.save_at_safe_point(&"village", &"from_outskirts") and ProgressState.continue_location().entry_id == &"from_outskirts", "安全点保存后提供继续位置")
	store.delete_files_for_tests()
	ProgressState.use_store_for_tests(Store.new())
	ProgressState.reset()


func _test_drops_and_inventory() -> void:
	const HIDE := &"item_test_hide"
	ProgressState.reset()
	var outskirts := await _scene("res://scenes/exploration/outskirts.tscn")
	var player := outskirts.get_node("Player") as CharacterBody2D
	player.set_physics_process(false)
	_disable_weapons(player)
	var enemy := outskirts.get_node("BranchEnemy") as CharacterBody2D
	enemy.set_physics_process(false)
	enemy.global_position = Vector2(300, 300)
	await get_tree().physics_frame
	enemy.take_damage(99)
	await get_tree().process_frame
	await get_tree().process_frame
	var drops := get_tree().get_nodes_in_group("inspectable_items").filter(func(node): return node.object_id == &"")
	_check(drops.size() == 1 and drops[0].item.item_id == HIDE and drops[0].global_position.distance_to(Vector2(300, 300)) < 1.0, "野兽死亡在原地生成掉落物")
	var drop: Node2D = drops[0]
	var popup := outskirts.get_node("UI/ItemDetailPopup")
	popup.follow_mouse = false
	popup.update_for_world_point(drop.global_position + Vector2(5, 5))
	_check(popup.is_showing() and popup.current_target == drop and popup.get_node("Panel/VBox/NameLabel").text == "兽皮（测试掉落）" \
		and popup.get_node("Panel/VBox/HintLabel").text == "靠近后按 E 拾取", "指向掉落物显示详情场景")
	popup.update_for_world_point(drop.global_position + Vector2(200, 0))
	_check(not popup.is_showing(), "指针移开后隐藏详情")
	player.set_physics_process(true)
	player.global_position = Vector2(300, 380)
	await _hold("move_up", 20)
	popup.update_for_world_point(drop.global_position)
	_check(popup.get_node("Panel/VBox/HintLabel").text == "按 E 拾取", "进入拾取范围后详情提示可拾取")
	await _press_action("interact")
	_check(ProgressState.item_count(HIDE) == 1 and (not is_instance_valid(drop) or drop.is_queued_for_deletion()), "拾取掉落物进入背包（数量 %d）" % ProgressState.item_count(HIDE))
	popup.update_for_world_point(Vector2(300, 300))
	_check(not popup.is_showing(), "已拾取的掉落物不再显示详情")
	var second := preload("res://scenes/exploration/world_drop.tscn").instantiate()
	second.item = preload("res://data/items/item_test_hide.tres")
	second.amount = 2
	outskirts.add_child(second)
	second.global_position = player.global_position
	await _physics_frames(2)
	await _press_action("interact")
	_check(ProgressState.item_count(HIDE) == 3, "同种掉落物数量叠加")
	var inventory := outskirts.get_node("InventoryPanel")
	await _press_action("inventory")
	_check(inventory.is_open() and inventory.row_texts() == PackedStringArray(["兽皮（测试掉落） ×3"]) \
		and inventory.detail_text().contains("掉落规则和用途未定"), "I 打开背包场景，列出持有物与说明")
	await _press_action("ui_cancel")
	_check(not inventory.is_open() and not get_tree().paused, "关闭背包且不触发暂停")
	get_tree().paused = true
	await _press_action("inventory")
	_check(not inventory.is_open(), "暂停时背包不响应")
	get_tree().paused = false
	await _press_action("inventory")
	ProgressState.add_item(&"item_test_material", 1)
	_check(inventory.row_texts().size() == 2 and inventory.row_texts()[0] == "测试材料 ×1", "背包打开时随持有物变化刷新")
	_check(not ProgressState.add_item(&"no_such_item", 1) and not ProgressState.add_item(HIDE, 0), "未知物品或无效数量不进背包")
	await _press_action("inventory")
	_check(not inventory.is_open(), "再次按 I 关闭背包")
	var village := await _scene("res://scenes/village/village.tscn")
	await _press_action("inventory")
	_check(village.get_node("InventoryPanel").is_open() and village.get_node("InventoryPanel").row_texts().size() == 2, "村落使用同一背包场景")
	_check(ProgressState.snapshot(&"village", &"default").items == {"item_test_hide": 3, "item_test_material": 1}, "掉落物进入存档快照")
	ProgressState.reset()


func _wait_state(actions: Node, wanted: int, max_frames: int = 90) -> bool:
	for i in max_frames:
		if actions.state == wanted:
			return true
		await get_tree().physics_frame
	return actions.state == wanted


func _test_manual_actions() -> void:
	const S := ActionController.State
	SettingsStore.set_auto_attack(false, false)
	var training := await _scene("res://scenes/exploration/action_training.tscn")
	var player := training.get_node("Player") as CharacterBody2D
	var actions := training.get_node("Player/ActionController")
	var dummy := training.get_node("Dummy")
	var hazard := training.get_node("Hazard")
	hazard.set_physics_process(false)
	var combos := [["move_right"], ["move_left"], ["move_up"], ["move_down"],
		["move_right", "move_down"], ["move_right", "move_up"], ["move_left", "move_down"], ["move_left", "move_up"]]
	var moves_ok := true
	for combo in combos:
		player.global_position = Vector2(-100, 150)
		var expected := Vector2.ZERO
		for action in combo:
			Input.action_press(action)
			expected += {"move_right": Vector2.RIGHT, "move_left": Vector2.LEFT, "move_up": Vector2.UP, "move_down": Vector2.DOWN}[action]
		await _physics_frames(6)
		moves_ok = moves_ok and player.velocity.normalized().dot(expected.normalized()) > 0.99 and absf(player.velocity.length() - player.move_speed) < 1.0
		for action in combo:
			Input.action_release(action)
	await _physics_frames(2)
	_check(moves_ok, "四方向与斜向移动方向、速度正确")
	player.global_position = Vector2(110, 0)
	await _physics_frames(40)
	_check(dummy.hp == dummy.max_hp, "自动攻击默认关闭时武器不出手")
	actions.test_aim_point = dummy.global_position
	await _press_action("attack")
	_check(actions.attack_count == 1 and actions.is_attacking(), "左键发起一次攻击")
	var windup_clean := true
	while actions.state == S.WINDUP:
		windup_clean = windup_clean and dummy.hp == dummy.max_hp
		await get_tree().physics_frame
	_check(windup_clean, "前摇阶段不造成伤害")
	await _wait_state(actions, S.RECOVERY)
	_check(dummy.hp == dummy.max_hp - 1, "生效阶段对目标只造成一次伤害")
	await _wait_state(actions, S.IDLE)
	_check(dummy.hp == dummy.max_hp - 1, "后摇不再造成伤害并回到待机")
	actions.test_aim_point = player.global_position + Vector2(-100, 0)
	await _physics_frames(1)
	await _press_action("attack")
	await _wait_state(actions, S.IDLE)
	_check(dummy.hp == dummy.max_hp - 1, "只命中瞄准扇形内的目标")
	actions.test_aim_point = dummy.global_position
	var dodges_before: int = actions.dodge_count
	await _press_action("attack")
	await _press_action("dodge")
	var no_cancel: bool = (actions.state == S.WINDUP or actions.state == S.ACTIVE) and actions.dodge_count == dodges_before
	while actions.state == S.WINDUP or actions.state == S.ACTIVE:
		no_cancel = no_cancel and actions.dodge_count == dodges_before
		await get_tree().physics_frame
	_check(no_cancel, "前摇与生效阶段不能被闪避取消")
	await _wait_state(actions, S.IDLE)
	var attacks_before: int = actions.attack_count
	await _press_action("attack")
	await _wait_state(actions, S.ACTIVE)
	await _press_action("dodge")
	_check(actions.state == S.ACTIVE or actions.state == S.RECOVERY or actions.state == S.DODGE, "生效中按闪避不打断生效")
	await _wait_state(actions, S.DODGE, 30)
	_check(actions.state == S.DODGE and dummy.hp == dummy.max_hp - 3, "后摇可被缓冲的闪避取消，且命中已先结算")
	await _wait_state(actions, S.IDLE)
	await _physics_frames(15)
	attacks_before = actions.attack_count
	await _press_action("attack")
	for i in 5:
		await _press_action("attack")
	await _physics_frames(120)
	_check(actions.attack_count - attacks_before <= 2 and actions.state == S.IDLE and not actions.has_buffered_action(), "输入缓冲只保留一格，不无限排队")
	dodges_before = actions.dodge_count
	var start_position := player.global_position
	for i in 3:
		await _press_action("dodge")
		await _wait_state(actions, S.IDLE)
		await _physics_frames(12)
	_check(actions.dodge_count - dodges_before == 3 and player.global_position.distance_to(start_position) > 100.0, "连续三次闪避都能执行（无耐力消耗）")
	hazard.set_physics_process(true)
	actions.test_aim_point = hazard.global_position + Vector2(0, 300)
	player.global_position = hazard.global_position
	var hp_before: int = player.hp
	var strikes: int = hazard.strike_count
	var dodged := false
	for i in 240:
		await get_tree().physics_frame
		var left: float = hazard.time_to_strike()
		if not dodged and left >= 0.0 and left < 0.1:
			actions.request(&"dodge")
			dodged = true
		if hazard.strike_count > strikes:
			break
	_check(dodged and hazard.strike_count > strikes and player.hp == hp_before, "预警结束前闪避可避开测试攻击")
	await _wait_state(actions, S.IDLE)
	player.global_position = hazard.global_position
	strikes = hazard.strike_count
	for i in 240:
		await get_tree().physics_frame
		if hazard.strike_count > strikes:
			break
	_check(player.hp == hp_before - 1, "不闪避会被测试攻击命中")
	hazard.set_physics_process(false)
	await _wait_state(actions, S.IDLE)
	await _physics_frames(45)
	actions.test_aim_point = dummy.global_position
	await _press_action("attack")
	player.take_damage(1)
	_check(actions.state == S.HURT and not actions.has_buffered_action(), "受击打断攻击并清空缓冲")
	await _wait_state(actions, S.IDLE, 30)
	Input.action_press("move_down")
	await _physics_frames(3)
	Input.action_release("move_down")
	_check(actions.state == S.IDLE and player.velocity.length() > 0.0, "受击硬直后恢复控制")
	await _physics_frames(45)
	await _press_action("attack")
	await _wait_state(actions, S.ACTIVE)
	actions.request(&"attack")
	get_tree().paused = true
	await _press_action("attack")
	await get_tree().process_frame
	var paused_attacks: int = actions.attack_count
	get_tree().paused = false
	await _physics_frames(60)
	_check(actions.attack_count == paused_attacks and actions.state == S.IDLE, "暂停清空缓冲，暂停期间的输入不执行")
	await _press_action("auto_attack_toggle")
	_check(SettingsStore.is_auto_attack_enabled() and training.get_node("Player/ActionController/AutoLabel").visible, "T 打开自动攻击辅助")
	await _press_action("auto_attack_toggle")
	_check(not SettingsStore.is_auto_attack_enabled(), "T 再次关闭自动攻击辅助")
	player.take_damage(999)
	var dead_attacks: int = actions.attack_count
	await _press_action("attack")
	await _press_action("dodge")
	_check(actions.state == S.DEAD and actions.attack_count == dead_attacks, "死亡后不再响应攻击与闪避")
	training = await _scene("res://scenes/exploration/action_training.tscn")
	actions = training.get_node("Player/ActionController")
	_check(actions.state == S.IDLE and actions.attack_count == 0 and not actions.has_buffered_action(), "换场后动作状态不残留")


func _test_layers(body: Sprite2D) -> void:
	var initial_child_count := body.get_child_count()
	body.update_motion(Vector2.UP, 0.1)
	var no_z := true
	for child in body.get_children():
		no_z = no_z and child.z_index == 0
	_check(no_z and body._layers["hair"].get_index() > body._layers["head"].get_index() and body._layers["held_weapon"].show_behind_parent, "外观层用子节点顺序排序，不脱离世界 Y 排序")
	body.update_motion(Vector2.DOWN, 0.1)
	_check(not body._layers["held_weapon"].show_behind_parent, "朝下时弹弓回到身体前方")
	_check(body.profile.profile_id == "ulpc_walk_v1" and body.hframes == 9 and body.vframes == 4, "战斗角色使用 ULPC 9x4 协议")
	_check(body.profile.frame_for("walk", "right", 0.1) == Vector2i(1, 2), "ULPC 行方向映射")
	var layer := LayerDefinition.new()
	layer.item_id = "test_overlay"
	layer.layer_id = "test"
	layer.profile_id = body.profile.profile_id
	layer.texture = body.texture # 仅测试同步协议，不当作衣服素材交付。
	_check(body.equip_layer(layer), "兼容图层装备")
	body.update_motion(Vector2.RIGHT, 0.2)
	var overlay: Sprite2D = body._layers["test"]
	_check(overlay.frame_coords == body.frame_coords and overlay.offset == body.offset, "身体图层同步帧和锚点")
	_check(body.equip_layer(layer) and body.get_child_count() == initial_child_count + 1, "重复装备替换而非堆叠")
	var snapshot: Dictionary = body.equipped_ids()
	snapshot.clear()
	_check(body.equipped_ids().has("test"), "外观状态快照不暴露内部容器")
	var invalid := LayerDefinition.new()
	invalid.item_id = "bad"
	invalid.layer_id = "test"
	invalid.texture = body.texture
	invalid.profile_id = "incompatible"
	_check(not body.equip_layer(invalid) and body.equipped_ids()["test"] == "test_overlay", "不兼容图集拒绝且保留旧装备")
	body.remove_layer("test")
	_check(body.get_child_count() == initial_child_count and not body.equipped_ids().has("test"), "卸下立即清除指定渲染层与状态")
	var custom := Profile.new()
	custom.grid = Vector2i(13, 21)
	custom.clips = {"walk_right": [Vector2i(1, 11), Vector2i(2, 11)]}
	_check(custom.frame_for("walk", "right", 0.15) == Vector2i(2, 11), "可配置其他图集帧布局")


func _test_waves(arena: Node, interval: int) -> void:
	var manager := arena.get_node("WaveManager")
	for wave in 3:
		manager._start_next_wave()
		manager._spawn_one_enemy()
		for enemy in get_tree().get_nodes_in_group("enemies"):
			enemy.take_damage(999)
		await get_tree().process_frame
		manager._phase = "clearing"
		manager._to_spawn = 0
		manager._physics_process(0.01)
		if wave < 2:
			var expected := "extracting" if (wave + 1) % interval == 0 else "adjusting"
			_check(manager._phase == expected, "撤离节奏 %d 第 %d 波" % [interval, wave + 1])
			if expected == "extracting":
				manager.complete_extraction_continue()
			_check(manager._phase == "adjusting" and get_tree().paused, "波间构筑暂停")
			manager.complete_build_adjustment()
			_check(not get_tree().paused and manager._phase == "between", "构筑确认继续")
	_check(manager._phase == "boss", "三波之后进入野猪王")
	var boss := get_tree().get_first_node_in_group("boar_king")
	_check(boss != null and Targeting.is_live_target(boss), "首领接受共享伤害接口")
	var old_hp: int = boss.hp
	Targeting.hit(boss, 1)
	_check(boss.hp == old_hp - 1, "通用武器伤害实际扣除首领生命")
	boss.take_damage(999)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(arena.get_node("RunStats").boar_defeated and arena.get_node("RunStats").outcome_label() == "狩猎成功", "首领胜利及统计")
	_check(arena.get_node("CombatHUD/Root/ResultPanel").visible, "胜利结果面板")


func _load_resources(path: String) -> void:
	for file_name in DirAccess.get_files_at(path):
		if file_name.get_extension() in ["gd", "tscn", "tres"]:
			_check(load(path.path_join(file_name)) != null, "加载 " + path.path_join(file_name))
	for directory in DirAccess.get_directories_at(path):
		_load_resources(path.path_join(directory))
