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
	var hunter = village.get_node("VillagePlayer/Sprite2D")
	_check(hunter.texture != null and hunter.hframes == 4 and hunter.vframes == 4, "城镇猎人图集已加载")
	hunter.update_motion(Vector2.ZERO, 0.1)
	_check(hunter.state == "idle" and hunter.frame_coords == Vector2i(0, 0), "城镇猎人待机朝下")
	hunter.update_motion(Vector2.RIGHT, 0.2)
	_check(hunter.state == "walk" and hunter.frame_coords.y == 2, "城镇猎人向右走路")
	hunter.play_attack(Vector2.UP)
	_check(hunter.state == "attack" and hunter.frame_coords == Vector2i(3, 3), "城镇猎人向上攻击")
	await get_tree().physics_frame
	var space: PhysicsDirectSpaceState2D = village.get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.collision_mask = 16
	query.collide_with_areas = false
	query.position = village.get_node("WeaponHouse").global_position + Vector2(0, -40)
	_check(not space.intersect_point(query).is_empty(), "房屋碰撞挡住玩家")
	var town_tree: Node2D = village.get_node("TownTree_00")
	query.position = town_tree.global_position + Vector2(0, -8)
	_check(not space.intersect_point(query).is_empty(), "树墩有碰撞")
	query.position = town_tree.global_position + Vector2(30, -100)
	_check(space.intersect_point(query).is_empty(), "树冠没有碰撞")
	var weapon_door := village.get_node("WeaponDoor")
	weapon_door._set_occupied(village.get_node("VillagePlayer"), true)
	var interact := InputEventAction.new()
	interact.action = "interact"
	interact.pressed = true
	village._unhandled_input(interact)
	var shop := village.get_node("ShopPanel")
	_check(shop.is_open() and shop.row_count() == 2, "武器铺列出物品表里的剑")
	shop.close()
	weapon_door._set_occupied(village.get_node("VillagePlayer"), false)
	var synthesis_door := village.get_node("SynthesisDoor")
	synthesis_door._set_occupied(village.get_node("VillagePlayer"), true)
	village._unhandled_input(interact)
	_check(shop.is_open() and shop.row_count() == 1, "合成铺列出素材")
	shop.close()
	village._open_expedition_overlay()
	_check(village.get_node("UI/ExpeditionOverlay").visible, "村落出征入口")
	village._on_close_expedition_overlay()
	var arena := await _arena()
	var combat_sprite = arena.get_node("Player/Sprite2D")
	_check(combat_sprite.hframes == 4 and combat_sprite.vframes == 4, "竞技场玩家使用猎人图")
	combat_sprite.play_attack(Vector2.RIGHT)
	_check(combat_sprite.state == "attack" and combat_sprite.frame_coords == Vector2i(3, 2), "战斗攻击切到猎人攻击帧")
	combat_sprite.update_motion(Vector2.ZERO, 1.0)
	_test_combat(arena)
	_test_layers(_layered_fixture())
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
	await _test_sword_attacks()
	await _test_developer_panel()
	await _test_wolf()
	await _test_armor()
	await _test_item_catalog()
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
	var second := preload("res://scenes/props/world_drop.tscn").instantiate()
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
	_check(dummy.hp == dummy.max_hp - 1, "只命中瞄准方向上的目标")
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


func _hold_action(action: String) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame


