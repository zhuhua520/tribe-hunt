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
	player.get_node("EquippedAutoWeapon").set_physics_process(false)
	return arena


func _enemy(arena: Node, pos: Vector2) -> Node2D:
	var enemy := preload("res://scenes/combat/enemy.tscn").instantiate() as Node2D
	arena.add_child(enemy)
	enemy.position = pos
	enemy.set_physics_process(false)
	return enemy


func _run() -> void:
	reparent(get_tree().root)
	# 旧竞技场用例沿用过渡自动武器。正式战斗不看 auto_attack，这里仍只改内存。
	ActionController.manual_attack_fixture = false
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
	_check(shop.is_open() and shop.row_count() == 6, "武器铺列出剑、锤、弓和火铳")
	shop.close()
	weapon_door._set_occupied(village.get_node("VillagePlayer"), false)
	var synthesis_door := village.get_node("SynthesisDoor")
	synthesis_door._set_occupied(village.get_node("VillagePlayer"), true)
	village._unhandled_input(interact)
	var craft := village.get_node("CraftPanel")
	_check(not shop.is_open() and craft.is_open() and craft.row_count() == 2, "合成铺打开配方页")
	_check(craft.detail_text().contains("试验火铳") and craft.detail_text().contains("需要图纸"), "没图纸时配方页写出锁定原因")
	craft.close()
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
	await _test_formal_auto_entry()
	await _test_hit_resolution()
	await _test_build_loadout()
	await _test_build_mechanics()
	await _test_build_sources()
	await _test_loot_tables()
	await _test_random_affixes()
	await _test_hammer()
	await _test_bow()
	await _test_gun()
	await _test_deep_armor()
	await _test_sentry()
	await _test_wolf_king()
	await _test_forest_depths()
	await _test_boar_lair()
	await _test_facility()
	await _test_craft()
	await _test_dismantle_and_enhance()
	await _test_growth()
	await _test_ui_completeness()
	await _test_full_slice()
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
	player.get_node("EquippedAutoWeapon").set_physics_process(false)
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
	var equipped := player.get_node_or_null("EquippedAutoWeapon")
	if equipped != null:
		equipped.set_physics_process(false)


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
	_write_text(store.main_path, JSON.stringify({
		"schema_version": 1,
		"location": {"scene_id": "village", "entry_id": "default"},
		"items": {"item_test_material": 1},
		"claimed_objects": [],
	}))
	loaded = store.load_data(ids)
	_check(loaded.status == Store.LoadStatus.OK and loaded.data.equipped_weapon_id == "sword_training" \
		and loaded.data.items.item_test_material == 1 and loaded.data.build.instances.is_empty() \
		and loaded.warnings.size() == 0, "旧档迁移后使用试验短剑且保留原物品")
	store.delete_files_for_tests()
	_write_text(store.main_path, JSON.stringify({
		"schema_version": 2,
		"location": {"scene_id": "village", "entry_id": "default"},
		"items": {"item_test_material": 4},
		"claimed_objects": ["keep.me"],
		"equipped_weapon_id": "sword_training",
		"build": {
			"active_build_id": "missing_preset",
			"instances": {
				"inst_ok": {"definition_id": "core_echo", "level": 1},
				"inst_unknown": {"definition_id": "core_from_future", "level": "x"},
				"bad": 5,
			},
			"presets": [
				{"build_id": "preset_a", "name": "甲", "core": "inst_ok", "support_0": "no_such", "support_1": "inst_ok"},
				{"build_id": "preset_b", "name": "乙", "core": "inst_unknown", "support_0": "inst_haste_a", "support_1": ""},
			],
		},
	}))
	loaded = store.load_data(ids)
	var repaired: Dictionary = loaded.data.build
	var preset_a: Dictionary = repaired.presets[0]
	var warning_text := "\n".join(loaded.warnings)
	_check(loaded.status == Store.LoadStatus.OK and loaded.data.items.item_test_material == 4 \
		and loaded.data.claimed_objects == ["keep.me"] and repaired.active_build_id == "preset_a" \
		and preset_a.core == "inst_ok" and preset_a.support_0 == "" and preset_a.support_1 == "" \
		and repaired.instances.has("inst_unknown") and int(repaired.instances.inst_unknown.level) == 1 \
		and not repaired.instances.has("bad") and warning_text.contains("引用无效") \
		and warning_text.contains("保留未知组件") and warning_text.contains("忽略无效激活预设"), "无效构筑引用被修复且原物品还在")
	store.delete_files_for_tests()
	_write_text(store.main_path, JSON.stringify({
		"schema_version": 3,
		"location": {"scene_id": "village", "entry_id": "default"},
		"items": {"item_test_material": 2},
		"claimed_objects": ["keep.v3"],
		"equipped_weapon_id": "sword_hunter",
		"build": {
			"active_build_id": "preset_a",
			"instances": {
				"inst_ok": {"definition_id": "core_echo", "level": 1},
			},
			"presets": [
				{"build_id": "preset_a", "name": "甲", "core": "inst_ok", "support_0": "", "support_1": ""},
				{"build_id": "preset_b", "name": "乙", "core": "", "support_0": "", "support_1": ""},
			],
			"discovered": ["core_echo"],
		},
	}))
	loaded = store.load_data(ids)
	_check(loaded.status == Store.LoadStatus.OK and int(loaded.data.growth.level) == 1 and int(loaded.data.growth.xp) == 0 \
		and loaded.data.growth.techs.is_empty() and loaded.data.items.item_test_material == 2 \
		and loaded.data.build.instances.has("inst_ok"), "schema 3 旧档补默认成长并保留构筑")
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


func _use_manual_attack_fixture() -> void:
	ActionController.manual_attack_fixture = true
	SettingsStore.set_auto_attack(false, false)


func _test_manual_actions() -> void:
	const S := ActionController.State
	_use_manual_attack_fixture()
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
	_check(dummy.hp == dummy.max_hp, "手动夹具里旧开关关闭时过渡武器不出手")
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
	var legacy_flag := SettingsStore.is_auto_attack_enabled()
	await _press_action("auto_attack_toggle")
	await _press_action("auto_attack_toggle")
	_check(SettingsStore.is_auto_attack_enabled() == legacy_flag, "T 不再改写自动攻击设置")
	_check(actions.get_node("AutoLabel").visible and actions.get_node("AutoLabel").text.begins_with("装备："), "玩家标明当前装备")
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

	_use_manual_attack_fixture()
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

	_use_manual_attack_fixture()
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
	_use_manual_attack_fixture()
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
	_use_manual_attack_fixture()
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

	_use_manual_attack_fixture()
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


func _test_formal_auto_entry() -> void:
	ActionController.manual_attack_fixture = false
	SettingsStore.set_auto_attack(false, false)
	var training := await _scene("res://scenes/exploration/action_training.tscn")
	var player := training.get_node("Player") as CharacterBody2D
	var actions := training.get_node("Player/ActionController")
	var dummy := training.get_node("Dummy")
	var other := training.get_node("DummyB")
	training.get_node("Hazard").set_physics_process(false)
	training.get_node("ArmoredTarget").global_position = Vector2(520, 300)
	const Link := preload("res://scripts/items/weapon_effect_link.gd")
	const Catalog := preload("res://scripts/items/item_catalog.gd")
	_check(not SettingsStore.is_auto_attack_enabled(), "旧档关闭自动攻击开关")
	_check(actions.get_node("AutoLabel").visible and actions.get_node("AutoLabel").text == "装备：试验短剑", "正式玩家显示当前装备")
	_check(player.get_node("MeleeWeapon")._phase == "idle" and get_tree().get_nodes_in_group("combat_projectiles").is_empty(), "正式场景只有装备武器，木棍和弹弓不出手")
	ProgressState.reset()
	_check(ProgressState.equip_weapon(&"sword_hunter") == "未持有", "未持有的武器不能装备")
	_check(ProgressState.equip_weapon(&"material_fiber") == "不是武器，不能装备", "素材不能装备")
	other.global_position = Vector2(480, 300)
	ProgressState.add_item(&"sword_hunter", 1)
	ProgressState.add_item(&"sword_training", 1)
	var panel := training.get_node("EquipmentPanel")
	panel.open()
	var hunter_row: Node = null
	for row in panel.get_node("Root/Center/Panel/Margin/VBox/Rows").get_children():
		if row.item_id == &"sword_hunter":
			hunter_row = row
	_check(hunter_row != null and hunter_row.get_node("EquipButton").visible, "持有的武器显示装备按钮")
	var cooldown_before: float = ProgressState.attack_cooldown_left
	hunter_row.get_node("EquipButton").pressed.emit()
	_check(ProgressState.equipped_weapon_id() == &"sword_hunter" and is_equal_approx(ProgressState.attack_cooldown_left, cooldown_before), "装备页换装且不清空冷却")
	_check(panel.current_text().contains("伤害 2") and actions.get_node("AutoLabel").text == "装备：猎手短剑", "面板伤害和头顶与猎手短剑一致")
	dummy.global_position = Vector2(110, 0)
	dummy.hp = dummy.max_hp
	ProgressState.attack_cooldown_left = 0.0
	await _physics_frames(8)
	_check(dummy.hp == dummy.max_hp - 2 and get_tree().get_nodes_in_group("combat_projectiles").is_empty(), "猎手短剑按攻击力 2 扣血且没有第二把武器")
	panel.equip_from_row(&"sword_training")
	dummy.hp = dummy.max_hp
	ProgressState.attack_cooldown_left = 0.0
	await _physics_frames(8)
	_check(dummy.hp == dummy.max_hp, "试验短剑打不到猎手短剑的更远位置")
	dummy.global_position = Vector2(50, 0)
	await _physics_frames(8)
	_check(dummy.hp == dummy.max_hp - 1, "试验短剑在扇形内造成 1 点伤害")
	dummy.hp = dummy.max_hp
	ProgressState.attack_cooldown_left = 0.0
	var wall := _thin_wall(training, Vector2(25, 0), Vector2(16, 200))
	await _physics_frames(8)
	_check(dummy.hp == dummy.max_hp, "装备武器不打墙后目标")
	wall.queue_free()
	Catalog.debug_set_attack(&"sword_training", 4)
	_check(String(ProgressState.get_definition(&"sword_training").description).contains("攻击力 4"), "攻击力改动后说明一起变")
	_check(String(Link.combat_profile(&"sword_training").summary).contains("伤害 4"), "面板摘要使用同一攻击力")
	dummy.hp = dummy.max_hp
	ProgressState.attack_cooldown_left = 0.0
	await _physics_frames(8)
	_check(dummy.hp == dummy.max_hp - 4, "下一次出手使用新的攻击力")
	Catalog.debug_set_attack(&"sword_training", 1)
	ProgressState.attack_cooldown_left = 5.0
	training = await _scene("res://scenes/exploration/action_training.tscn")
	await get_tree().physics_frame
	_check(ProgressState.attack_cooldown_left <= 5.0 and ProgressState.attack_cooldown_left > 4.0, "换场不把冷却刷满")
	player = training.get_node("Player")
	actions = training.get_node("Player/ActionController")
	var attacks_before: int = actions.attack_count
	await _press_action("attack")
	_check(actions.state == ActionController.State.IDLE and actions.attack_count == attacks_before, "正式玩家左键不发动剑")
	player.global_position = Vector2(-80, 0)
	Input.action_press("move_right")
	await _physics_frames(4)
	var kept_speed: bool = absf(player.velocity.length() - player.move_speed) < 1.0
	Input.action_release("move_right")
	_check(kept_speed, "自动攻击不降低移动速度")
	dummy = training.get_node("Dummy")
	other = training.get_node("DummyB")
	other.global_position = Vector2(480, 300)
	dummy.global_position = Vector2(480, -300)
	var hp_paused: int = dummy.hp
	var stones_paused := get_tree().get_nodes_in_group("combat_projectiles").size()
	get_tree().paused = true
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().paused = false
	_check(other.hp == hp_paused and get_tree().get_nodes_in_group("combat_projectiles").size() == stones_paused, "暂停期间不新发射")
	player.global_position = Vector2(0, 0)
	other.global_position = Vector2(40, 0)
	player.get_node("MeleeWeapon").cancel_pending()
	player.get_node("RangedWeapon")._cooldown_left = 0.0
	player.get_node("RangedWeapon").set_physics_process(true)
	var stones_before := get_tree().get_nodes_in_group("combat_projectiles").size()
	await _press_action("dodge")
	var dodge_clean := true
	for _i in 8:
		await get_tree().physics_frame
		dodge_clean = dodge_clean and get_tree().get_nodes_in_group("combat_projectiles").size() == stones_before
	_check(dodge_clean and actions.attack_count == attacks_before, "闪避期间不发射，也不补放剑攻击")
	await _wait_state(actions, ActionController.State.IDLE)
	_check(actions.attack_count == attacks_before and not actions.has_buffered_action(), "闪避结束后没有积压的手动攻击")
	var stones_dead := get_tree().get_nodes_in_group("combat_projectiles").size()
	player.take_damage(999)
	await _physics_frames(10)
	_check(actions.state == ActionController.State.DEAD and get_tree().get_nodes_in_group("combat_projectiles").size() <= stones_dead, "死亡后不新发射")
	var arena := await _scene("res://scenes/combat/arena.tscn")
	var arena_player := arena.get_node("Player")
	arena_player.take_damage(999)
	await get_tree().process_frame
	await get_tree().process_frame
	var ended_stones := get_tree().get_nodes_in_group("combat_projectiles").size()
	await _physics_frames(8)
	_check(arena_player.process_mode == Node.PROCESS_MODE_DISABLED and get_tree().get_nodes_in_group("combat_projectiles").size() == ended_stones, "结果态不新发射")
	var village := await _scene("res://scenes/village/village.tscn")
	_check(village.get_node_or_null("VillagePlayer/MeleeWeapon") == null and village.get_node_or_null("VillagePlayer/RangedWeapon") == null and village.get_node_or_null("VillagePlayer/ActionController") == null, "村落没有战斗攻击入口")
	await _press_action("attack")
	await _physics_frames(8)
	_check(get_tree().get_nodes_in_group("combat_projectiles").is_empty(), "村落里按攻击键不生成弹体")