func _release_action(action: String) -> void:
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _test_sword_attacks() -> void:
	const S := ActionController.State
	const Volume := preload("res://scripts/combat/melee_attack_volume.gd")
	const SwordData := preload("res://scripts/combat/sword_attack_data.gd")
	const AttackDef := preload("res://scripts/combat/melee_attack_definition.gd")
	const Keyframe := preload("res://scripts/combat/melee_hit_keyframe.gd")
	var gap := AttackDef.new()
	gap.attack_id = "gap"
	gap.keyframes = [_keyframe(Keyframe, 0.0, Vector2(0, -50), 8.0), _keyframe(Keyframe, 1.0, Vector2(0, 50), 8.0)]
	var endpoints := [Volume.sample_at(gap, Vector2.ZERO, Vector2.RIGHT, 0.0), Volume.sample_at(gap, Vector2.ZERO, Vector2.RIGHT, 1.0)]
	var thin := Vector2(0, 0)
	_check(endpoints[0].center.distance_to(thin) > float(endpoints[0].radius) + 2.0 \
		and endpoints[1].center.distance_to(thin) > float(endpoints[1].radius) + 2.0 \
		and Volume.overlaps(Volume.samples_between(gap, Vector2.ZERO, Vector2.ZERO, Vector2.RIGHT, 0.0, 1.0), thin, 2.0),
		"大步长扫掠命中两端圆之间的薄目标")
	var shifted := Volume.samples_between(gap, Vector2(-90, 0), Vector2(90, 0), Vector2.RIGHT, 0.0, 1.0)
	_check(shifted[0].center.distance_to(thin) > float(shifted[0].radius) + 2.0 \
		and shifted[-1].center.distance_to(thin) > float(shifted[-1].radius) + 2.0 \
		and Volume.overlaps(shifted, thin, 2.0),
		"高移速下扫掠命中中途目标")
	var facing_right: Vector2 = Volume.sample_at(SwordData.combo_attacks()[0], Vector2.ZERO, Vector2.RIGHT, 0.0).center
	var facing_left: Vector2 = Volume.sample_at(SwordData.combo_attacks()[0], Vector2.ZERO, Vector2.LEFT, 0.0).center
	_check(facing_right.x > 10.0 and facing_left.x < -10.0, "转向时判定区域跟着朝向翻转")
	var sword: WeaponDefinition = load("res://data/build/weapon_sword.tres")
	_check(sword.weapon_id == "weapon_sword" and sword.damage == 1, "剑伤害来自武器定义")

	SettingsStore.set_auto_attack(false, false)
	var training := await _scene("res://scenes/exploration/action_training.tscn")
	var player := training.get_node("Player") as CharacterBody2D
	var actions := training.get_node("Player/ActionController")
	var hazard := training.get_node("Hazard")
	hazard.set_physics_process(false)
	player.set_physics_process(false)
	var dummy := training.get_node("Dummy")
	var other := training.get_node("DummyB")
	dummy.set_physics_process(false)
	other.set_physics_process(false)
	_place_sword_targets(player, dummy, other, Vector2(52, -22), Vector2(52, 22))
	actions.test_aim_point = player.global_position + Vector2(300, 0)
	await _press_action("attack")
	_check(actions.state == S.WINDUP and actions.hit_samples().is_empty() and dummy.hp == dummy.max_hp, "剑前摇不造成伤害")
	await _wait_state(actions, S.ACTIVE)
	var forward: bool = actions.hit_samples().size() >= 1 and actions.visual_matches_hits()
	for sample in actions.hit_samples():
		forward = forward and (sample.center as Vector2).x > player.global_position.x + 10.0
	_check(forward, "生效调试圈与命中采样一致，且落在瞄准方向")
	await _wait_state(actions, S.RECOVERY)
	_check(dummy.hp == dummy.max_hp - 1 and other.hp == other.max_hp - 1, "一段挥砍命中两个目标且各只一次")
	_check(actions.current_attack_id() == "sword_slash_1", "第一段是独立攻击")
	await _press_action("attack")
	await _wait_state(actions, S.RECOVERY)
	_check(actions.current_attack_id() == "sword_slash_2" and dummy.hp == dummy.max_hp - 2 and other.hp == other.max_hp - 2, "第二段可以再次命中")
	await _press_action("attack")
	await _wait_state(actions, S.RECOVERY)
	_check(actions.current_attack_id() == "sword_slash_3" and dummy.hp == dummy.max_hp - 3 and other.hp == other.max_hp - 3, "第三段可以再次命中")
	await _wait_state(actions, S.IDLE)
	_check(dummy.hp == dummy.max_hp - 3 and other.hp == other.max_hp - 3, "后摇不再造成伤害")

	_place_sword_targets(player, dummy, other, Vector2(52, -22), Vector2(52, 22))
	actions.test_aim_point = player.global_position + Vector2(-300, 0)
	await _press_action("attack")
	await _wait_state(actions, S.ACTIVE)
	var turned: bool = actions.hit_samples().size() > 0
	for sample in actions.hit_samples():
		turned = turned and (sample.center as Vector2).x < player.global_position.x - 10.0
	await _wait_state(actions, S.IDLE)
	_check(turned and dummy.hp == dummy.max_hp and other.hp == other.max_hp, "反向挥砍落空")

	_place_sword_targets(player, dummy, other, Vector2(52, -22), Vector2(52, 22))
	actions.test_aim_point = player.global_position + Vector2(300, 0)
	await _press_action("attack")
	var opened := false
	for i in 90:
		if actions.recovery_cancel_open():
			opened = true
			break
		await get_tree().physics_frame
	var attacks_before: int = actions.attack_count
	actions.request(&"dodge")
	_check(opened and actions.state == S.DODGE and actions.combo_index() == 0, "后摇后段闪避取消连击")
	await _release_action("attack")
	await _wait_state(actions, S.IDLE)
	await _physics_frames(12)
	await _press_action("attack")
	_check(actions.current_attack_id() == "sword_slash_1" and actions.attack_count == attacks_before + 1, "取消后下一次从第一段开始")
	await _wait_state(actions, S.IDLE)

	_place_sword_targets(player, dummy, other, Vector2(52, -22), Vector2(52, 22))
	actions.test_aim_point = player.global_position + Vector2(300, 0)
	await _hold_action("attack")
	var charging := false
	for i in 40:
		await get_tree().physics_frame
		if actions.state == S.CHARGE:
			charging = true
			break
	_check(charging and dummy.hp == dummy.max_hp and other.hp == other.max_hp, "蓄力期间不造成伤害")
	attacks_before = actions.attack_count
	actions.request(&"dodge")
	await _release_action("attack")
	await _wait_state(actions, S.IDLE)
	await _physics_frames(8)
	_check(actions.attack_count == attacks_before and dummy.hp == dummy.max_hp and other.hp == other.max_hp, "闪避放弃蓄力，松手不再斩出")

	_place_sword_targets(player, dummy, other, Vector2(52, -22), Vector2(52, 22))
	await _hold_action("attack")
	charging = false
	for i in 40:
		await get_tree().physics_frame
		if actions.state == S.CHARGE:
			charging = true
			break
	await _release_action("attack")
	var saw_charge := false
	for i in 90:
		if actions.current_attack_id() == "sword_charge":
			saw_charge = true
		if saw_charge and actions.state == S.IDLE:
			break
		await get_tree().physics_frame
	_check(charging and saw_charge and dummy.hp == dummy.max_hp - 2 and other.hp == other.max_hp - 2, "蓄力斩单独结算且命中两个目标")
	_check(sword.damage == 1, "结算不改写剑的武器定义")

	_place_sword_targets(player, dummy, other, Vector2(36, 0), Vector2(400, 0))
	actions.test_aim_point = player.global_position + Vector2(300, 0)
	var slash: MeleeAttackDefinition = SwordData.combo_attacks()[0]
	var start_sample: Dictionary = Volume.sample_at(slash, player.global_position, Vector2.RIGHT, 0.0)
	var end_sample: Dictionary = Volume.sample_at(slash, player.global_position, Vector2.RIGHT, 1.0)
	var body_radius := Volume.body_radius(dummy)
	var outside_ends: bool = start_sample.center.distance_to(dummy.global_position) > float(start_sample.radius) + body_radius \
		and end_sample.center.distance_to(dummy.global_position) > float(end_sample.radius) + body_radius
	var ticks: int = get_node("/root/DeveloperPanel").set_physics_ticks(2)
	await get_tree().physics_frame
	actions.request(&"attack")
	await _wait_state(actions, S.IDLE, 8)
	get_node("/root/DeveloperPanel").set_physics_ticks(ticks)
	_check(outside_ends and dummy.hp == dummy.max_hp - 1 and other.hp == other.max_hp, "低物理帧率下整段扫掠仍命中中间目标")
	player.set_physics_process(true)