func _test_hit_resolution() -> void:
	const ContextScript := preload("res://scripts/combat/hit_context.gd")
	const Catalog := preload("res://scripts/items/item_catalog.gd")
	ActionController.manual_attack_fixture = false
	ProgressState.reset()
	ProgressState.attack_cooldown_left = 5.0
	var training := await _scene("res://scenes/exploration/action_training.tscn")
	var player := training.get_node("Player") as CharacterBody2D
	var weapon := training.get_node("Player/EquippedAutoWeapon")
	var dummy := training.get_node("Dummy")
	var other := training.get_node("DummyB")
	var armor := training.get_node("ArmoredTarget")
	training.get_node("Hazard").set_physics_process(false)
	weapon.set_physics_process(false)
	other.global_position = Vector2(480, 300)
	armor.global_position = Vector2(520, 280)
	dummy.global_position = Vector2(50, 0)
	dummy.hp = dummy.max_hp
	Catalog.debug_set_attack(&"sword_training", 9)
	var context = ContextScript.new()
	context.attack_instance_id = Targeting.begin_attack()
	context.source = player
	context.snapshot_id = "sword_training"
	context.target = dummy
	context.base_damage = 1
	context.snapshot_damage = 3
	var result = Targeting.resolve(context)
	_check(result.damage_applied == 3 and dummy.hp == dummy.max_hp - 3, "结算使用攻击开始时的伤害快照")
	Catalog.debug_set_attack(&"sword_training", 1)
	Targeting.close_attack(context.attack_instance_id)
	var hp_before_invuln: int = player.hp
	player._invuln_left = 1.0
	var healed := {"n": 0}
	var bus = Targeting.event_bus()
	var on_damage = func(hit_result, _ctx) -> void:
		if not hit_result.rejected_invulnerable:
			healed.n += hit_result.damage_applied
	bus.damage_resolved.connect(on_damage)
	context = ContextScript.new()
	context.attack_instance_id = Targeting.begin_attack()
	context.source = dummy
	context.target = player
	context.snapshot_damage = 4
	result = Targeting.resolve(context)
	bus.damage_resolved.disconnect(on_damage)
	_check(result.rejected_invulnerable and player.hp == hp_before_invuln and int(healed.n) == 0, "无敌时没有伤害也没有吸血")
	player._invuln_left = 0.0
	other.global_position = Vector2(60, 0)
	other.hp = 1
	var kills := {"n": 0}
	var on_kill = func(_hit_result, _ctx) -> void:
		kills.n += 1
	bus.target_killed.connect(on_kill)
	var attack_id := Targeting.begin_attack()
	context = ContextScript.new()
	context.attack_instance_id = attack_id
	context.source = player
	context.target = other
	context.snapshot_damage = 5
	Targeting.resolve(context)
	Targeting.resolve(context)
	bus.target_killed.disconnect(on_kill)
	_check(int(kills.n) == 1 and (not is_instance_valid(other) or other.hp <= 0), "同一次攻击的击杀事件只发一次")
	Targeting.close_attack(attack_id)
	dummy.hp = dummy.max_hp
	var wall := _thin_wall(training, Vector2(25, 0), Vector2(16, 80))
	await get_tree().physics_frame
	context = ContextScript.new()
	context.attack_instance_id = Targeting.begin_attack()
	context.source = player
	context.target = dummy
	context.snapshot_damage = 4
	result = Targeting.resolve(context)
	_check(result.blocked_by_wall and dummy.hp == dummy.max_hp, "墙后目标不进入伤害结算")
	wall.queue_free()
	await get_tree().physics_frame
	Targeting.close_attack(context.attack_instance_id)
	armor.global_position = player.global_position + Vector2(40, 0)
	armor.refill()
	var break_result = null
	for _i in 3:
		context = ContextScript.new()
		context.attack_instance_id = Targeting.begin_attack()
		context.source = player
		context.target = armor
		context.snapshot_damage = 2
		context.armor_break = 1
		break_result = Targeting.resolve(context)
		Targeting.close_attack(context.attack_instance_id)
	_check(break_result.damage_applied == 1 and break_result.armor_broken and armor.broken, "触发破甲的一击仍先减伤")
	context = ContextScript.new()
	context.attack_instance_id = Targeting.begin_attack()
	context.source = player
	context.target = armor
	context.snapshot_damage = 2
	result = Targeting.resolve(context)
	_check(result.damage_applied == 2 and not result.killed, "破甲后按原伤害结算")
	Targeting.close_attack(context.attack_instance_id)
	dummy.global_position = Vector2(40, 0)
	dummy.hp = dummy.max_hp
	var second = preload("res://scenes/combat/enemy.tscn").instantiate()
	second.move_speed = 0.0
	second.contact_damage = 0
	second.max_hp = 30
	training.add_child(second)
	second.hp = 30
	second.global_position = Vector2(40, 20)
	var profile := {
		"item_id": &"sword_hunter",
		"damage": 2,
		"range": 130.0,
		"arc_degrees": 360.0,
		"behavior_id": "area_strike",
	}
	weapon._strike(profile, dummy)
	_check(dummy.hp == dummy.max_hp - 2 and second.hp == 28, "一次范围攻击对每个目标只结算一次")
	var stats := Node.new()
	stats.set_script(preload("res://scripts/combat/run_stats.gd"))
	training.add_child(stats)
	dummy.hp = dummy.max_hp
	context = ContextScript.new()
	context.attack_instance_id = Targeting.begin_attack()
	context.source = player
	context.target = dummy
	context.snapshot_damage = 1
	Targeting.resolve(context)
	_check(stats.damage_dealt == 1, "实际伤害记入本次统计")
	Targeting.close_attack(context.attack_instance_id)
	var chains := {"n": 0}
	var chain = func(hit_result, hit_context) -> void:
		if hit_result.blocked_recursion or hit_result.rejected_invulnerable or hit_result.blocked_by_wall or hit_result.duplicate_hit:
			return
		if hit_result.damage_applied <= 0:
			return
		chains.n += 1
		var child = hit_context.fork()
		child.trigger_depth += 1
		child.attack_instance_id = Targeting.begin_attack()
		child.snapshot_damage = 1
		Targeting.resolve(child)
	bus = Targeting.event_bus()
	bus.damage_resolved.connect(chain)
	dummy.hp = 10
	context = ContextScript.new()
	context.attack_instance_id = Targeting.begin_attack()
	context.source = player
	context.target = dummy
	context.snapshot_damage = 1
	Targeting.resolve(context)
	bus.damage_resolved.disconnect(chain)
	_check(int(chains.n) == 2 and dummy.hp == 8, "测试触发器最多再进入一层")


func _test_build_loadout() -> void:
	const Derived := preload("res://scripts/build/build_derived_stats.gd")
	ProgressState.reset()
	ActionController.manual_attack_fixture = false
	var training := await _scene("res://scenes/exploration/action_training.tscn")
	var dev := get_node("/root/DeveloperPanel")
	_check(dev.grant_build_test_pack().contains("没有写入存档"), "开发菜单发放本进程构筑测试包")
	var panel := training.get_node("BuildPanel")
	panel.open()
	_check(panel.status_text() == "未成型", "没有核心时提示未成型")
	_check(panel.equip_instance("inst_haste_a") == "", "可以先装辅助")
	var early: Dictionary = Derived.from_weapon(ProgressState.equipped_weapon_id())
	_check(early.formed != true and int(early.damage) == 1 and is_equal_approx(float(early.interval), 0.5), "未成型时辅助不改变基础武器")
	_check(panel.equip_instance("inst_core") == "", "装上试验核心")
	var formed: Dictionary = Derived.from_weapon(ProgressState.equipped_weapon_id())
	_check(formed.formed == true and int(formed.damage) == 2 and is_equal_approx(float(formed.interval), 0.4), "预览的伤害和间隔跟着构筑变化")
	_check(panel.preview_text().contains("伤害 2") and panel.preview_text().contains("0.40"), "构筑页显示同一份预览")
	training.get_node("Hazard").set_physics_process(false)
	training.get_node("ArmoredTarget").global_position = Vector2(520, 280)
	training.get_node("DummyB").global_position = Vector2(480, 300)
	var dummy := training.get_node("Dummy")
	dummy.global_position = Vector2(50, 0)
	dummy.hp = dummy.max_hp
	ProgressState.attack_cooldown_left = 0.0
	await _physics_frames(8)
	_check(dummy.hp == dummy.max_hp - 2, "自动攻击使用派生后的伤害")
	panel.clear_slot("core")
	var stripped: Dictionary = Derived.from_weapon(ProgressState.equipped_weapon_id())
	_check(stripped.formed != true and int(stripped.damage) == 1 and is_equal_approx(float(stripped.interval), 0.5), "卸下核心后参数恢复")
	_check(panel.equip_instance("inst_core") == "", "再次装上核心")
	var again: Dictionary = Derived.from_weapon(ProgressState.equipped_weapon_id())
	_check(int(again.damage) == 2 and is_equal_approx(float(again.interval), 0.4), "再次装上不会把加成叠高")
	_check(panel.equip_instance("inst_haste_b") == "不能装两个相同的辅助", "相同辅助不能装两个")
	_check(panel.equip_instance("inst_projectile") == "", "不适配的辅助可以留在槽上")
	var mismatched: Dictionary = Derived.from_weapon(ProgressState.equipped_weapon_id())
	_check(String(mismatched.detail).contains("不适配") and is_equal_approx(float(mismatched.range), 78.0), "不适配的辅助不改数值")
	var loadout = ProgressState.build_loadout
	_check(loadout.set_active_preset("preset_b") == "", "切换到第二套预设")
	_check(loadout.set_slot("core", "inst_core") == "" and loadout.set_slot("support_0", "inst_haste_a") == "", "第二套预设引用同一个辅助实例")
	var shared: Dictionary = Derived.from_weapon(ProgressState.equipped_weapon_id())
	_check(int(shared.damage) == 2 and is_equal_approx(float(shared.interval), 0.4), "跨预设的同一个实例只计算一次")


func _test_build_mechanics() -> void:
	const Derived := preload("res://scripts/build/build_derived_stats.gd")
	ProgressState.reset()
	ActionController.manual_attack_fixture = false
	var training := await _scene("res://scenes/exploration/action_training.tscn")
	var dev := get_node("/root/DeveloperPanel")
	dev.grant_build_test_pack()
	var loadout = ProgressState.build_loadout
	_check(loadout.set_slot("core", "inst_echo") == "", "装上回响核心")
	var mechanics := ProgressState.get_node("BuildMechanics")
	var readout := training.get_node("BuildCombatReadout")
	await get_tree().process_frame
	_check(readout.get_node("Panel/CoreLabel").text == "◎ 回响", "战斗界面显示回响核心")
	_check(readout.get_node("Panel/DetailLabel").text.contains("每 3 次") and readout.get_node("Panel/DetailLabel").text.contains("范围 40"), "详情写明触发条件和范围")
	training.get_node("Hazard").set_physics_process(false)
	training.get_node("Player/EquippedAutoWeapon").set_physics_process(true)
	var armor := training.get_node("ArmoredTarget")
	var other := training.get_node("DummyB")
	armor.global_position = Vector2(520, 280)
	other.global_position = Vector2(480, 300)
	var dummy := training.get_node("Dummy")
	var player := training.get_node("Player")
	player.global_position = Vector2.ZERO
	dummy.global_position = Vector2(50, 0)
	dummy.hp = dummy.max_hp
	var start_hp: int = dummy.hp
	mechanics.reset_counts()
	ProgressState.attack_cooldown_left = 0.0
	for _i in 160:
		if mechanics.basic_hits >= 3:
			training.get_node("Player/EquippedAutoWeapon").set_physics_process(false)
			break
		await get_tree().physics_frame
	await _physics_frames(20)
	_check(mechanics.echo_triggers == 1 and dummy.hp == start_hp - mechanics.basic_damage - mechanics.mechanic_damage, "回响由自动攻击触发，伤害与生命损失一致")
	_check(readout.get_node("Panel/StatsLabel").text.contains("触发 1") and readout.get_node("Panel/StatsLabel").text.contains("来源伤害 %d" % mechanics.basic_damage), "战斗界面分开显示来源伤害和机制伤害")
	await _physics_frames(30)
	_check(mechanics.echo_triggers == 1, "回响不会再触发自己")
	loadout.set_slot("core", "")
	var triggers_after_remove: int = mechanics.echo_triggers
	training.get_node("Player/EquippedAutoWeapon").set_physics_process(true)
	ProgressState.attack_cooldown_left = 0.0
	var hits_before: int = mechanics.basic_hits
	for _i in 80:
		if mechanics.basic_hits >= hits_before + 2:
			break
		await get_tree().physics_frame
	training.get_node("Player/EquippedAutoWeapon").set_physics_process(false)
	_check(mechanics.echo_triggers == triggers_after_remove and readout.get_node("Panel/CoreLabel").text == "无核心", "卸下回响后不再触发")
	dummy.global_position = Vector2(480, -280)
	armor.global_position = player.global_position + Vector2(48, 0)
	armor.refill()
	_check(loadout.set_slot("core", "inst_break") == "", "装上破阵核心")
	await get_tree().process_frame
	_check(readout.get_node("Panel/CoreLabel").text == "▣ 破阵", "战斗界面显示破阵核心")
	var armor_before: int = armor.hp
	var mechanic_before: int = mechanics.mechanic_damage
	ProgressState.attack_cooldown_left = 0.0
	training.get_node("Player/EquippedAutoWeapon").set_physics_process(true)
	for _i in 200:
		if mechanics.break_triggers >= 1:
			training.get_node("Player/EquippedAutoWeapon").set_physics_process(false)
			break
		await get_tree().physics_frame
	var shock_damage: int = mechanics.mechanic_damage - mechanic_before
	_check(mechanics.break_triggers == 1 and armor.hp == armor_before - shock_damage, "破甲开始只冲击一次，冲击伤害与生命损失一致")
	var breaks_before: int = mechanics.break_triggers
	dummy.global_position = player.global_position + Vector2(46, 0)
	armor.global_position = Vector2(520, 280)
	ProgressState.attack_cooldown_left = 0.0
	training.get_node("Player/EquippedAutoWeapon").set_physics_process(true)
	await _physics_frames(40)
	training.get_node("Player/EquippedAutoWeapon").set_physics_process(false)
	_check(mechanics.break_triggers == breaks_before, "没有护甲的目标不会假触发破阵")
	loadout.set_slot("core", "")
	await get_tree().process_frame
	_check(readout.get_node("Panel/CoreLabel").text == "无核心", "卸下破阵后核心显示消失")
	_check(loadout.set_slot("core", "inst_echo") == "" and loadout.set_slot("support_0", "inst_echo_range") == "", "回响可以装扩圈辅助")
	var widened: Dictionary = Derived.from_weapon(ProgressState.equipped_weapon_id())
	_check(is_equal_approx(float(widened.echo_range), 60.0), "回响扩圈把回响范围加到 60")
	_check(loadout.set_slot("core", "inst_break") == "" and loadout.set_slot("support_0", "inst_break_power") == "", "破阵可以装破击辅助")
	var harder: Dictionary = Derived.from_weapon(ProgressState.equipped_weapon_id())
	_check(int(harder.armor_break) == 2, "破击把基础破甲加到 2")
	_check(loadout.set_slot("support_0", "inst_echo_range") == "", "机制不匹配的辅助可以留在槽上")
	var rejected: Dictionary = Derived.from_weapon(ProgressState.equipped_weapon_id())
	_check(String(rejected.detail).contains("不适配") and int(rejected.armor_break) == 1, "不适配的机制辅助不改破甲")
	mechanics.echo_progress = 2
	ProgressState.attack_cooldown_left = 4.5
	var active_before := String(loadout.active_build_id)
	training.get_node("BuildPanel/Root/Center/Panel/Margin/VBox/PresetRow/PresetB").pressed.emit()
	_check(String(loadout.active_build_id) == active_before and training.get_node("BuildPanel").status_text() == "战斗中不能切换预设", "战斗中不能切换预设")
	_check(mechanics.echo_progress == 2 and is_equal_approx(ProgressState.attack_cooldown_left, 4.5), "没切成时触发进度和攻击冷却都保持")
	_check(loadout.set_active_preset("preset_b") == "", "代码仍可切换预设")
	_check(mechanics.echo_progress == 0 and is_equal_approx(ProgressState.attack_cooldown_left, 4.5), "切换重置触发进度，不刷新攻击冷却")