func _test_developer_panel() -> void:
	const S := ActionController.State
	var panel := get_node_or_null("/root/DeveloperPanel")
	_check(panel != null and not panel.is_open(), "开发者菜单在左侧且默认收起")
	if panel == null:
		return
	panel.set_open(true)
	_check(panel.is_open(), "开发者菜单可以展开")
	var material := &"item_test_material"
	var before := ProgressState.item_count(material)
	var saved := ProgressState.last_save_ok
	_check(panel.grant_item(material, 1), "开发者菜单可以加入已定义物品")
	_check(ProgressState.item_count(material) == before + 1, "加入的物品进入进度状态")
	_check(panel.grant_money_note() == "金钱尚未定义，没有写入存档" and ProgressState.last_save_ok == saved \
		and ProgressState.item_count(material) == before + 1, "金钱入口不写入存档")

	var training := await _scene("res://scenes/exploration/action_training.tscn")
	var player := training.get_node("Player") as CharacterBody2D
	var actions := training.get_node("Player/ActionController")
	var hazard := training.get_node("Hazard")
	hazard.set_physics_process(false)
	player.set_physics_process(false)
	actions.set_process_unhandled_input(false)
	_place_sword_targets(player, training.get_node("Dummy"), training.get_node("DummyB"), Vector2(52, -22), Vector2(52, 22))
	actions.test_aim_point = player.global_position + Vector2(300, 0)
	var placed: bool = panel.place_dummy()
	var spawned := get_tree().get_nodes_in_group("developer_dummies")
	_check(placed and spawned.size() == 1 and spawned[0].move_speed == 0.0 and spawned[0].contact_damage == 0, "开发者菜单可以放置静止木桩")
	var dummy := training.get_node("Dummy")
	var other := training.get_node("DummyB")
	_check(actions.debug_start_combo_step(2) and actions.state == S.WINDUP and actions.current_attack_id() == "sword_slash_3", "开发者菜单可以直接打出第三段")
	await _wait_state(actions, S.IDLE)
	_check(dummy.hp == dummy.max_hp - 1 and other.hp == other.max_hp - 1, "第三段命中两个目标且各只一次")
	panel.clear_dummies()
	await get_tree().process_frame
	_check(get_tree().get_nodes_in_group("developer_dummies").is_empty(), "开发者木桩可以清除")
	panel.set_open(false)
	player.set_physics_process(true)