func _test_build_sources() -> void:
	const Derived := preload("res://scripts/build/build_derived_stats.gd")
	ProgressState.reset()
	ActionController.manual_attack_fixture = false
	var village := await _scene("res://scenes/village/village.tscn")
	village.get_node("UI/StarterButton").pressed.emit()
	var echo_inst: Dictionary = ProgressState.build_loadout.instance("claim.village.starter_kit")
	_check(ProgressState.is_claimed(ProgressState.STARTER_CLAIM) and ProgressState.item_count(&"sword_training") >= 1 \
		and String(echo_inst.get("definition_id", "")) == "core_echo", "村落领取试验短剑和回响核心")
	var owned_before := int(ProgressState.build_loadout.instances.size())
	village.get_node("UI/StarterButton").pressed.emit()
	_check(ProgressState.claim_starter_kit() == "已经领取" and ProgressState.build_loadout.instances.size() == owned_before \
		and village.get_node("UI/InventoryLabel").text == "已经领取", "重复领取不会复制核心")
	var outskirts := await _scene("res://scenes/exploration/outskirts.tscn")
	var chest: Node = outskirts.get_node("SupportChest")
	_check(chest.try_pickup(), "外围宝箱领取护持")
	_check(ProgressState.grant_claimed_instance(&"outskirts.chest_shield", "support_shield_time") == "已经领取", "重复打开宝箱不会复制辅助")
	var enemy: Node = outskirts.get_node("BranchEnemy")
	enemy.set_physics_process(false)
	enemy.take_damage(999)
	enemy.take_damage(999)
	var hunts := 0
	for instance_id in ProgressState.build_loadout.instances:
		var inst: Dictionary = ProgressState.build_loadout.instance(String(instance_id))
		if String(inst.get("definition_id", "")) == "core_hunt":
			hunts += 1
	_check(ProgressState.is_claimed(&"outskirts.branch_hunt") and hunts == 1, "击败外围敌人获得一份猎获，再击败不会复制")
	var panel: Node = outskirts.get_node("BuildPanel")
	panel.open()
	_check(panel.equip_instance("claim.village.starter_kit") == "", "构筑页装上回响")
	_check(panel.preview_text().contains("回响"), "回响组合能在预览里看出来")
	panel.clear_slot("core")
	_check(panel.equip_instance("claim.outskirts.branch_hunt") == "" and panel.equip_instance("claim.outskirts.chest_shield") == "", "构筑页装上猎获和护持")
	var paired: Dictionary = Derived.from_weapon(ProgressState.equipped_weapon_id())
	_check(String(paired.get("mechanic", "")) == "hunt" and is_equal_approx(float(paired.get("shield_duration", 0.0)), 6.0), "护持把护盾时间加到 6 秒")
	var training := await _scene("res://scenes/exploration/action_training.tscn")
	training.get_node("Hazard").set_physics_process(false)
	training.get_node("ArmoredTarget").global_position = Vector2(520, 280)
	training.get_node("DummyB").global_position = Vector2(480, 300)
	var player: Node = training.get_node("Player")
	var dummy: Node = training.get_node("Dummy")
	player.global_position = Vector2.ZERO
	dummy.global_position = Vector2(50, 0)
	dummy.hp = 1
	training.get_node("Player/EquippedAutoWeapon").set_physics_process(true)
	ProgressState.attack_cooldown_left = 0.0
	for _i in 80:
		if player.shield_hp >= 2:
			training.get_node("Player/EquippedAutoWeapon").set_physics_process(false)
			break
		await get_tree().physics_frame
	training.get_node("Player/EquippedAutoWeapon").set_physics_process(false)
	await get_tree().process_frame
	_check(player.shield_hp == 2 and training.get_node("BuildCombatReadout").get_node("Panel/DetailLabel").text.contains("猎获：获得护盾"), "击杀后界面说明获得了护盾")
	var hp_before: int = player.hp
	player.take_damage(1)
	_check(player.hp == hp_before and player.shield_hp == 1 and player._invuln_left == 0.0, "护盾抵消伤害，不改无敌时间")
	var other: Node = training.get_node("DummyB")
	other.global_position = Vector2(46, 0)
	other.hp = 1
	ProgressState.attack_cooldown_left = 0.0
	training.get_node("Player/EquippedAutoWeapon").set_physics_process(true)
	await _physics_frames(40)
	training.get_node("Player/EquippedAutoWeapon").set_physics_process(false)
	_check(player.shield_hp == 1, "护盾冷却内再次击杀不会叠高")


func _test_loot_tables() -> void:
	const Loot := preload("res://scripts/loot/loot_table.gd")
	var seeded: Dictionary = Loot.roll("loot_wolf", 11)
	var repeated: Dictionary = Loot.roll("loot_wolf", 11)
	_check(seeded.ok == true and seeded.drops == repeated.drops, "同一随机种子掉落相同")
	var differed := false
	for seed_value in range(1, 40):
		var other: Dictionary = Loot.roll("loot_wolf", seed_value)
		if other.drops != seeded.drops:
			differed = true
			break
	_check(differed, "不同种子可以落到不同结果")
	var bad: Dictionary = Loot.roll_table({
		"id": "bad",
		"entries": [{
			"kind": "weighted_choice",
			"rolls": 1,
			"choices": [
				{"weight": 0, "item_id": "no_such_item", "min_count": 2, "max_count": 1},
				{"weight": 1, "chance": 0.2, "empty": true},
			],
		}],
	}, 1)
	var bad_text := "\n".join(bad.errors)
	_check(bad.ok != true and bad.drops.is_empty() and bad_text.contains("权重") and bad_text.contains("未知物品") and bad_text.contains("概率"), "非法权重和引用会被诊断且不会发放")
	var mixed := Loot.diagnose({
		"id": "mixed",
		"entries": [{
			"kind": "independent_chance",
			"chance": 0.5,
			"weight": 3,
			"item_id": "sword_hunter",
			"min_count": 1,
			"max_count": 1,
		}],
	})
	_check("\n".join(mixed).contains("不能写权重"), "独立概率不接受权重")
	_check(Loot.sources_text_for_item("item_test_hide").contains("林地野兽"), "掉落表能查出物品来源")
	ProgressState.reset()
	var training := await _scene("res://scenes/exploration/action_training.tscn")
	training.get_node("Hazard").set_physics_process(false)
	training.get_node("Player/EquippedAutoWeapon").set_physics_process(false)
	var enemy_scene := preload("res://scenes/combat/enemy.tscn")
	var first_enemy := _spawn_loot_enemy(training, enemy_scene, "loot_beast", Vector2(420, 220))
	first_enemy.take_damage(5)
	first_enemy.take_damage(5)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_hide_drops(training).size() == 1, "同次死亡只掉一次")
	_spawn_loot_enemy(training, enemy_scene, "loot_beast", Vector2(460, 220)).take_damage(5)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_hide_drops(training).size() == 2, "重新生成的野兽可以再掉")
	_spawn_loot_enemy(training, enemy_scene, "loot_branch_beast", Vector2(500, 220)).take_damage(5)
	_spawn_loot_enemy(training, enemy_scene, "loot_branch_beast", Vector2(540, 220)).take_damage(5)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("claim.outskirts.branch_hunt" in ProgressState.build_loadout.instances and _hide_drops(training).size() == 4, "唯一奖励不重发，普通材料仍会再掉")
	var wolf := preload("res://scenes/enemies/wolf.tscn").instantiate()
	wolf.loot_seed = 8
	wolf.max_hp = 1
	training.add_child(wolf)
	wolf.position = Vector2(580, 220)
	wolf.take_damage(9)
	await get_tree().process_frame
	await get_tree().process_frame
	var found_sword := false
	for node in training.get_children():
		if node.get("item") != null and node.item.item_id == &"sword_hunter":
			found_sword = true
	_check(found_sword, "野狼掉落表会掉武器")


func _test_random_affixes() -> void:
	const AffixPool := preload("res://scripts/build/affix_pool.gd")
	const Derived := preload("res://scripts/build/build_derived_stats.gd")
	_check(AffixPool.check_pool(["affix_edge"]) == "词条池不足两种", "词条池不足两种时拒绝")
	_check(AffixPool.check_range(NAN, 1) == "词条数值无效", "非数字词条区间被拒绝")
	_check(AffixPool.check_range(3, 1) == "词条区间无效", "颠倒的词条区间被拒绝")
	ProgressState.reset()
	var loadout = ProgressState.build_loadout
	_check(loadout.add_instance("inst_core", "core_test_damage") == "", "比较测试先有一个核心")
	_check(loadout.create_random_instance("rand_a", "support_haste", 4) == "", "生成第一件急促")
	_check(loadout.create_random_instance("rand_b", "support_haste", 9) == "", "生成第二件同名急促")
	var first: Array = loadout.instance("rand_a").get("affixes", [])
	var second: Array = loadout.instance("rand_b").get("affixes", [])
	_check(first.size() == 2 and second.size() == 2 and String(first[0].get("id", "")) != String(first[1].get("id", "")) and first != second, "两件同名组件各有两条不同词条")
	var training := await _scene("res://scenes/exploration/action_training.tscn")
	var panel: Node = training.get_node("BuildPanel")
	panel.open()
	var shown: Array = loadout.instance("rand_a").get("affixes", [])
	_check(shown == first and panel.compare_text().contains("星级 1") and panel.compare_text().contains("rand_a") and panel.compare_text().contains("rand_b"), "打开界面不重抽，并能比较两件")
	var row: Node = null
	for child in panel.get_node("Root/Center/Panel/Margin/VBox/Instances").get_children():
		if child.slot == "rand_a":
			row = child
	row.get_node("LockButton").pressed.emit()
	_check(loadout.instance("rand_a").get("locked", false) == true and loadout.dismantle("rand_a") == "已锁定，不能拆解", "锁定后不能拆解")
	_check(panel.equip_instance("inst_core") == "" and panel.equip_instance("rand_a") == "", "锁定不影响装配")
	var profile: Dictionary = Derived.from_weapon(ProgressState.equipped_weapon_id())
	var mods: Dictionary = AffixPool.mods_for(loadout.instance("rand_a"))
	_check(int(profile.damage) == 2 + int(mods.get("flat_damage", 0)), "副词条进入实际伤害")
	_check(loadout.set_locked("rand_b", false) == "" and loadout.dismantle("rand_b") == "" and not ("rand_b" in loadout.instances), "未锁定的另一件可以拆解")
	_check(loadout.instance("rand_a").get("affixes", []) == first, "拆解另一件不会改已保留实例")


func _test_hammer() -> void:
	const Derived := preload("res://scripts/build/build_derived_stats.gd")
	const Link := preload("res://scripts/items/weapon_effect_link.gd")
	ProgressState.reset()
	ActionController.manual_attack_fixture = false
	_check(ProgressState.add_item(&"hammer_training", 1) and ProgressState.equip_weapon(&"hammer_training") == "", "可以装备试验重锤")
	var profile: Dictionary = Link.combat_profile(&"hammer_training")
	_check(String(profile.behavior_id) == "area_strike" and is_equal_approx(float(profile.interval), 1.6) \
		and is_equal_approx(float(profile.range), 150.0) and int(profile.armor_break) == 2 \
		and String(profile.summary).contains("破甲 2"), "重锤面板写出间隔、范围和破甲")
	_check(String(ProgressState.get_definition(&"hammer_training").description).contains("破甲 2"), "物品说明和面板用同一破甲")
	var loadout = ProgressState.build_loadout
	_check(loadout.add_instance("inst_core", "core_test_damage") == "" and loadout.add_instance("inst_haste_a", "support_haste") == "", "重锤可以装上已有构筑")
	_check(loadout.set_slot("core", "inst_core") == "" and loadout.set_slot("support_0", "inst_haste_a") == "", "重锤构筑装配成功")
	var formed: Dictionary = Derived.from_weapon(&"hammer_training")
	_check(int(formed.damage) == 3 and is_equal_approx(float(formed.interval), 1.28) and int(formed.armor_break) == 2, "构筑加成叠在重锤自己的数值上")
	loadout.set_slot("core", "")
	loadout.set_slot("support_0", "")
	var training := await _scene("res://scenes/exploration/action_training.tscn")
	training.get_node("Hazard").set_physics_process(false)
	var player: Node = training.get_node("Player")
	var actions: Node = training.get_node("Player/ActionController")
	var armor: Node = training.get_node("ArmoredTarget")
	var dummy: Node = training.get_node("Dummy")
	var other: Node = training.get_node("DummyB")
	player.global_position = Vector2.ZERO
	dummy.global_position = Vector2(40, 0)
	other.global_position = Vector2(0, 70)
	armor.global_position = Vector2(520, 280)
	dummy.hp = dummy.max_hp
	other.hp = other.max_hp
	var weapon: Node = training.get_node("Player/EquippedAutoWeapon")
	weapon.set_physics_process(true)
	ProgressState.attack_cooldown_left = 0.0
	for _i in 40:
		if dummy.hp < dummy.max_hp:
			weapon.set_physics_process(false)
			break
		await get_tree().physics_frame
	_check(dummy.hp == dummy.max_hp - 2 and other.hp == other.max_hp - 2, "一次重锤让范围内每个目标各掉一次血")
	var attacks_before: int = actions.attack_count
	await _press_action("attack")
	player.set_physics_process(true)
	Input.action_press("move_left")
	await _physics_frames(4)
	var moving: bool = absf(player.velocity.length() - player.move_speed) < 1.0
	Input.action_release("move_left")
	_check(actions.state == ActionController.State.IDLE and actions.attack_count == attacks_before and moving, "重锤不等待蓄力，也不锁住移动")
	weapon.set_physics_process(true)
	armor.global_position = player.global_position + Vector2(60, 0)
	dummy.global_position = Vector2(520, 200)
	other.global_position = Vector2(520, 240)
	armor.refill()
	ProgressState.attack_cooldown_left = 0.0
	for _i in 200:
		if armor.broken:
			weapon.set_physics_process(false)
			break
		await get_tree().physics_frame
	_check(armor.broken, "重锤自带破甲，能打断装甲")
	_check(ProgressState.add_item(&"sword_training", 1) and ProgressState.equip_weapon(&"sword_training") == "", "换回试验短剑")
	_check(loadout.add_instance("inst_break", "core_break") == "" and loadout.set_slot("core", "inst_break") == "", "剑装上破阵")
	armor.refill()
	weapon.set_physics_process(true)
	ProgressState.attack_cooldown_left = 0.0
	await _physics_frames(20)
	weapon.set_physics_process(false)
	_check(armor.armor_value > 0 and not armor.broken, "剑仍然能积累破甲，而且比重大锤慢")


func _test_bow() -> void:
	const Derived := preload("res://scripts/build/build_derived_stats.gd")
	const Link := preload("res://scripts/items/weapon_effect_link.gd")
	ProgressState.reset()
	ActionController.manual_attack_fixture = false
	_check(ProgressState.add_item(&"bow_training", 1) and ProgressState.equip_weapon(&"bow_training") == "", "可以装备试验弓")
	var plain: Dictionary = Link.combat_profile(&"bow_training")
	_check(String(plain.behavior_id) == "projectile" and String(plain.summary).contains("弹速 280"), "弓的说明写出弹速")
	var loadout = ProgressState.build_loadout
	_check(loadout.add_instance("inst_core", "core_test_damage") == "" and loadout.add_instance("inst_projectile", "support_projectile") == "", "弓可以装疾矢")
	_check(loadout.set_slot("core", "inst_core") == "" and loadout.set_slot("support_0", "inst_projectile") == "", "疾矢装到弓上")
	var sped: Dictionary = Derived.from_weapon(&"bow_training")
	_check(is_equal_approx(float(sped.projectile_speed), 336.0), "疾矢把箭速提高两成")
	loadout.set_slot("core", "")
	loadout.set_slot("support_0", "")
	var training := await _scene("res://scenes/exploration/action_training.tscn")
	training.get_node("Hazard").set_physics_process(false)
	var player: Node = training.get_node("Player")
	var weapon: Node = training.get_node("Player/EquippedAutoWeapon")
	var dummy: Node = training.get_node("Dummy")
	var other: Node = training.get_node("DummyB")
	var armor: Node = training.get_node("ArmoredTarget")
	player.global_position = Vector2.ZERO
	player.set_physics_process(false)
	armor.global_position = Vector2(700, 400)
	other.global_position = Vector2(700, -400)
	dummy.global_position = Vector2(180, 0)
	dummy.hp = dummy.max_hp
	weapon.set_physics_process(false)
	for node in get_tree().get_nodes_in_group("combat_projectiles"):
		node.queue_free()
	await get_tree().physics_frame
	dummy.hp = dummy.max_hp
	weapon.set_physics_process(true)
	ProgressState.attack_cooldown_left = 0.0
	await get_tree().physics_frame
	weapon.set_physics_process(false)
	var arrows := get_tree().get_nodes_in_group("combat_projectiles")
	_check(arrows.size() == 1 and dummy.hp == dummy.max_hp, "箭刚离弦时还没有伤害")
	dummy.global_position = Vector2(180, 320)
	await _physics_frames(40)
	_check(dummy.hp == dummy.max_hp, "直线箭不会追着躲开的目标")
	for node in get_tree().get_nodes_in_group("combat_projectiles"):
		node.queue_free()
	await get_tree().physics_frame
	dummy.global_position = Vector2(90, 0)
	other.global_position = Vector2(190, 0)
	dummy.hp = dummy.max_hp
	other.hp = other.max_hp
	weapon.set_physics_process(true)
	ProgressState.attack_cooldown_left = 0.0
	await get_tree().physics_frame
	weapon.set_physics_process(false)
	await _physics_frames(40)
	_check(dummy.hp == dummy.max_hp - 1 and other.hp == other.max_hp, "箭打中前面的目标后停下")
	var wall := _thin_wall(training, Vector2(50, 0), Vector2(12, 80))
	await get_tree().physics_frame
	dummy.hp = dummy.max_hp
	weapon.set_physics_process(true)
	ProgressState.attack_cooldown_left = 0.0
	await get_tree().physics_frame
	weapon.set_physics_process(false)
	await _physics_frames(30)
	_check(dummy.hp == dummy.max_hp and get_tree().get_nodes_in_group("combat_projectiles").is_empty(), "箭先碰到墙就停，墙后目标不受伤")
	wall.queue_free()
	await get_tree().physics_frame
	var fast := _fire_stone(training, Vector2(40, 0), 4000.0)
	fast.global_position = Vector2(40, 0)
	dummy.global_position = Vector2(70, 0)
	dummy.hp = dummy.max_hp
	await get_tree().physics_frame
	_check(dummy.hp == dummy.max_hp - 1, "高速箭不会穿过近处的薄目标")
	var lingering := _fire_stone(training, Vector2(-200, -200), 10.0)
	_check(get_tree().get_nodes_in_group("combat_projectiles").has(lingering), "暂停前箭还在场上")
	get_tree().paused = true
	await get_tree().process_frame
	var held: Vector2 = lingering.global_position
	await get_tree().physics_frame
	_check(lingering.global_position == held, "暂停时箭停在原地")
	get_tree().paused = false
	await _scene("res://scenes/village/village.tscn")
	_check(get_tree().get_nodes_in_group("combat_projectiles").is_empty(), "离开场景后不残留箭")


func _test_gun() -> void:
	const Link := preload("res://scripts/items/weapon_effect_link.gd")
	ProgressState.reset()
	ActionController.manual_attack_fixture = false
	_check(ProgressState.add_item(&"gun_training", 1) and ProgressState.equip_weapon(&"gun_training") == "", "可以装备试验火铳")
	var gun: Dictionary = Link.combat_profile(&"gun_training")
	var bow: Dictionary = Link.combat_profile(&"bow_training")
	_check(gun.get("reload", false) == true and float(gun.interval) > float(bow.interval) and int(gun.armor_break) > int(bow.armor_break) \
		and float(gun.projectile_speed) > float(bow.projectile_speed) and String(gun.summary).contains("装填"), "火铳比弓更慢、破甲更高、弹速更快")
	ProgressState.attack_cooldown_left = 2.0
	_check(ProgressState.add_item(&"bow_training", 1) and ProgressState.equip_weapon(&"bow_training") == "", "装填中可以换成弓")
	_check(is_equal_approx(ProgressState.attack_cooldown_left, 2.0), "换武器不会把装填清掉")
	ProgressState.equip_weapon(&"gun_training")
	var training := await _scene("res://scenes/exploration/action_training.tscn")
	training.get_node("Hazard").set_physics_process(false)
	var player: Node = training.get_node("Player")
	var weapon: Node = training.get_node("Player/EquippedAutoWeapon")
	player.global_position = Vector2.ZERO
	player.set_physics_process(false)
	player.hp = 0
	ProgressState.attack_cooldown_left = 2.0
	weapon.set_physics_process(true)
	await _physics_frames(4)
	_check(is_equal_approx(ProgressState.attack_cooldown_left, 2.0), "倒下后装填不会自己走完")
	player.hp = player.max_hp
	get_tree().paused = true
	await _physics_frames(4)
	_check(is_equal_approx(ProgressState.attack_cooldown_left, 2.0), "暂停时装填不减少")
	get_tree().paused = false
	var dummy: Node = training.get_node("Dummy")
	var other: Node = training.get_node("DummyB")
	var armor: Node = training.get_node("ArmoredTarget")
	other.global_position = Vector2(700, 400)
	armor.global_position = Vector2(700, -400)
	dummy.global_position = Vector2(48, 0)
	dummy.hp = dummy.max_hp
	var wall := _thin_wall(training, Vector2(24, 0), Vector2(8, 64))
	await get_tree().physics_frame
	weapon.set_physics_process(true)
	ProgressState.attack_cooldown_left = 0.0
	await get_tree().physics_frame
	weapon.set_physics_process(false)
	await _physics_frames(8)
	_check(dummy.hp == dummy.max_hp and get_tree().get_nodes_in_group("combat_projectiles").is_empty(), "高速火铳先打中薄墙，近处目标不受伤")
	wall.queue_free()
	await get_tree().physics_frame
	dummy.hp = dummy.max_hp
	weapon.set_physics_process(true)
	ProgressState.attack_cooldown_left = 0.0
	await get_tree().physics_frame
	weapon.set_physics_process(false)
	await _physics_frames(6)
	_check(dummy.hp == dummy.max_hp - 3, "薄墙移开后，高速火铳打中近处目标")
	var readout: Node = training.get_node("BuildCombatReadout")
	_check(readout.get_node("Panel/ReloadLabel").text.begins_with("装填") and readout.get_node("Panel/ReloadBar").visible, "战斗界面显示装填条")
	_check(ProgressState.add_item(&"bow_pierce", 1) and ProgressState.equip_weapon(&"bow_pierce") == "", "可以装备穿杨弓")
	var pierce: Dictionary = Link.combat_profile(&"bow_pierce")
	_check(int(pierce.pierce_count) == 2 and is_equal_approx(float(pierce.damage_falloff), 0.5), "穿杨弓最多穿透两个目标并写明衰减")
	var loadout = ProgressState.build_loadout
	_check(loadout.add_instance("inst_echo", "core_echo") == "" and loadout.set_slot("core", "inst_echo") == "", "穿杨弓装上回响")
	var mechanics := ProgressState.get_node("BuildMechanics")
	mechanics.reset_counts()
	other.global_position = Vector2(160, 0)
	dummy.global_position = Vector2(80, 0)
	dummy.hp = dummy.max_hp
	other.hp = other.max_hp
	weapon.set_physics_process(true)
	ProgressState.attack_cooldown_left = 0.0
	await get_tree().physics_frame
	weapon.set_physics_process(false)
	await _physics_frames(40)
	_check(dummy.hp == dummy.max_hp - 2 and other.hp == other.max_hp - 1 and mechanics.echo_progress == 1, "第二下伤害减半，而且不会再触发一次回响")


func _test_deep_armor() -> void:
	var outskirts := await _scene("res://scenes/exploration/outskirts.tscn")
	var placed = outskirts.get_node("ArmoredWolf")
	_check(placed.loot_table_id == "loot_armored_wolf" and placed.global_position.x < -524.0 and placed.global_position.y < -374.0, "深处试炼放着会掉纤维的装甲狼")
	var training := await _scene("res://scenes/exploration/action_training.tscn")
	training.get_node("Hazard").set_physics_process(false)
	training.get_node("Player/EquippedAutoWeapon").set_physics_process(false)
	var wolf := preload("res://scenes/enemies/armored_wolf.tscn").instantiate()
	training.add_child(wolf)
	wolf.position = Vector2(0, 200)
	wolf.debug_velocity = Vector2(180, 0)
	var wall := _thin_wall(training, Vector2(50, 200), Vector2(24, 80))
	await _physics_frames(12)
	_check(wolf.global_position.x < 40.0, "装甲狼被岩石挡住，不会穿墙")
	wolf.debug_velocity = null
	wolf.global_position = wolf.home_position()
	var player = training.get_node("Player")
	player.global_position = wolf.global_position + Vector2(20, 0)
	player.set_physics_process(false)
	var bitten := false
	for _i in 50:
		if wolf.state == wolf.State.WINDUP and player.hp == player.max_hp:
			bitten = true
			break
		await get_tree().physics_frame
	_check(bitten, "装甲狼先预警，预警时还没咬到")
	player.global_position = wolf.home_position() + Vector2(wolf.activity_radius + 80.0, 0)
	await _physics_frames(20)
	_check(wolf.global_position.distance_to(wolf.home_position()) <= wolf.activity_radius + 16.0, "玩家离开活动范围后装甲狼不无限追")
	var beast := preload("res://scenes/combat/enemy.tscn").instantiate()
	beast.max_hp = 6
	training.add_child(beast)
	beast.hp = 6
	beast.take_damage(1)
	var armor_before: int = wolf.hp
	wolf.receive_hit(1, 0)
	_check(beast.hp == 5 and wolf.hp == armor_before, "同一把短剑能伤到野兽，却被装甲挡住")
	wolf.receive_hit(3, 3)
	_check(wolf.broken and wolf.hp == armor_before - 2, "火铳这样的高破甲一击能打穿装甲")
	var before := _fiber_drops(training).size()
	var hp_before: int = player.hp
	wolf.hp = 1
	wolf.take_damage(5)
	wolf.take_damage(5)
	await get_tree().process_frame
	await get_tree().process_frame
	await _physics_frames(8)
	_check(_fiber_drops(training).size() == before + 1 and player.hp == hp_before, "装甲狼死后只掉一次，也不会再攻击")
	wall.queue_free()


func _test_sentry() -> void:
	var outskirts := await _scene("res://scenes/exploration/outskirts.tscn")
	var placed = outskirts.get_node("Sentry")
	var spawn: Vector2 = outskirts.get_node("Player").global_position
	_check(placed.loot_table_id == "loot_sentry" and placed.global_position.distance_to(spawn) > placed.notice_radius, "南侧哨位离出生点还有一段安全距离")
	var probe := Node2D.new()
	outskirts.add_child(probe)
	probe.global_position = Vector2(420, 640)
	_check(not Targeting.has_line_of_sight(placed, probe), "哨位岩石挡住东侧，可以躲开射击")
	probe.queue_free()
	var training := await _scene("res://scenes/exploration/action_training.tscn")
	training.get_node("Hazard").set_physics_process(false)
	training.get_node("Player/EquippedAutoWeapon").set_physics_process(false)
	ProgressState.reset()
	var sentry = preload("res://scenes/enemies/sentry.tscn").instantiate()
	sentry.position = Vector2(0, 220)
	sentry.windup_seconds = 0.25
	sentry.recovery_seconds = 2.0
	sentry.shot_speed = 420.0
	sentry.preferred_range = 150.0
	training.add_child(sentry)
	var player = training.get_node("Player")
	player.set_physics_process(false)
	player.global_position = Vector2.ZERO
	sentry.debug_velocity = Vector2(180, 0)
	var block := _thin_wall(training, Vector2(50, 220), Vector2(24, 80))
	await _physics_frames(12)
	_check(sentry.global_position.x < 40.0, "哨械被岩石挡住，不会穿墙")
	block.queue_free()
	sentry.debug_velocity = null
	sentry.global_position = sentry.home_position()
	player.global_position = sentry.global_position + Vector2(40, 0)
	await _physics_frames(15)
	_check(sentry.global_position.x < sentry.home_position().x - 4.0 and player.hp == player.max_hp, "玩家贴太近时哨械后退，而且还不开火")
	sentry.global_position = sentry.home_position()
	player.global_position = sentry.home_position() + Vector2(150, 0)
	player._invuln_left = 0.0
	var warned := false
	for _i in 40:
		if sentry.state == sentry.State.WINDUP and player.hp == player.max_hp and get_tree().get_nodes_in_group("combat_projectiles").is_empty():
			warned = true
			break
		await get_tree().physics_frame
	_check(warned, "哨械先亮出射击方向，预警时还没有弹")
	player.global_position = sentry.home_position() + Vector2(150, 90)
	var ally = preload("res://scenes/combat/enemy.tscn").instantiate()
	ally.max_hp = 5
	training.add_child(ally)
	ally.hp = 5
	ally.global_position = sentry.home_position() + Vector2(80, 0)
	await _physics_frames(55)
	_check(player.hp == player.max_hp and ally.hp == 5 and sentry.hp == sentry.max_hp, "躲开锁定方向后不受伤，弹也不打自己和旁边的敌人")
	for node in get_tree().get_nodes_in_group("combat_projectiles"):
		node.queue_free()
	await get_tree().physics_frame
	sentry.recovery_seconds = 0.15
	sentry._state_left = 0.0
	player.global_position = sentry.home_position() + Vector2(150, 0)
	player._invuln_left = 0.0
	var loadout = ProgressState.build_loadout
	_check(loadout.add_instance("inst_echo", "core_echo") == "" and loadout.set_slot("core", "inst_echo") == "", "哨械测试装上回响")
	var mechanics = ProgressState.get_node("BuildMechanics")
	mechanics.reset_counts()
	var hit := false
	for _i in 80:
		if player.hp < player.max_hp:
			hit = true
			break
		await get_tree().physics_frame
	_check(hit and ally.hp == 5 and mechanics.echo_progress == 0 and mechanics.basic_hits == 0, "哨械打中玩家，但不推进回响")
	for node in get_tree().get_nodes_in_group("combat_projectiles"):
		node.queue_free()
	sentry.state = sentry.State.HOLD
	sentry.global_position = sentry.home_position()
	player.global_position = sentry.home_position() + Vector2(160, 0)
	player._invuln_left = 0.0
	var cover := _thin_wall(training, sentry.home_position() + Vector2(80, 0), Vector2(20, 220))
	await get_tree().physics_frame
	var hp_after: int = player.hp
	await _physics_frames(45)
	_check(player.hp == hp_after and not Targeting.has_line_of_sight(sentry, player), "岩石挡住后哨械不再打到玩家")
	cover.queue_free()
	await get_tree().physics_frame
	sentry.set_physics_process(false)
	for node in get_tree().get_nodes_in_group("combat_projectiles"):
		node.queue_free()
	await get_tree().physics_frame
	ally.global_position = Vector2(900, 900)
	player.global_position = Vector2.ZERO
	sentry.global_position = Vector2(90, 0)
	var open_dummy = training.get_node("Dummy")
	var other = training.get_node("DummyB")
	var armor = training.get_node("ArmoredTarget")
	other.global_position = Vector2(800, 800)
	armor.global_position = Vector2(820, 800)
	open_dummy.global_position = Vector2(200, 140)
	open_dummy.hp = open_dummy.max_hp
	var sight := _thin_wall(training, Vector2(40, 0), Vector2(12, 20))
	await get_tree().physics_frame
	_check(ProgressState.add_item(&"bow_training", 1) and ProgressState.equip_weapon(&"bow_training") == "", "面对哨械时仍可装备弓")
	mechanics.reset_counts()
	var weapon = training.get_node("Player/EquippedAutoWeapon")
	weapon.set_physics_process(true)
	ProgressState.attack_cooldown_left = 0.0
	await get_tree().physics_frame
	weapon.set_physics_process(false)
	await _physics_frames(80)
	_check(open_dummy.hp == open_dummy.max_hp - 1 and sentry.hp == sentry.max_hp and mechanics.echo_progress == 1, "墙后的哨械不会让自动攻击停火")
	for node in get_tree().get_nodes_in_group("combat_projectiles"):
		node.queue_free()
	await get_tree().physics_frame
	var before := _hide_drops(training).size()
	var safe_hp: int = player.hp
	sentry.take_damage(99)
	sentry.take_damage(99)
	await get_tree().process_frame
	await get_tree().process_frame
	await _physics_frames(20)
	_check(_hide_drops(training).size() == before + 1 and player.hp == safe_hp and get_tree().get_nodes_in_group("combat_projectiles").is_empty(), "哨械死后只掉一次，也不再射击")
	sight.queue_free()