func _test_wolf() -> void:
	var outskirts := await _scene("res://scenes/exploration/outskirts.tscn")
	var wolf: CharacterBody2D = outskirts.get_node("Wolf")
	var player := outskirts.get_node("Player") as CharacterBody2D
	var actions := player.get_node("ActionController")
	outskirts.get_node("BranchEnemy").set_physics_process(false)
	player.set_physics_process(false)
	actions.set_process_unhandled_input(false)
	await get_tree().physics_frame
	_check(not _body_hits_terrain(wolf), "野狼出生点不在墙内")

	var home: Vector2 = wolf.home_position()
	wolf.debug_velocity = Vector2(400, 0)
	wolf.global_position = Vector2(180, -250)
	var crossed := false
	for _i in 12:
		await get_tree().physics_frame
		if wolf.global_position.x > 212.0:
			crossed = true
	wolf.debug_velocity = null
	wolf.velocity = Vector2.ZERO
	wolf.global_position = home
	_check(not crossed, "野狼不穿墙")

	player.global_position = home + Vector2(0, wolf.activity_radius + 120.0)
	await _physics_frames(20)
	_check(not wolf.is_chasing(), "离开活动范围不追击")

	player.hurt_invuln_seconds = 0.0
	player._invuln_left = 0.0
	player.global_position = wolf.global_position + Vector2(28, 0)
	var hp_before: int = player.hp
	var bitten := false
	var repeated := false
	for _i in 120:
		await get_tree().physics_frame
		if player.hp < hp_before:
			bitten = true
			var once: int = player.hp
			for _j in 15:
				await get_tree().physics_frame
			repeated = player.hp < once
			break
	_check(bitten and not repeated, "撕咬持续重叠只结算一次")

	wolf.set_physics_process(false)
	wolf.hp = wolf.max_hp
	player.global_position = wolf.global_position + Vector2(-60, 0)
	actions.test_aim_point = wolf.global_position
	var before: int = wolf.hp
	_check(actions.debug_start_combo_step(0), "可以对野狼打出剑")
	await _wait_state(actions, ActionController.State.IDLE)
	_check(wolf.hp == before - 1, "剑可以打中野狼")
	var deaths := {"n": 0}
	wolf.defeated.connect(func() -> void: deaths.n += 1)
	wolf.take_damage(999)
	wolf.take_damage(999)
	_check(int(deaths.n) == 1, "野狼死亡事件只发一次")