func _test_wolf_king() -> void:
	var outskirts := await _scene("res://scenes/exploration/outskirts.tscn")
	var placed = outskirts.get_node("WolfKing")
	var sentry = outskirts.get_node("Sentry")
	var spawn: Vector2 = outskirts.get_node("Player").global_position
	var cover_probe := Node2D.new()
	outskirts.add_child(cover_probe)
	cover_probe.global_position = Vector2(420, 640)
	_check(placed.loot_table_id == "loot_wolf_king" and placed.global_position.distance_to(spawn) > placed.notice_radius and sentry.global_position.distance_to(spawn) > sentry.notice_radius, "狼王和哨械都离出生点有安全距离")
	_check(placed.global_position.distance_to(sentry.global_position) > 120.0 and placed.global_position.distance_to(cover_probe.global_position) > placed.notice_radius and not Targeting.has_line_of_sight(sentry, cover_probe), "南侧是混合哨位，东侧岩石后仍能躲开哨械")
	cover_probe.queue_free()
	var training := await _scene("res://scenes/exploration/action_training.tscn")
	training.get_node("Hazard").set_physics_process(false)
	training.get_node("Player/EquippedAutoWeapon").set_physics_process(false)
	var king = preload("res://scenes/enemies/wolf_king.tscn").instantiate()
	king.position = Vector2(0, 280)
	king.windup_seconds = 0.25
	king.recovery_seconds = 0.45
	king.pounce_range = 180.0
	training.add_child(king)
	var player = training.get_node("Player")
	player.set_physics_process(false)
	player.global_position = Vector2.ZERO
	king.debug_velocity = Vector2(180, 0)
	var block := _thin_wall(training, Vector2(50, 280), Vector2(24, 80))
	await _physics_frames(12)
	_check(king.global_position.x < 42.0, "狼王被岩石挡住，不会穿墙")
	block.queue_free()
	king.debug_velocity = null
	king.global_position = king.home_position()
	player.global_position = king.home_position() + Vector2(120, 0)
	player._invuln_left = 0.0
	var warned := false
	for _i in 30:
		if king.state == king.State.WINDUP:
			warned = true
			break
		await get_tree().physics_frame
	_check(warned and player.hp == player.max_hp, "狼王先锁定扑击方向，预警时还没扑到")
	player.global_position = king.home_position() + Vector2(120, 140)
	var missed := false
	for _i in 50:
		if king.state == king.State.RECOVERY and player.hp == player.max_hp:
			missed = true
			break
		await get_tree().physics_frame
	_check(missed, "扑击方向锁定后可以躲开，扑空进入恢复")
	king.global_position = king.home_position()
	king._state_left = 0.0
	player.global_position = king.home_position() + Vector2(36, 0)
	player._invuln_left = 0.0
	var loadout = ProgressState.build_loadout
	var preset: Dictionary = loadout.active_preset()
	if String(preset.get("core", "")) != "inst_echo":
		_check(loadout.add_instance("inst_echo", "core_echo") == "" and loadout.set_slot("core", "inst_echo") == "", "狼王测试装上回响")
	else:
		_check(true, "狼王测试装上回响")
	var mechanics = ProgressState.get_node("BuildMechanics")
	mechanics.reset_counts()
	var struck := false
	for _i in 50:
		if player.hp < player.max_hp:
			struck = true
			break
		await get_tree().physics_frame
	_check(struck and mechanics.echo_progress == 0 and mechanics.basic_hits == 0, "狼王扑中玩家，但不推进回响")
	for _i in 20:
		if king.state == king.State.HOLD or king.state == king.State.RECOVERY:
			break
		await get_tree().physics_frame
	king.state = king.State.HOLD
	king.global_position = king.home_position()
	player.global_position = king.home_position() + Vector2(150, 0)
	player._invuln_left = 0.0
	var hp_after: int = player.hp
	var seen_windup := false
	for _i in 30:
		if king.state == king.State.WINDUP:
			seen_windup = true
			break
		await get_tree().physics_frame
	var cover := _thin_wall(training, king.home_position() + Vector2(70, 0), Vector2(24, 140))
	await get_tree().physics_frame
	await _physics_frames(40)
	_check(seen_windup and king.global_position.x < king.home_position().x + 58.0 and player.hp == hp_after, "扑击被岩石挡住，打不到墙后的玩家")
	cover.queue_free()
	var before := _fiber_drops(training).size()
	king.take_damage(99)
	king.take_damage(99)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_fiber_drops(training).size() == before + 1, "狼王死后只掉一次")
	_check(await _build_downs_king(training, &"sword_training", "inst_sword_core", "core_test_damage"), "试伤核心配短剑能打倒狼王")
	_check(await _build_downs_king(training, &"hammer_training", "inst_hammer_core", "core_break"), "破阵核心配重锤能打倒狼王")


func _build_downs_king(training: Node, weapon_id: StringName, instance_id: String, core_id: String) -> bool:
	var player = training.get_node("Player")
	player.global_position = Vector2.ZERO
	player._invuln_left = 9.0
	training.get_node("Dummy").global_position = Vector2(800, 800)
	training.get_node("DummyB").global_position = Vector2(840, 800)
	training.get_node("ArmoredTarget").global_position = Vector2(880, 800)
	var king = preload("res://scenes/enemies/wolf_king.tscn").instantiate()
	king.max_hp = 4
	king.position = Vector2(48, 0)
	training.add_child(king)
	var before := _fiber_drops(training).size()
	var loadout = ProgressState.build_loadout
	if loadout.add_instance(instance_id, core_id) != "" and not loadout.instances.has(instance_id):
		return false
	if loadout.set_slot("core", instance_id) != "":
		return false
	if not (ProgressState.add_item(weapon_id, 1) and ProgressState.equip_weapon(weapon_id) == ""):
		return false
	var weapon = training.get_node("Player/EquippedAutoWeapon")
	weapon.set_physics_process(true)
	ProgressState.attack_cooldown_left = 0.0
	for _i in 120:
		if not is_instance_valid(king) or king.hp <= 0:
			break
		await get_tree().physics_frame
	weapon.set_physics_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	return (not is_instance_valid(king) or king.hp <= 0) and _fiber_drops(training).size() == before + 1


func _test_forest_depths() -> void:
	const Catalog := preload("res://scripts/exploration/region_catalog.gd")
	const DEPTHS := "res://scenes/exploration/forest_depths.tscn"
	const OUTSKIRTS := "res://scenes/exploration/outskirts.tscn"
	ProgressState.reset()
	var outskirts_info: Dictionary = Catalog.region("outskirts")
	var depths_info: Dictionary = Catalog.region("forest_depths")
	_check(String(outskirts_info.get("id", "")) == "outskirts" and String(depths_info.get("id", "")) == "forest_depths", "区域表有外围和深处两区")
	_check(outskirts_info.get("encounters", []) != depths_info.get("encounters", []) \
		and String(outskirts_info.get("threat", "")).contains("不随玩家等级") \
		and String(depths_info.get("threat", "")).contains("不随玩家等级"), "两区遭遇不同，威胁写明不随等级")
	var outskirts := await _scene(OUTSKIRTS)
	_disable_weapons(outskirts.get_node("Player"))
	var armor_hp: int = outskirts.get_node("ArmoredWolf").max_hp
	ProgressState.add_item(&"sword_training", 20)
	_check(outskirts.get_node("ArmoredWolf").max_hp == armor_hp, "外围敌人生命不随持有物增加")
	_check(not _body_hits_terrain(outskirts.get_node("Player") as CharacterBody2D), "外围默认出生不在墙内")
	var trips_ok := 0
	for trip in 10:
		for node_name in ["ArmoredWolf", "BranchEnemy", "Wolf", "Sentry", "WolfKing"]:
			if outskirts.has_node(node_name):
				outskirts.get_node(node_name).set_physics_process(false)
		var player := outskirts.get_node("Player") as CharacterBody2D
		_disable_weapons(player)
		player.set_physics_process(true)
		player.global_position = Vector2(-1080, -420)
		var depths := await _walk_until_scene_change("move_left", 40)
		var ok := depths != null and depths.scene_file_path == DEPTHS
		if ok:
			var marker: Vector2 = depths.get_node("SpawnPoints/from_outskirts").global_position
			ok = depths.entry_id == &"from_outskirts" \
				and depths.get_node("Player").global_position.distance_to(marker) < 12.0 \
				and get_tree().get_nodes_in_group("player").size() == 1 \
				and not _body_hits_terrain(depths.get_node("Player") as CharacterBody2D)
			ok = ok and await _idle_keeps_scene(10)
		if ok:
			_disable_weapons(depths.get_node("Player"))
			if depths.has_node("Wolf"):
				depths.get_node("Wolf").set_physics_process(false)
			if depths.has_node("Sentry"):
				depths.get_node("Sentry").set_physics_process(false)
			depths.get_node("Player").global_position = Vector2(500, 0)
			outskirts = await _walk_until_scene_change("move_right", 40)
			ok = outskirts != null and outskirts.scene_file_path == OUTSKIRTS
		if ok:
			var back: Vector2 = outskirts.get_node("SpawnPoints/from_depths").global_position
			ok = outskirts.entry_id == &"from_depths" \
				and outskirts.get_node("Player").global_position.distance_to(back) < 12.0 \
				and get_tree().get_nodes_in_group("player").size() == 1 \
				and not _body_hits_terrain(outskirts.get_node("Player") as CharacterBody2D)
			ok = ok and await _idle_keeps_scene(10)
		if not ok:
			break
		trips_ok += 1
	_check(trips_ok == 10, "外围与深处连续往返 10 次，出生点正确、单一玩家、不立即回传（%d/10）" % trips_ok)
	SceneFlow.go_to_entry(DEPTHS, &"no_such_entry")
	await get_tree().process_frame
	await get_tree().process_frame
	var fallback := get_tree().current_scene
	_check(fallback.scene_file_path == DEPTHS and fallback.entry_id == &"from_outskirts", "深处未知入口回退到外围入口")
	var depths := await _scene(DEPTHS)
	_disable_weapons(depths.get_node("Player"))
	depths.get_node("Player").set_physics_process(false)
	depths.get_node("Wolf").set_physics_process(false)
	depths.get_node("Sentry").set_physics_process(false)
	_check(depths.has_node("Wolf") and depths.has_node("Sentry") and depths.has_node("ReachCache"), "深处同时有野狼、哨械和区域奖励")
	_check(depths.get_node("UI/ThreatLabel").text.contains("不随玩家等级"), "深处界面写出固定威胁")
	var wolf_hp: int = depths.get_node("Wolf").max_hp
	ProgressState.add_item(&"hammer_training", 9)
	_check(depths.get_node("Wolf").max_hp == wolf_hp, "深处敌人生命不随持有物增加")
	var cache = depths.get_node("ReachCache")
	_check(cache.try_pickup(), "深处缓存箱可以领取延伸")
	_check(ProgressState.build_loadout.instances.has("claim.forest_depths.cache_reach"), "领取后构筑里有该区延伸实例")
	var snapshot: Dictionary = ProgressState.build_loadout.export_state()
	depths = await _scene(DEPTHS)
	_check(not depths.has_node("ReachCache") and ProgressState.build_loadout.instances.has("claim.forest_depths.cache_reach"), "重进深处后奖励箱不再出现，实例还在")
	_check(ProgressState.grant_claimed_instance(&"forest_depths.cache_reach", "support_reach") == "已经领取", "同一标记不能再领一次")
	var later: Dictionary = ProgressState.build_loadout.export_state()
	_check(later.instances.has("claim.forest_depths.cache_reach") and int(later.instances.size()) == int(snapshot.instances.size()), "往返不改构筑实例名单")


func _test_boar_lair() -> void:
	const Catalog := preload("res://scripts/exploration/region_catalog.gd")
	const LAIR := "res://scenes/exploration/boar_lair.tscn"
	const DEPTHS := "res://scenes/exploration/forest_depths.tscn"
	const CLAIM := &"boar_lair.first_core"
	ProgressState.reset()
	var info: Dictionary = Catalog.region("boar_lair")
	_check(String(info.get("id", "")) == "boar_lair" and String(info.get("threat", "")).contains("不随玩家等级"), "巢穴写在区域表里，威胁不随等级")
	var training := await _scene("res://scenes/exploration/action_training.tscn")
	training.get_node("Hazard").set_physics_process(false)
	training.get_node("Player/EquippedAutoWeapon").set_physics_process(false)
	var stray = preload("res://scenes/combat/boar_king.tscn").instantiate()
	training.add_child(stray)
	stray.global_position = Vector2(300, 300)
	stray.take_damage(999)
	stray.take_damage(999)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not ProgressState.is_claimed(CLAIM), "竞技场那头的野猪王不发巢穴首次奖励")
	var depths := await _scene(DEPTHS)
	_disable_weapons(depths.get_node("Player"))
	depths.get_node("Wolf").set_physics_process(false)
	depths.get_node("Sentry").set_physics_process(false)
	depths.get_node("Player").set_physics_process(true)
	depths.get_node("Player").global_position = Vector2(0, 180)
	var lair := await _walk_until_scene_change("move_down", 40)
	_check(lair != null and lair.scene_file_path == LAIR and lair.entry_id == &"from_depths", "从深处能走进巢穴")
	_disable_weapons(lair.get_node("Player"))
	lair.get_node("BoarKing").set_physics_process(false)
	_check(get_tree().get_nodes_in_group("player").size() == 1 and not _body_hits_terrain(lair.get_node("Player") as CharacterBody2D), "巢穴出生不在墙内，也没有复制玩家")
	_check(await _idle_keeps_scene(10), "走进巢穴后不会立刻被送回深处")
	SceneFlow.go_to_entry(LAIR, &"no_such_entry")
	await get_tree().process_frame
	await get_tree().process_frame
	lair = get_tree().current_scene
	_check(lair.scene_file_path == LAIR and lair.entry_id == &"from_depths", "巢穴未知入口回退到深处入口")
	var boar = lair.get_node("BoarKing")
	var player = lair.get_node("Player")
	_disable_weapons(player)
	player.set_physics_process(false)
	boar.set_physics_process(false)
	ProgressState.add_item(&"material_fiber", 1)
	player.hp = 1
	player._invuln_left = 0.0
	player.take_damage(9)
	await get_tree().process_frame
	_check(lair.get_node("UI/DefeatPanel").visible and ProgressState.item_count(&"material_fiber") == 1 and not ProgressState.is_claimed(CLAIM), "倒下保留当前所得，也不发首次奖励")
	lair.get_node("UI/DefeatPanel/VBox/ReturnButton").pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(get_tree().current_scene.scene_file_path == "res://scenes/village/village.tscn" and ProgressState.item_count(&"material_fiber") == 1, "回村后内存所得还在")
	lair = await _scene(LAIR)
	_check(lair.has_node("BoarKing") and lair.get_node("BoarKing").hp == lair.get_node("BoarKing").max_hp and not ProgressState.is_claimed(CLAIM), "再进巢穴会重置野猪王，仍可重试")
	player = lair.get_node("Player")
	boar = lair.get_node("BoarKing")
	_disable_weapons(player)
	player.set_physics_process(false)
	boar.global_position = Vector2(0, -60)
	player.global_position = Vector2(90, -60)
	player._invuln_left = 0.0
	player.hp = player.max_hp
	boar.locked_direction = Vector2.RIGHT
	boar.dash_direction = Vector2.RIGHT
	boar.action_name = "charge_lock"
	boar._action_time = 0.4
	boar.set_physics_process(true)
	await get_tree().physics_frame
	player.global_position = Vector2(90, 90)
	await _physics_frames(40)
	_check(player.hp == player.max_hp and boar.action_name == "charge_recover", "锁向冲撞可以走位躲开，扑空进入恢复")
	boar.set_physics_process(false)
	boar.global_position = Vector2(100, -60)
	boar.dash_direction = Vector2.RIGHT
	boar.locked_direction = Vector2.RIGHT
	boar.action_name = "charge_dash"
	boar._action_time = 0.0
	boar.set_physics_process(true)
	await _physics_frames(20)
	_check(boar.global_position.x < 210.0, "冲刺撞上石柱就停，不穿墙")
	boar.set_physics_process(false)
	_check(await _build_downs_lair_boar(lair, &"sword_training", "inst_sword_core", "core_test_damage"), "试伤核心配短剑能打倒巢穴野猪王")
	_check(ProgressState.is_claimed(CLAIM) and ProgressState.build_loadout.instances.has("claim.boar_lair.first_core"), "首次击败发破阵，标记和实例在同一次领取里")
	var snap: Dictionary = ProgressState.snapshot(&"village", &"default")
	_check(snap.claimed_objects.has("boar_lair.first_core") and snap.build.instances.has("claim.boar_lair.first_core"), "回村快照同时记下领取和实例")
	_check(ProgressState.save_at_safe_point(&"village", &"default"), "回村可以写入存档")
	lair = await _scene(LAIR)
	_check(await _build_downs_lair_boar(lair, &"hammer_training", "inst_hammer_core", "core_echo"), "回响核心配重锤也能打倒重置后的野猪王")
	_check(ProgressState.grant_claimed_instance(CLAIM, "core_break") == "已经领取", "两套构筑打完也只领一次")
	boar = lair.get_node_or_null("BoarKing")
	if boar == null:
		boar = preload("res://scenes/combat/boar_king.tscn").instantiate()
		lair.add_child(boar)
	var before_inst := int(ProgressState.build_loadout.instances.size())
	boar.take_damage(999)
	boar.take_damage(999)
	await get_tree().process_frame
	_check(int(ProgressState.build_loadout.instances.size()) == before_inst, "同时致死只结算一次奖励")


func _test_facility() -> void:
	const Catalog := preload("res://scripts/exploration/region_catalog.gd")
	const ItemCatalog := preload("res://scripts/items/item_catalog.gd")
	const FACILITY := "res://scenes/exploration/facility.tscn"
	const OUTSKIRTS := "res://scenes/exploration/outskirts.tscn"
	const SWITCH := &"facility.switch"
	const SCHEMATIC := &"facility.schematic"
	const BLUEPRINT := &"blueprint_gun"
	ProgressState.reset()
	var info: Dictionary = Catalog.region("facility")
	var blueprint: Dictionary = ItemCatalog.get_item(BLUEPRINT)
	_check(String(info.get("id", "")) == "facility" and String(info.get("threat", "")).contains("不随玩家等级"), "设施写在区域表里，威胁不随等级")
	_check(String(blueprint.get("category_id", "")) == "blueprint" and String(blueprint.get("description", "")).contains("用途"), "火铳图纸写在物品表，说明里有用途")
	_check(not ProgressState.is_claimed(&"boar_lair.first_core"), "未击败野猪王也可以去设施")
	var outskirts := await _scene(OUTSKIRTS)
	_disable_weapons(outskirts.get_node("Player"))
	for node_name in ["ArmoredWolf", "BranchEnemy", "Wolf", "Sentry", "WolfKing"]:
		if outskirts.has_node(node_name):
			outskirts.get_node(node_name).set_physics_process(false)
	outskirts.get_node("Player").set_physics_process(true)
	outskirts.get_node("Player").global_position = Vector2(1000, -640)
	var facility := await _walk_until_scene_change("move_up", 40)
	_check(facility != null and facility.scene_file_path == FACILITY and facility.entry_id == &"from_outskirts", "从外围东北支路能走进设施")
	_disable_weapons(facility.get_node("Player"))
	facility.get_node("Sentry").set_physics_process(false)
	_check(get_tree().get_nodes_in_group("player").size() == 1 and not _body_hits_terrain(facility.get_node("Player") as CharacterBody2D), "设施出生不在墙内，也没有复制玩家")
	_check(await _idle_keeps_scene(10), "走进设施后不会立刻被送回外围")
	SceneFlow.go_to_entry(FACILITY, &"no_such_entry")
	await get_tree().process_frame
	await get_tree().process_frame
	facility = get_tree().current_scene
	_check(facility.scene_file_path == FACILITY and facility.entry_id == &"from_outskirts", "设施未知入口回退到外围入口")
	var player = facility.get_node("Player")
	var door = facility.get_node("InnerDoor")
	var power = facility.get_node("PowerSwitch")
	_disable_weapons(player)
	facility.get_node("Sentry").set_physics_process(false)
	player.set_physics_process(true)
	player.global_position = Vector2(0, 40)
	await _hold("move_up", 30)
	_check(player.global_position.y > -20.0 and door.collision_layer == 16, "关门时走不过北侧房间")
	player.set_physics_process(false)
	_check(power.try_activate() and ProgressState.is_claimed(SWITCH) and door.collision_layer == 0, "第一次开开关记下门状态并开门")
	_check(not power.try_activate() and ProgressState.item_count(BLUEPRINT) == 0, "再按开关不发图纸")
	player.global_position = Vector2(0, -140)
	_check(not _body_hits_terrain(player as CharacterBody2D), "开门后可以站进北侧房间")
	var cache = facility.get_node("SchematicCache")
	_check(cache.try_pickup() and ProgressState.item_count(BLUEPRINT) == 1 and ProgressState.is_claimed(SCHEMATIC), "门后图纸只领一次")
	_check(not ProgressState.claim_pickup(SCHEMATIC, BLUEPRINT, 1) and ProgressState.item_count(BLUEPRINT) == 1, "图纸箱不会发第二次")
	var inventory := facility.get_node("InventoryPanel")
	inventory.open()
	_check(inventory.is_open() and inventory.detail_text().contains("用途") and inventory.detail_text().contains("试验火铳") \
		and inventory.detail_text().contains("解锁"), "背包里能看到图纸的用途和解锁内容")
	inventory.close()
	var snap: Dictionary = ProgressState.snapshot(&"village", &"default")
	_check(snap.claimed_objects.has("facility.switch") and snap.claimed_objects.has("facility.schematic") \
		and snap.items.has("blueprint_gun"), "回村快照同时记下门、领取和图纸")
	_check(ProgressState.save_at_safe_point(&"village", &"default"), "回村可以写入存档")
	ProgressState.reset()
	_check(not ProgressState.is_claimed(SWITCH) and ProgressState.item_count(BLUEPRINT) == 0, "重置后内存里没有设施进度")
	ProgressState.load_from_disk()
	_check(ProgressState.is_claimed(SWITCH) and ProgressState.is_claimed(SCHEMATIC) and ProgressState.item_count(BLUEPRINT) == 1, "读档恢复门状态和图纸")
	facility = await _scene(FACILITY)
	_disable_weapons(facility.get_node("Player"))
	facility.get_node("Sentry").set_physics_process(false)
	_check(facility.get_node("InnerDoor").collision_layer == 0 and not facility.has_node("SchematicCache"), "再进设施时门仍开着，图纸箱不再出现")
	_check(not facility.get_node("PowerSwitch").try_activate() and ProgressState.item_count(BLUEPRINT) == 1, "读档后再开开关也不发奖励")
	_check(not ProgressState.is_claimed(&"boar_lair.first_core"), "走完设施也不要求先打野猪王")


func _test_craft() -> void:
	const Recipes := preload("res://scripts/items/recipe_catalog.gd")
	const Store := preload("res://scripts/save/progress_store.gd")
	const RECIPE := "recipe_gun_training"
	const FIBER := &"material_fiber"
	const BLUEPRINT := &"blueprint_gun"
	const GUN := &"gun_training"
	ProgressState.reset()
	_check(Recipes.ids().has(RECIPE), "配方表有试验火铳")
	_check(ProgressState.craft_blocked_reason(RECIPE) == "需要图纸", "没图纸不能做")
	_check(ProgressState.craft_recipe(RECIPE) == "需要图纸" and ProgressState.item_count(GUN) == 0, "没图纸不发武器")
	ProgressState.add_item(BLUEPRINT, 1)
	_check(ProgressState.craft_blocked_reason(RECIPE) == "材料不足", "有图纸但纤维不够")
	ProgressState.add_item(FIBER, 2)
	_check(ProgressState.craft_recipe(RECIPE) == "材料不足" and ProgressState.item_count(FIBER) == 2 and ProgressState.item_count(GUN) == 0, "材料不够不扣也不发")
	var store := Store.new("user://test_craft.json")
	store.delete_files_for_tests()
	ProgressState.use_store_for_tests(store)
	ProgressState.reset()
	_check(ProgressState.add_item(BLUEPRINT, 1) and ProgressState.add_item(FIBER, 3), "存档失败用例先备齐材料和图纸")
	_check(ProgressState.save_at_safe_point(&"village", &"default"), "存档失败用例先有一份有效存档")
	store.fail_commit_after_backup = true
	_check(ProgressState.craft_recipe(RECIPE) == "存档失败，没有扣除也没有发放", "写入失败时返回失败原因")
	_check(ProgressState.item_count(FIBER) == 3 and ProgressState.item_count(GUN) == 0 and ProgressState.item_count(BLUEPRINT) == 1, "存档失败不扣料也不发奖")
	store.fail_commit_after_backup = false
	store.delete_files_for_tests()
	ProgressState.use_store_for_tests(Store.new())
	ProgressState.reset()
	ProgressState.add_item(BLUEPRINT, 1)
	ProgressState.add_item(FIBER, 3)
	var village := await _scene("res://scenes/village/village.tscn")
	var craft = village.get_node("CraftPanel")
	craft.open_recipes()
	_check(craft.is_open() and craft.row_count() == 2 and craft.detail_text().contains("测试纤维") and craft.detail_text().contains("用途"), "配方页写出材料和用途")
	craft.close()
	_check(not craft.is_open() and ProgressState.item_count(FIBER) == 3 and ProgressState.item_count(GUN) == 0, "取消离开不制作")
	craft.open_recipes()
	_check(craft.try_craft_selected() == "" and ProgressState.item_count(GUN) == 1 and ProgressState.item_count(FIBER) == 0 and ProgressState.item_count(BLUEPRINT) == 1, "材料够才扣纤维并发火铳，图纸留下")
	_check(craft.try_craft_selected() == "材料不足" and ProgressState.item_count(GUN) == 1, "连点第二次不重复发奖")
	var inventory := village.get_node("InventoryPanel")
	inventory.open()
	var found_gun := false
	var found_purpose := false
	for i in inventory.row_texts().size():
		var row: String = inventory.row_texts()[i]
		if row.contains("试验火铳"):
			found_gun = true
		if row.contains("火铳图纸") or row.contains("测试纤维"):
			inventory._show_detail(i)
	found_purpose = inventory.detail_text().contains("用途")
	_check(found_gun and found_purpose, "背包能看到做出的火铳，材料说明仍有用途")
	inventory.close()
	var snap: Dictionary = ProgressState.snapshot(&"village", &"default")
	_check(int(snap.items.get("gun_training", 0)) == 1 and int(snap.items.get("material_fiber", 0)) == 0 and int(snap.items.get("blueprint_gun", 0)) == 1, "制作事务和存档快照一致")
	ProgressState.reset()
	ProgressState.load_from_disk()
	_check(ProgressState.item_count(GUN) == 1 and ProgressState.item_count(FIBER) == 0 and ProgressState.item_count(BLUEPRINT) == 1, "读档后火铳还在，纤维不会回来")