func _test_armor() -> void:
	var training := await _scene("res://scenes/exploration/action_training.tscn")
	var player := training.get_node("Player") as CharacterBody2D
	var actions := training.get_node("Player/ActionController")
	var target := training.get_node("ArmoredTarget")
	var dummy := training.get_node("Dummy")
	training.get_node("Hazard").set_physics_process(false)
	training.get_node("DummyB").set_physics_process(false)
	dummy.set_physics_process(false)
	player.set_physics_process(false)
	actions.set_process_unhandled_input(false)

	var before: int = dummy.hp
	dummy.take_damage(1)
	_check(dummy.hp == before - 1 and not dummy.has_method("receive_hit"), "无甲目标仍按原伤害结算")

	target.refill()
	target.receive_hit(2, 1)
	_check(target.hp == target.max_hp - 1 and target.armor_value == 1 and not target.broken, "未破甲时先按护甲减伤结算")
	target.refill()
	target.receive_hit(1, 1)
	target.receive_hit(1, 1)
	_check(target.hp == target.max_hp and target.armor_value == 2 and not target.broken, "护甲可以把伤害降到零并积累破甲")
	target.receive_hit(1, 1)
	_check(target.hp == target.max_hp and target.broken and target.armor_value == 0, "触发破甲的一击仍按破甲前防护结算")
	target.receive_hit(1, 9)
	_check(target.hp == target.max_hp - 1 and target.broken and target.armor_value == 0, "破甲期间造成全额伤害且不积累下一轮")
	target._break_left = 0.05
	await _physics_frames(12)
	_check(not target.broken and target.armor_value == 0, "破甲结束恢复护甲并重置破甲值")
	var hp_after: int = target.hp
	target.receive_hit(1, 1)
	_check(target.hp == hp_after and target.armor_value == 1 and not target.broken, "护甲恢复后再次减伤")

	player.global_position = Vector2(0, 40)
	dummy.global_position = Vector2(800, 800)
	training.get_node("DummyB").global_position = Vector2(900, 800)
	target.refill()
	target.global_position = player.global_position + Vector2(52, -22)
	actions.test_aim_point = player.global_position + Vector2(300, 0)
	_check(actions.debug_start_combo_step(0), "可以对装甲目标挥剑")
	await _wait_state(actions, ActionController.State.IDLE)
	_check(target.hp == target.max_hp and target.armor_value == 1 and not target.broken, "剑的破甲贡献进入装甲目标")

	var starts := {"n": 0}
	target.break_started.connect(func() -> void: starts.n += 1)
	target.hp = 1
	target.armor_value = target.armor_break_threshold - 1
	target.broken = false
	target.receive_hit(target.max_hp + target.armor_reduction, 10)
	_check(target.hp == 0 and not target.broken and int(starts.n) == 0, "死亡不再触发破甲")