func _test_dismantle_and_enhance() -> void:
	const Catalog := preload("res://scripts/items/item_catalog.gd")
	const Derived := preload("res://scripts/build/build_derived_stats.gd")
	const AffixPool := preload("res://scripts/build/affix_pool.gd")
	const Store := preload("res://scripts/save/progress_store.gd")
	const FIBER := &"material_fiber"
	var fiber_item: Dictionary = Catalog.get_item(FIBER)
	_check(String(fiber_item.get("description", "")).contains("用途") \
		and String(fiber_item.get("description", "")).contains("强化") \
		and String(fiber_item.get("description", "")).contains("测试上限"), "纤维说明写出强化用途和测试上限")
	var store := Store.new("user://test_dismantle.json")
	store.delete_files_for_tests()
	ProgressState.use_store_for_tests(store)
	ProgressState.reset()
	var loadout = ProgressState.build_loadout
	_check(loadout.add_instance("inst_core", "core_test_damage") == "", "拆解用例先有试验核心")
	_check(loadout.add_instance("inst_echo", "core_echo") == "", "拆解用例先有回响核心")
	_check(loadout.add_instance("inst_haste_a", "support_haste") == "", "拆解用例先有急促")
	_check(loadout.add_instance("inst_reach", "support_reach") == "", "拆解用例先有延伸")
	_check(loadout.set_slot("core", "inst_core") == "" and loadout.set_slot("support_0", "inst_haste_a") == "", "甲套装上核心和急促")
	_check(loadout.set_active_preset("preset_b") == "", "切到乙套")
	_check(loadout.set_slot("core", "inst_echo") == "" and loadout.set_slot("support_0", "inst_haste_a") == "", "乙套用另一个核心和同一件急促")
	_check(loadout.set_active_preset("preset_a") == "", "切回甲套")
	_check(ProgressState.dismantle_component("inst_haste_a") == "还装在预设里，需要确认卸下再拆", "引用中的组件不能直接拆")
	_check(loadout.instances.has("inst_haste_a") and String(loadout.active_preset().get("support_0", "")) == "inst_haste_a", "拒绝拆解时预设引用还在")
	_check(ProgressState.dismantle_component("inst_reach") == "", "没装上的实例可以直接拆")
	_check(not loadout.instances.has("inst_reach") and loadout.has_discovered("support_reach"), "拆掉延伸后图鉴还在")
	_check(ProgressState.dismantle_component("inst_reach") == "未知实例", "连点第二次不会再拆一次")
	_check(ProgressState.dismantle_component("inst_haste_a", true) == "", "确认后卸下并拆掉引用中的急促")
	_check(not loadout.instances.has("inst_haste_a") and String(loadout.active_preset().get("core", "")) == "inst_core" \
		and String(loadout.active_preset().get("support_0", "")) == "", "甲套只卸下急促，核心还在")
	_check(loadout.set_active_preset("preset_b") == "" and String(loadout.active_preset().get("core", "")) == "inst_echo" \
		and String(loadout.active_preset().get("support_0", "")) == "", "乙套也不再引用那件急促，自己的核心还在")
	_check(loadout.has_discovered("support_haste"), "拆掉最后一件急促后图鉴仍记下定义")
	_check(loadout.set_locked("inst_core", true) == "" and ProgressState.dismantle_component("inst_core", true) == "已锁定，不能拆解", "锁定的不能靠确认拆掉")
	_check(loadout.set_locked("inst_core", false) == "", "解锁后再做强化和确认拆解")
	_check(loadout.set_active_preset("preset_a") == "" and loadout.set_slot("core", "inst_core") == "", "强化前甲套装回试验核心")
	_check(loadout.create_random_instance("rand_a", "support_haste", 4) == "" and loadout.set_slot("support_0", "rand_a") == "", "强化用例装上带词条的急促")
	var affixes_before: Array = loadout.instance("rand_a").get("affixes", [])
	var before_profile: Dictionary = Derived.from_weapon(ProgressState.equipped_weapon_id())
	_check(ProgressState.enhance_component("rand_a") == "材料不足" and int(loadout.instance("rand_a").get("level", 1)) == 1, "没纤维不能强化")
	_check(ProgressState.add_item(FIBER, 3) and ProgressState.enhance_component("rand_a") == "", "有纤维才能强化一级")
	var after_profile: Dictionary = Derived.from_weapon(ProgressState.equipped_weapon_id())
	_check(int(loadout.instance("rand_a").get("level", 1)) == 2 and ProgressState.item_count(FIBER) == 2, "强化后等级加一并扣一份纤维")
	_check(int(after_profile.damage) == int(before_profile.damage) + 1, "强化只把伤害加一")
	_check(loadout.instance("rand_a").get("affixes", []) == affixes_before and int(affixes_before.size()) == 2, "强化不改词条数量和内容")
	_check(String(after_profile.get("mechanic", "")) == String(before_profile.get("mechanic", "")), "强化不改核心机制")
	_check(ProgressState.enhance_component("rand_a") == "" and int(loadout.instance("rand_a").get("level", 1)) == 3, "可以强化到测试上限")
	_check(ProgressState.enhance_component("rand_a") == "已到测试上限" and ProgressState.item_count(FIBER) == 1 \
		and int(loadout.instance("rand_a").get("level", 1)) == 3, "到上限后连点不再扣料")
	var snap: Dictionary = ProgressState.snapshot(&"village", &"default")
	_check(snap.build.discovered.has("support_reach") and not snap.build.instances.has("inst_reach") \
		and int(snap.items.get("material_fiber", 0)) == 1, "拆解、图鉴和材料写在同一份快照")
	store.fail_commit_after_backup = true
	_check(ProgressState.enhance_component("inst_echo") == "存档失败，没有强化", "强化写入失败时返回失败原因")
	_check(int(loadout.instance("inst_echo").get("level", 1)) == 1 and ProgressState.item_count(FIBER) == 1, "存档失败不强化也不扣料")
	_check(ProgressState.dismantle_component("inst_echo", true) == "存档失败，没有拆解" and loadout.instances.has("inst_echo"), "拆解写入失败时实例还在")
	store.fail_commit_after_backup = false
	ProgressState.reset()
	ProgressState.load_from_disk()
	loadout = ProgressState.build_loadout
	_check(not loadout.instances.has("inst_reach") and loadout.has_discovered("support_reach"), "读档后延伸实例不在，图鉴还在")
	_check(int(loadout.instance("rand_a").get("level", 1)) == 3 and ProgressState.item_count(FIBER) == 1, "读档后强化等级和剩余纤维一致")
	var village := await _scene("res://scenes/village/village.tscn")
	var panel: Node = village.get_node("BuildPanel")
	panel.open()
	_check(panel.codex_text().contains("延伸") and panel.preview_text().contains("强化 +2"), "构筑页写出图鉴和强化数值")
	_check(panel.request_dismantle("inst_core") == "还装在预设里，需要确认卸下再拆" and panel.confirm_visible(), "引用中的拆解要确认")
	panel.cancel_dismantle()
	_check(not panel.confirm_visible() and loadout.instances.has("inst_core"), "取消确认不拆")
	_check(panel.request_dismantle("inst_core") == "还装在预设里，需要确认卸下再拆" and panel.confirm_dismantle() == "", "确认后才卸下并拆掉")
	_check(not loadout.instances.has("inst_core") and String(loadout.active_preset().get("core", "")) == "", "确认拆解后槽位空了")
	_check(loadout.set_active_preset("preset_b") == "" and String(loadout.active_preset().get("core", "")) == "inst_echo", "拆甲套核心不影响乙套回响")
	var inventory := village.get_node("InventoryPanel")
	inventory.open()
	var found_fiber := false
	for i in inventory.row_texts().size():
		if String(inventory.row_texts()[i]).contains("测试纤维"):
			inventory._show_detail(i)
			found_fiber = inventory.detail_text().contains("强化")
	_check(found_fiber, "背包里能看到纤维用于强化")
	inventory.close()
	var training := await _scene("res://scenes/exploration/action_training.tscn")
	var training_panel: Node = training.get_node("BuildPanel")
	training_panel.open()
	_check(training_panel.request_dismantle("inst_echo") == "战斗中不能拆解" and loadout.instances.has("inst_echo"), "战斗中不能拆解")
	_check(training_panel.request_enhance("rand_a") == "战斗中不能强化" and int(loadout.instance("rand_a").get("level", 1)) == 3, "战斗中不能强化")
	store.delete_files_for_tests()
	ProgressState.use_store_for_tests(Store.new())
	ProgressState.reset()


func _test_growth() -> void:
	const Derived := preload("res://scripts/build/build_derived_stats.gd")
	const Store := preload("res://scripts/save/progress_store.gd")
	const Targeting := preload("res://scripts/combat/combat_targeting.gd")
	const ContextScript := preload("res://scripts/combat/hit_context.gd")
	const Catalog := preload("res://scripts/items/item_catalog.gd")
	const FIBER := &"material_fiber"
	const TECH := "tech_bow_training"
	const RECIPE := "recipe_bow_training"
	const BOW := &"bow_training"
	ProgressState.reset()
	_check(ProgressState.player_level() == 1 and ProgressState.player_xp() == 0 and not ProgressState.has_tech(TECH), "新进度从等级 1 开始，没有技术")
	_check(ProgressState.craft_blocked_reason(RECIPE) == "需要技术", "没研究时不能做试验弓")
	_check(ProgressState.research_blocked_reason(TECH) == "需要等级", "等级不够不能研究")
	var training := await _scene("res://scenes/exploration/action_training.tscn")
	var player = training.get_node("Player")
	_disable_weapons(player)
	training.get_node("Hazard").set_physics_process(false)
	_check(player.max_hp == 8 and player.hp == 8, "等级 1 时生命仍是基础值")
	var dummy := training.get_node("Dummy")
	dummy.hp = 1
	var miss = ContextScript.new()
	miss.source = player
	miss.target = dummy
	miss.base_damage = 9
	miss.snapshot_damage = 9
	Targeting.resolve(miss)
	_check(ProgressState.player_level() == 1 and ProgressState.player_xp() == 0, "训练场击杀不给经验")
	player.hp = 5
	_check(ProgressState.add_xp(1) == "" and ProgressState.player_level() == 1 and ProgressState.player_xp() == 1, "一份经验还不够升级")
	_check(ProgressState.add_xp(1) == "" and ProgressState.player_level() == 2 and ProgressState.player_xp() == 0, "两份经验升到测试 2 级")
	_check(player.max_hp == 9 and player.hp == 6, "受伤时升级只把当前生命和上限一起加一")
	var before: Dictionary = Derived.from_weapon(ProgressState.equipped_weapon_id())
	_check(int(before.damage) == 2 and String(before.detail).contains("等级成长 +1"), "等级给基础伤害，不开放加点")
	var wolf := preload("res://scenes/enemies/wolf.tscn").instantiate()
	training.add_child(wolf)
	wolf.set_physics_process(false)
	var wolf_hp: int = wolf.max_hp
	_check(ProgressState.add_xp(2) == "" and ProgressState.player_level() == 3, "再两份经验升到测试区间上限")
	_check(ProgressState.add_xp(2) == "" and ProgressState.player_level() == 3 and ProgressState.player_xp() == 0, "测试上限后经验不再升级")
	_check(wolf.max_hp == wolf_hp and player.max_hp == 10, "敌人生命不随玩家等级变化")
	_check(ProgressState.research_blocked_reason(TECH) == "材料不足", "等级够了但纤维不够")
	var store := Store.new("user://test_growth.json")
	store.delete_files_for_tests()
	ProgressState.use_store_for_tests(store)
	ProgressState.reset()
	_check(ProgressState.add_xp(2) == "" and ProgressState.add_item(FIBER, 2), "研究用例先升到 2 级并备纤维")
	_check(ProgressState.save_at_safe_point(&"village", &"default"), "存档失败用例先有一份有效存档")
	store.fail_commit_after_backup = true
	_check(ProgressState.research_tech(TECH) == "存档失败，没有研究", "研究写入失败时返回失败原因")
	_check(not ProgressState.has_tech(TECH) and ProgressState.item_count(FIBER) == 2, "存档失败不扣料也不解锁")
	store.fail_commit_after_backup = false
	_check(ProgressState.research_tech(TECH) == "" and ProgressState.has_tech(TECH) and ProgressState.item_count(FIBER) == 0, "材料够才研究成功")
	_check(ProgressState.research_tech(TECH) == "已经解锁" and ProgressState.item_count(FIBER) == 0, "连点第二次不再扣料")
	_check(ProgressState.add_item(FIBER, 2) and ProgressState.craft_recipe(RECIPE) == "", "解锁后可以用纤维做出试验弓")
	_check(ProgressState.item_count(BOW) == 1, "技术有实际产出，不是只显示已解锁")
	var snap: Dictionary = ProgressState.snapshot(&"village", &"default")
	_check(int(snap.growth.level) == 2 and snap.growth.techs.has(TECH) and int(snap.items.get("bow_training", 0)) == 1, "等级、技术和弓写在同一份快照")
	ProgressState.reset()
	ProgressState.load_from_disk()
	_check(ProgressState.player_level() == 2 and ProgressState.has_tech(TECH) and ProgressState.item_count(BOW) == 1, "读档后等级和技术还在")
	var village := await _scene("res://scenes/village/village.tscn")
	var panel: Node = village.get_node("GrowthPanel")
	panel.open()
	_check(panel.is_open() and panel.status_text().contains("等级 2") and panel.detail_text().contains("试验弓"), "村落成长页写出等级和用途")
	_check(panel.try_research() == "已经解锁", "成长页不会重复研究")
	var craft = village.get_node("CraftPanel")
	craft.open_recipes()
	_check(craft.detail_text().contains("弓术试制") or craft.row_count() == 2, "合成铺能看到弓配方")
	craft.close()
	var fiber_item: Dictionary = Catalog.get_item(FIBER)
	_check(String(fiber_item.get("description", "")).contains("弓术"), "纤维说明写出研究用途")
	var outskirts := await _scene("res://scenes/exploration/outskirts.tscn")
	var hunter = outskirts.get_node("Player")
	_disable_weapons(hunter)
	hunter._invuln_left = 9.0
	for node_name in ["ArmoredWolf", "BranchEnemy", "Wolf", "Sentry", "WolfKing"]:
		if outskirts.has_node(node_name):
			outskirts.get_node(node_name).set_physics_process(false)
	var enemy = outskirts.get_node("BranchEnemy")
	enemy.max_hp = 1
	enemy.hp = 1
	var xp_before: int = ProgressState.player_xp()
	var hit = ContextScript.new()
	hit.source = hunter
	hit.target = enemy
	hit.base_damage = 9
	hit.snapshot_damage = 9
	Targeting.resolve(hit)
	_check(ProgressState.player_xp() == xp_before + 1 or ProgressState.player_level() > 2, "探索击杀给经验")
	store.delete_files_for_tests()
	ProgressState.use_store_for_tests(Store.new())
	ProgressState.reset()


func _test_ui_completeness() -> void:
	const Loot := preload("res://scripts/loot/loot_table.gd")
	ProgressState.reset()
	ProgressState.add_item(&"item_test_hide", 3)
	ProgressState.add_item(&"item_test_material", 1)
	ProgressState.add_item(&"sword_training", 1)
	ProgressState.add_item(&"sword_hunter", 1)
	var outskirts := await _scene("res://scenes/exploration/outskirts.tscn")
	_disable_weapons(outskirts.get_node("Player"))
	var inventory := outskirts.get_node("InventoryPanel")
	inventory.open()
	_check(inventory.row_texts() == PackedStringArray(["测试材料 ×1", "兽皮（测试掉落） ×3", "试验短剑 ×1", "猎手短剑 ×1"]), "默认筛选保持背包原顺序")
	var bag_list: ItemList = inventory.get_node("Root/Center/Panel/Margin/VBox/ItemList")
	bag_list.select(1)
	bag_list.item_selected.emit(1)
	_check(inventory.detail_text().contains("掉落规则和用途未定") and inventory.detail_text().contains("来源"), "背包详情写出说明和掉落来源")
	inventory.set_filter_index(1)
	_check(inventory.row_texts() == PackedStringArray(["试验短剑 ×1", "猎手短剑 ×1"]), "筛选只列出武器")
	inventory.set_filter_index(2)
	_check(inventory.row_texts() == PackedStringArray(["测试材料 ×1", "兽皮（测试掉落） ×3"]), "筛选素材不改原顺序")
	inventory.set_sort_index(1)
	_check(inventory.row_texts()[0] == "兽皮（测试掉落） ×3", "素材可按名称排序")
	inventory.set_filter_index(0)
	inventory.set_sort_index(0)
	_check(Loot.sources_text_for_item("item_test_hide").contains("林地野兽"), "兽皮来源来自掉落表而不是另写文案")
	var drop := preload("res://scenes/props/world_drop.tscn").instantiate()
	drop.item = preload("res://data/items/item_test_hide.tres")
	drop.amount = 1
	outskirts.add_child(drop)
	drop.global_position = Vector2(300, 300)
	var popup := outskirts.get_node("UI/ItemDetailPopup")
	popup.follow_mouse = false
	popup.update_for_world_point(drop.global_position)
	_check(popup.get_node("Panel/VBox/SourceLabel").text.contains("林地野兽"), "地上掉落详情写出掉落来源")
	_check(popup.get_node("Panel/VBox/HintLabel").text.contains("按 E 拾取"), "来源行不改拾取提示")
	await _press_action("pause")
	_check(not inventory.is_open() and not get_tree().paused, "Escape 先关背包，不打开暂停")
	var equipment := outskirts.get_node("EquipmentPanel")
	equipment.open_for(&"sword_hunter")
	_check(equipment.compare_text().contains("伤害") and equipment.compare_text().contains("猎手短剑"), "装备页比较当前武器和选中武器")
	var hunter_row: Node = null
	for row in equipment.get_node("Root/Center/Panel/Margin/VBox/Rows").get_children():
		if row.item_id == &"sword_hunter":
			hunter_row = row
	_check(hunter_row != null and not hunter_row.get_node("EquipButton").visible and hunter_row.get_node("ReasonLabel").text.contains("回村"), "探索中不能换装")
	equipment.close()
	var readout := outskirts.get_node("BuildCombatReadout")
	await get_tree().process_frame
	_check(readout.vital_text().contains("生命") and readout.region_text().contains("林地外围") and readout.weapon_text().contains("试验短剑"), "探索 HUD 显示生命、区域和当前武器")
	ProgressState.add_item(&"item_test_hide", 1)
	outskirts._on_player_defeated()
	_check(outskirts.get_node("UI/DefeatPanel").visible and outskirts.get_node("UI/DefeatPanel/VBox/StatsLabel").text.contains("本次收益") and outskirts.get_node("UI/DefeatPanel/VBox/StatsLabel").text.contains("核心触发"), "探索倒下结算写出本次收益和核心触发")
	ProgressState.reset()
	_check(ProgressState.grant_claimed_instance(&"test.codex.core", "core_test_damage") == "", "图鉴用例先发现试验核心")
	var village := await _scene("res://scenes/village/village.tscn")
	var codex := village.get_node("CodexPanel")
	codex.open()
	var rows: PackedStringArray = codex.row_texts()
	var found_core := false
	var found_hidden := false
	for line in rows:
		if line.contains("试验核心") and line.contains("已发现"):
			found_core = true
		if line.contains("未发现"):
			found_hidden = true
	_check(codex.status_text().contains("组件图鉴") and found_core and found_hidden, "图鉴区分已发现和未发现")
	village.get_node("InventoryPanel").open()
	var bag := " ".join(village.get_node("InventoryPanel").row_texts())
	_check(not bag.contains("试验核心"), "图鉴不等于背包，组件不记进库存完成度")
	village.get_node("InventoryPanel").close()
	codex.close()
	var arena := await _arena()
	_check(arena.get_node("RunStats").summary_text().contains("造成伤害") and arena.get_node("RunStats").summary_text().contains("核心触发"), "竞技场结算写出伤害来源和核心触发")
	_check(arena.get_node("BuildCombatReadout").region_text().contains("旧竞技场"), "竞技场 HUD 复用同一份战斗读出")
	ProgressState.reset()


func _test_full_slice() -> void:
	const Store := preload("res://scripts/save/progress_store.gd")
	const Derived := preload("res://scripts/build/build_derived_stats.gd")
	const VILLAGE := "res://scenes/village/village.tscn"
	const OUTSKIRTS := "res://scenes/exploration/outskirts.tscn"
	const DEPTHS := "res://scenes/exploration/forest_depths.tscn"
	const LAIR := "res://scenes/exploration/boar_lair.tscn"
	const FACILITY := "res://scenes/exploration/facility.tscn"
	const TRAINING := "res://scenes/exploration/action_training.tscn"
	const FIBER := &"material_fiber"
	const BLUEPRINT := &"blueprint_gun"
	const GUN := &"gun_training"
	const HUNTER := &"sword_hunter"
	var store := Store.new("user://test_slice.json")
	store.delete_files_for_tests()
	ProgressState.use_store_for_tests(store)
	ProgressState.reset()
	var adapter := ", ".join(OS.get_video_adapter_driver_info())
	print("SLICE_ENV os=%s cpus=%d window=%s adapter=%s fps=%.1f" % [
		OS.get_name(),
		OS.get_processor_count(),
		str(DisplayServer.window_get_size()),
		adapter,
		Engine.get_frames_per_second(),
	])
	print("STABILITY_20MIN=not_run")
	var export_blocked := not FileAccess.file_exists("res://export_presets.cfg")
	print("EXPORT_BLOCKED=%s" % export_blocked)
	_check(export_blocked, "没有导出预设，导出包不能用编辑器通过代替")
	var bus := Targeting.event_bus()
	var bus_before: int = bus.get_signal_connection_list("damage_resolved").size()
	var village := await _scene(VILLAGE)
	village.get_node("UI/StarterButton").pressed.emit()
	_check(ProgressState.is_claimed(ProgressState.STARTER_CLAIM) and ProgressState.item_count(&"sword_training") >= 1, "村落正式按钮领取试验短剑和回响")
	village.get_node("InventoryPanel").open()
	_check(village.get_node("InventoryPanel").is_open() and village.get_node("CodexPanel") != null, "切片用正式背包和图鉴页，不走开发者菜单")
	village.get_node("InventoryPanel").close()
	var build = village.get_node("BuildPanel")
	build.open()
	_check(build.equip_instance("claim.village.starter_kit") == "", "第一套预设通过构筑页装上回响")
	build.close()
	var round_one := PackedStringArray([OUTSKIRTS, DEPTHS, LAIR, FACILITY])
	for path in round_one:
		var scene := await _slice_visit(path)
		_check(scene.scene_file_path == path and scene.get_node_or_null("BuildCombatReadout") != null, "第一轮进入 %s" % path.get_file())
	var outskirts := get_tree().current_scene
	_check(ProgressState.grant_claimed_instance(&"outskirts.branch_hunt", "core_hunt") == "", "第一轮领取猎获")
	_check(ProgressState.grant_claimed_instance(&"outskirts.chest_shield", "support_shield_time") == "", "第一轮领取护持")
	_check(ProgressState.grant_claimed_instance(&"forest_depths.cache_reach", "support_reach") == "", "第一轮领取延伸")
	_check(ProgressState.grant_claimed_instance(&"boar_lair.first_core", "core_break") == "", "第一轮领取破阵")
	var facility := await _scene(FACILITY)
	_disable_weapons(facility.get_node("Player"))
	facility.get_node("Sentry").set_physics_process(false)
	_check(facility.get_node("PowerSwitch").try_activate() and facility.get_node("SchematicCache").try_pickup(), "第一轮用设施开关和图纸箱")
	_check(ProgressState.add_item(FIBER, 3) and ProgressState.add_item(HUNTER, 1), "访问外围来源后补测试纤维和猎手短剑（单图只掉 1 纤维）")
	village = await _scene(VILLAGE)
	var craft = village.get_node("CraftPanel")
	craft.open_recipes()
	_check(craft.try_craft_selected() == "" and ProgressState.item_count(GUN) == 1, "村落合成铺做出试验火铳")
	craft.close()
	var equipment = village.get_node("EquipmentPanel")
	equipment.open()
	equipment.equip_from_row(HUNTER)
	_check(ProgressState.equipped_weapon_id() == HUNTER, "村落装备页换上猎手短剑")
	equipment.close()
	build = village.get_node("BuildPanel")
	build.open()
	build.get_node("Root/Center/Panel/Margin/VBox/PresetRow/PresetB").pressed.emit()
	_check(build.equip_instance("claim.boar_lair.first_core") == "", "第二套预设通过构筑页装上破阵")
	build.get_node("Root/Center/Panel/Margin/VBox/PresetRow/PresetA").pressed.emit()
	_check(String(ProgressState.build_loadout.active_build_id) == "preset_a", "村落可以在两套预设之间切换")
	build.close()
	_check(ProgressState.save_at_safe_point(&"village", &"default"), "第一轮回村写入隔离档")
	outskirts = await _scene(OUTSKIRTS)
	_disable_weapons(outskirts.get_node("Player"))
	outskirts.get_node("Player")._invuln_left = 0.0
	outskirts.get_node("Player").take_damage(999)
	await get_tree().process_frame
	_check(outskirts.get_node("UI/DefeatPanel").visible, "倒下后出现正式返回入口")
	outskirts.get_node("UI/DefeatPanel/VBox/ReturnButton").pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(get_tree().current_scene.scene_file_path == VILLAGE, "倒下后从结算返回村落")
	for path in round_one:
		await _slice_visit(path)
	_check(ProgressState.grant_claimed_instance(&"outskirts.branch_hunt", "core_hunt") == "已经领取", "第二轮不重复发猎获")
	_check(ProgressState.grant_claimed_instance(&"boar_lair.first_core", "core_break") == "已经领取", "第二轮不重复发破阵")
	_check(not ProgressState.claim_pickup(&"facility.schematic", BLUEPRINT, 1) and ProgressState.item_count(BLUEPRINT) == 1, "第二轮不重复发图纸")
	village = await _scene(VILLAGE)
	village.get_node("CodexPanel").open()
	_check(village.get_node("CodexPanel").status_text().contains("已发现") and village.get_node("GrowthPanel") != null, "回村能查看图鉴和成长，不靠开发者菜单")
	village.get_node("CodexPanel").close()
	var claimed: Array = ProgressState.snapshot(&"village", &"default").claimed_objects
	ProgressState.reset()
	ProgressState.load_from_disk()
	_check(ProgressState.equipped_weapon_id() == HUNTER and ProgressState.item_count(GUN) == 1 \
		and ProgressState.is_claimed(&"boar_lair.first_core") and claimed.has("facility.schematic"), "重启读档恢复武器、制作结果和唯一奖励")
	var training := await _scene(TRAINING)
	training.get_node("Hazard").set_physics_process(false)
	_disable_weapons(training.get_node("Player"))
	var loadout = ProgressState.build_loadout
	_check(loadout.set_active_preset("preset_a") == "" and loadout.set_slot("core", "claim.village.starter_kit") == "", "对照前激活回响")
	var echo_report: Dictionary = await _slice_compare(training, "echo")
	_check(loadout.set_active_preset("preset_b") == "", "对照切换到破阵")
	var break_report: Dictionary = await _slice_compare(training, "break")
	print("SLICE_COMPARE %s" % JSON.stringify(echo_report))
	print("SLICE_COMPARE %s" % JSON.stringify(break_report))
	_check(echo_report.has("echo_triggers") and break_report.has("break_triggers") and echo_report.has("basic_damage") \
		and String(echo_report.get("build", "")) == "echo" and String(break_report.get("build", "")) == "break", "对照记录来源伤害和触发，不只看总伤害")
	var idle_projectiles := get_tree().get_nodes_in_group("combat_projectiles").size()
	await _physics_frames(20)
	_check(get_tree().get_nodes_in_group("combat_projectiles").size() <= idle_projectiles, "短时运行没有弹体堆积")
	await _slice_visit(OUTSKIRTS)
	await _slice_visit(FACILITY)
	var bus_after: int = bus.get_signal_connection_list("damage_resolved").size()
	_check(bus_after <= bus_before + 8, "换场景后结算订阅没有无界增长")
	print("SLICE_PERF enemies=%d projectiles=%d process_ms=%.2f" % [
		get_tree().get_nodes_in_group("enemies").size(),
		get_tree().get_nodes_in_group("combat_projectiles").size(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
	])
	store.delete_files_for_tests()
	ProgressState.use_store_for_tests(Store.new())
	ProgressState.reset()


func _slice_visit(path: String) -> Node:
	var scene := await _scene(path)
	var player := scene.get_node_or_null("Player")
	if player != null:
		_disable_weapons(player)
	for node_name in ["ArmoredWolf", "BranchEnemy", "Wolf", "Sentry", "WolfKing", "BoarKing"]:
		if scene.has_node(node_name):
			scene.get_node(node_name).set_physics_process(false)
	return scene


func _slice_compare(training: Node, build_id: String) -> Dictionary:
	const Derived := preload("res://scripts/build/build_derived_stats.gd")
	var dummy := training.get_node("Dummy")
	var armor := training.get_node("ArmoredTarget")
	dummy.global_position = Vector2(50, 0)
	armor.global_position = Vector2(52, 8)
	dummy.hp = dummy.max_hp
	armor.hp = armor.max_hp
	var player = training.get_node("Player")
	player.get_node("EquippedAutoWeapon").set_physics_process(true)
	ProgressState.attack_cooldown_left = 0.0
	var mechanics := ProgressState.get_node("BuildMechanics")
	var echo0: int = mechanics.echo_triggers
	var break0: int = mechanics.break_triggers
	var basic0: int = mechanics.basic_damage
	var mechanic0: int = mechanics.mechanic_damage
	var started: int = Time.get_ticks_msec()
	await _physics_frames(36)
	player.get_node("EquippedAutoWeapon").set_physics_process(false)
	return {
		"build": build_id,
		"elapsed_ms": Time.get_ticks_msec() - started,
		"taken": 0,
		"basic_damage": mechanics.basic_damage - basic0,
		"mechanic_damage": mechanics.mechanic_damage - mechanic0,
		"echo_triggers": mechanics.echo_triggers - echo0,
		"break_triggers": mechanics.break_triggers - break0,
		"dummy_hp": dummy.hp,
		"armor_hp": armor.hp,
		"derived": int(Derived.from_weapon(ProgressState.equipped_weapon_id()).get("damage", 0)),
	}


func _build_downs_lair_boar(lair: Node, weapon_id: StringName, instance_id: String, core_id: String) -> bool:
	var player = lair.get_node("Player")
	player.global_position = Vector2(56, -60)
	player._invuln_left = 9.0
	player.hp = player.max_hp
	var boar = lair.get_node_or_null("BoarKing")
	if boar == null:
		boar = preload("res://scenes/combat/boar_king.tscn").instantiate()
		lair.add_child(boar)
		boar.global_position = Vector2(0, -60)
		if lair.has_method("_on_boar_defeated") and boar.has_signal("defeated"):
			boar.defeated.connect(lair._on_boar_defeated)
	else:
		boar.global_position = Vector2(0, -60)
	boar.max_hp = 4
	boar.hp = 4
	boar.set_physics_process(false)
	var loadout = ProgressState.build_loadout
	if loadout.add_instance(instance_id, core_id) != "" and not loadout.instances.has(instance_id):
		return false
	if loadout.set_slot("core", instance_id) != "":
		return false
	if not (ProgressState.add_item(weapon_id, 1) and ProgressState.equip_weapon(weapon_id) == ""):
		return false
	var weapon = player.get_node("EquippedAutoWeapon")
	weapon.set_physics_process(true)
	ProgressState.attack_cooldown_left = 0.0
	for _i in 160:
		if not is_instance_valid(boar) or boar.hp <= 0:
			break
		await get_tree().physics_frame
	weapon.set_physics_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	return not is_instance_valid(boar) or boar.hp <= 0


func _fiber_drops(parent: Node) -> Array:
	var found: Array = []
	for node in parent.get_children():
		if node.get("item") != null and node.item.item_id == &"material_fiber":
			found.append(node)
	return found


func _spawn_loot_enemy(parent: Node, enemy_scene: PackedScene, table_id: String, at: Vector2) -> Node:
	var enemy := enemy_scene.instantiate()
	enemy.loot_table_id = table_id
	enemy.loot_seed = 3
	enemy.max_hp = 1
	enemy.move_speed = 0.0
	enemy.contact_damage = 0
	parent.add_child(enemy)
	enemy.position = at
	return enemy


func _hide_drops(parent: Node) -> Array:
	var found: Array = []
	for node in parent.get_children():
		if node.get("item") != null and node.item.item_id == &"item_test_hide" and node.get("object_id") == &"":
			found.append(node)
	return found


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