func _test_item_catalog() -> void:
	const Catalog := preload("res://scripts/items/item_catalog.gd")
	const Link := preload("res://scripts/items/weapon_effect_link.gd")
	var training_sword: Dictionary = Catalog.get_item(&"sword_training")
	var hunter_sword: Dictionary = Catalog.get_item(&"sword_hunter")
	var fiber: Dictionary = Catalog.get_item(&"material_fiber")
	_check(training_sword.get("category_id") == "weapon" and training_sword.get("group_id") == "sword" \
		and int(training_sword.get("attack", 0)) == 1, "试验短剑在武器大类、剑中类下")
	_check(fiber.get("category_id") == "material" and fiber.get("group_id") == "fiber", "素材大类可以登记具体物品")
	var combo: Dictionary = Link.resolve(&"sword_training")
	var heavy: Dictionary = Link.resolve(&"sword_hunter")
	_check(combo.get("id") == "effect_sword_combo" and combo.get("attack_style") == "combo_slash", "试验短剑连到三段斩特效")
	_check(heavy.get("id") == "effect_sword_heavy" and heavy.get("attack_style") == "heavy_slash" \
		and int(hunter_sword.get("attack", 0)) == 2, "猎手短剑连到另一种特效")
	_check(Link.resolve(&"material_fiber").is_empty(), "素材不套用武器特效")
	_check(ProgressState.add_item(&"material_fiber", 1) and ProgressState.item_count(&"material_fiber") == 1, "物品表里的素材可以进背包")

	var training := await _scene("res://scenes/exploration/action_training.tscn")
	var player := training.get_node("Player") as CharacterBody2D
	var actions := training.get_node("Player/ActionController")
	training.get_node("Hazard").set_physics_process(false)
	player.set_physics_process(false)
	actions.set_process_unhandled_input(false)
	var enemy := preload("res://scenes/combat/enemy.tscn").instantiate()
	enemy.move_speed = 0.0
	enemy.contact_damage = 0
	enemy.max_hp = 1
	enemy.drop_item_id = &"sword_hunter"
	enemy.drop_amount = 1
	training.add_child(enemy)
	enemy.global_position = player.global_position + Vector2(90, 0)
	var before: int = ProgressState.item_count(&"sword_hunter")
	enemy.take_damage(5)
	await get_tree().process_frame
	await get_tree().process_frame
	var drop: Node = null
	for node in training.get_children():
		if node.has_method("try_pickup") and node.get("item") != null and node.item.item_id == &"sword_hunter":
			drop = node
			break
	_check(drop != null, "击倒后按物品表生成掉落")
	if drop != null:
		drop.global_position = player.global_position
		drop._on_body_entered(player)
		_check(drop.try_pickup(), "掉落物可以拾取")
	_check(ProgressState.item_count(&"sword_hunter") == before + 1, "掉落的剑进入背包")
	_check(ProgressState.get_definition(&"sword_hunter").display_name == "猎手短剑", "背包能读到物品表里的名字")
	actions.weapon_item_id = &"sword_hunter"
	_check(actions.effect_attack_style() == "heavy_slash", "换上猎手短剑后攻击方式跟着特效变")
	actions.request(&"attack")
	_check(actions.current_attack_id() == "sword_charge", "重斩特效点按打出单次重斩")
	actions.weapon_item_id = &"sword_training"
	_check(actions.effect_attack_style() == "combo_slash", "换回试验短剑后恢复三段斩")


func _body_hits_terrain(body: CharacterBody2D) -> bool:
	var shape_node := body.get_node("CollisionShape2D") as CollisionShape2D
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape_node.shape
	params.transform = shape_node.global_transform
	params.collision_mask = 16
	params.exclude = [body.get_rid()]
	return not body.get_world_2d().direct_space_state.intersect_shape(params, 1).is_empty()


func _keyframe(keyframe_script: GDScript, time: float, offset: Vector2, radius: float) -> Resource:
	var keyframe: Resource = keyframe_script.new()
	keyframe.time = time
	keyframe.offset = offset
	keyframe.radius = radius
	return keyframe


func _place_sword_targets(player: Node2D, first: Node2D, second: Node2D, first_offset: Vector2, second_offset: Vector2) -> void:
	player.global_position = Vector2(0, 40)
	first.global_position = player.global_position + first_offset
	second.global_position = player.global_position + second_offset
	first.hp = first.max_hp
	second.hp = second.max_hp


func _layered_fixture() -> Sprite2D:
	var body := Sprite2D.new()
	body.name = "LayerFixture"
	body.set_script(preload("res://scripts/appearance/layered_character.gd"))
	body.texture = load("res://assets/ulpc/player/body_male_walk.png")
	body.profile = load("res://data/appearance/ulpc_profile.tres")
	body.initial_layer_paths = PackedStringArray([
		"res://data/appearance/ulpc_head.tres",
		"res://data/appearance/ulpc_hair.tres",
		"res://data/appearance/ulpc_shirt.tres",
		"res://data/appearance/ulpc_pants.tres",
		"res://data/appearance/ulpc_sandals.tres",
		"res://data/appearance/ulpc_slingshot.tres",
	])
	body.position = Vector2(-4000, -4000)
	add_child(body)
	return body


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
