extends Node2D
## 部落村落场景：
## - 四周以方块围成边界（未来用于做树木 UI 限制村落范围，右方留出村道路口）
## - 村内设置武器店（仅边框形状占位，不弹 UI）与合成店占位（仅形状占位，不弹 UI）
## - 玩家走上右侧出村道路时打开出征选择 UI（左侧分类占位、右侧具体目的地出征点）
## - 出征选择返回时回到村落；确认出征进入战斗场景 Arena
## - 左侧道路（OutskirtsExit）进入林地外围探索图；从外围返回时出生在 SpawnPoints/from_outskirts
## - 村落是安全点：每次进入都把持有物、领取状态和当前入口写入进度存档
## - 摄像机挂在玩家身上，画面只显示镜头范围内的村落；地图大于视口

const SceneFlow = preload("res://scripts/ui/scene_flow.gd")
const PreviewArt := preload("res://scripts/systems/borrowed_preview_art.gd")

const VILLAGE_HALF_SIZE := Vector2(1600.0, 1000.0)
const GROUND_MARGIN := Vector2(320.0, 240.0)
const TREE_BLOCK_STEP := 94.0
const ROAD_HALF_HEIGHT := 56.0
const ROAD_INNER_INSET := 40.0
const ROAD_OUTER_LENGTH := 180.0

@onready var _camera: Camera2D = $VillagePlayer/Camera2D
@onready var _ground: Polygon2D = $Ground
@onready var _floor: Polygon2D = $VillageFloor
@onready var _road_floor: Polygon2D = $ExitRoadFloor
@onready var _road_border: Line2D = $ExitRoadBorder
@onready var _road_label: Label = $ExitRoadLabel
@onready var _tree_hint: Label = $TreeHintLabel
@onready var _tree_ring: Node2D = $TreeBorderRing
@onready var _player: CharacterBody2D = $VillagePlayer
@onready var _player_sprite: Sprite2D = $VillagePlayer/Sprite2D
@onready var _ground_art: Sprite2D = $GroundArt
@onready var _road_area: Area2D = $ExitRoadArea
@onready var _expedition_overlay: Control = $UI/ExpeditionOverlay
@onready var _confirm_button: Button = $UI/ExpeditionOverlay/Center/Panel/Margin/MainVBox/BottomBar/ConfirmButton
@onready var _back_button: Button = $UI/ExpeditionOverlay/Center/Panel/Margin/MainVBox/BottomBar/BackButton
@onready var _build_options: VBoxContainer = $UI/ExpeditionOverlay/Center/Panel/Margin/MainVBox/Columns/RightDestBox/PrepConfigBox/BuildOptions
@onready var _build_summary: Label = $UI/ExpeditionOverlay/Center/Panel/Margin/MainVBox/Columns/RightDestBox/PrepConfigBox/BuildSummaryLabel
@onready var _rhythm_option: OptionButton = $UI/ExpeditionOverlay/Center/Panel/Margin/MainVBox/Columns/RightDestBox/PrepConfigBox/RhythmOption
@onready var _category_forest_btn: Button = $UI/ExpeditionOverlay/Center/Panel/Margin/MainVBox/Columns/LeftCategoryBox/CatForestButton
@onready var _category_swamp_btn: Button = $UI/ExpeditionOverlay/Center/Panel/Margin/MainVBox/Columns/LeftCategoryBox/CatSwampButton
@onready var _category_ruins_btn: Button = $UI/ExpeditionOverlay/Center/Panel/Margin/MainVBox/Columns/LeftCategoryBox/CatRuinsButton
@onready var _dest_boar_btn: Button = $UI/ExpeditionOverlay/Center/Panel/Margin/MainVBox/Columns/RightDestBox/DestList/DestBoarWoodsButton
@onready var _dest_placeholder_btn: Button = $UI/ExpeditionOverlay/Center/Panel/Margin/MainVBox/Columns/RightDestBox/DestList/DestPlaceholderButton
@onready var _dest_desc_label: Label = $UI/ExpeditionOverlay/Center/Panel/Margin/MainVBox/Columns/RightDestBox/DestDescLabel
@onready var _return_menu_btn: Button = $UI/TopBar/ReturnMenuButton

var _module_checkboxes: Dictionary = {}
var _selected_dest_valid: bool = true
var _leaving: bool = false
var _tree_texture_a: Texture2D
var _tree_texture_b: Texture2D


func _ready() -> void:
	DisplayServer.window_set_title("TribeHunt - 部落村落")
	_ground_art.texture = PreviewArt.texture("village_ground.png")
	$VillagePlayer/Shadow.texture = PreviewArt.texture("shadow.png")
	$WeaponShopArt/Sprite2D.texture = PreviewArt.texture("hut_weapon.png")
	$SynthesisShopArt/Sprite2D.texture = PreviewArt.texture("hut_synthesis.png")
	_tree_texture_a = PreviewArt.texture("tree_round.png")
	_tree_texture_b = PreviewArt.texture("tree_tall.png")
	var entry_id := SceneFlow.place_at_entry(_player, $SpawnPoints, &"default")
	var saved := ProgressState.save_at_safe_point(&"village", entry_id)
	var save_note := "进度已保存" if saved else "进度未保存（存档版本较新或写入失败）"
	$UI/InventoryLabel.text = "%s · %s" % [ProgressState.summary_text(), save_note]
	_layout_map()
	_configure_camera()
	_spawn_tree_border_blocks()
	_spawn_village_decor()
	_expedition_overlay.visible = false
	_road_area.body_entered.connect(_on_exit_road_body_entered)
	_confirm_button.pressed.connect(_on_confirm_expedition_pressed)
	_back_button.pressed.connect(_on_close_expedition_overlay)
	_return_menu_btn.pressed.connect(_on_return_menu_pressed)
	_category_forest_btn.pressed.connect(_on_category_selected.bind("forest"))
	_category_swamp_btn.pressed.connect(_on_category_selected.bind("swamp"))
	_category_ruins_btn.pressed.connect(_on_category_selected.bind("ruins"))
	_dest_boar_btn.pressed.connect(_on_dest_selected.bind(true))
	_dest_placeholder_btn.pressed.connect(_on_dest_selected.bind(false))
	_build_module_options()
	_build_rhythm_options()
	_on_category_selected("forest")


func _physics_process(delta: float) -> void:
	if _expedition_overlay.visible or _leaving:
		_player.velocity = Vector2.ZERO
		return
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_player.velocity = input_vector * 240.0
	_player.move_and_slide()
	_update_player_sprite(input_vector, delta)
	var min_x := -VILLAGE_HALF_SIZE.x + 24.0
	var max_x := VILLAGE_HALF_SIZE.x - 24.0
	if absf(_player.global_position.y) <= ROAD_HALF_HEIGHT - 12.0:
		min_x = -VILLAGE_HALF_SIZE.x - 120.0
		max_x = VILLAGE_HALF_SIZE.x + 120.0
	_player.global_position.x = clampf(_player.global_position.x, min_x, max_x)
	_player.global_position.y = clampf(_player.global_position.y, -VILLAGE_HALF_SIZE.y + 24.0, VILLAGE_HALF_SIZE.y - 24.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed("ui_cancel"):
		return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
	if _expedition_overlay.visible:
		_on_close_expedition_overlay()


func _layout_map() -> void:
	var ground_half := VILLAGE_HALF_SIZE + GROUND_MARGIN
	_ground.polygon = _centered_rect(ground_half)
	_floor.polygon = _centered_rect(VILLAGE_HALF_SIZE)
	var road_left := VILLAGE_HALF_SIZE.x - ROAD_INNER_INSET
	var road_right := VILLAGE_HALF_SIZE.x + ROAD_OUTER_LENGTH
	var road := PackedVector2Array([
		Vector2(road_left, -ROAD_HALF_HEIGHT),
		Vector2(road_right, -ROAD_HALF_HEIGHT),
		Vector2(road_right, ROAD_HALF_HEIGHT),
		Vector2(road_left, ROAD_HALF_HEIGHT),
	])
	_road_floor.polygon = road
	_road_border.points = road
	_place_label(_road_label, Rect2(road_left + 16.0, -18.0, road_right - road_left - 32.0, 36.0))
	_place_label(_tree_hint, Rect2(-260.0, -VILLAGE_HALF_SIZE.y + 48.0, 520.0, 30.0))
	_road_area.position = Vector2(VILLAGE_HALF_SIZE.x + 80.0, 0.0)


func _configure_camera() -> void:
	var ground_half := VILLAGE_HALF_SIZE + GROUND_MARGIN
	_camera.position_smoothing_enabled = false
	_camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	_camera.limit_left = int(round(-ground_half.x))
	_camera.limit_top = int(round(-ground_half.y))
	_camera.limit_right = int(round(ground_half.x))
	_camera.limit_bottom = int(round(ground_half.y))
	_camera.enabled = true
	_camera.make_current()


func _centered_rect(half: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])


func _place_label(label: Label, rect: Rect2) -> void:
	label.offset_left = rect.position.x
	label.offset_top = rect.position.y
	label.offset_right = rect.end.x
	label.offset_bottom = rect.end.y


func _spawn_tree_border_blocks() -> void:
	var x := -VILLAGE_HALF_SIZE.x
	while x <= VILLAGE_HALF_SIZE.x:
		_add_tree_block(Vector2(x, -VILLAGE_HALF_SIZE.y))
		_add_tree_block(Vector2(x, VILLAGE_HALF_SIZE.y))
		x += TREE_BLOCK_STEP

	var y := -VILLAGE_HALF_SIZE.y + TREE_BLOCK_STEP
	while y <= VILLAGE_HALF_SIZE.y - TREE_BLOCK_STEP:
		if absf(y) > ROAD_HALF_HEIGHT:
			_add_tree_block(Vector2(-VILLAGE_HALF_SIZE.x, y))
			_add_tree_block(Vector2(VILLAGE_HALF_SIZE.x, y))
		y += TREE_BLOCK_STEP


func _add_tree_block(pos: Vector2) -> void:
	var tree := Node2D.new()
	tree.position = pos
	var sprite := Sprite2D.new()
	sprite.texture = _tree_texture_a if int(round(pos.x / TREE_BLOCK_STEP + pos.y / TREE_BLOCK_STEP)) % 2 == 0 else _tree_texture_b
	sprite.position = Vector2(0.0, -48.0)
	sprite.scale = Vector2(2.0, 2.0)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tree.add_child(sprite)
	_tree_ring.add_child(tree)


func _spawn_village_decor() -> void:
	var positions: Array[Vector2] = [
		Vector2(-480, 60),
		Vector2(480, 60),
		Vector2(-500, 270),
		Vector2(500, 270),
		Vector2(-300, 420),
		Vector2(300, 420),
	]
	for index in positions.size():
		var tree := Node2D.new()
		tree.name = "VillageTree_%02d" % index
		tree.position = positions[index]
		var sprite := Sprite2D.new()
		sprite.texture = _tree_texture_a if index % 2 == 0 else _tree_texture_b
		sprite.position = Vector2(0.0, -48.0)
		sprite.scale = Vector2(2.0, 2.0)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tree.add_child(sprite)
		add_child(tree)


func _update_player_sprite(input_vector: Vector2, delta: float) -> void:
	_player_sprite.update_motion(input_vector, delta)


func _on_exit_road_body_entered(body: Node) -> void:
	if body != _player or _expedition_overlay.visible or _leaving:
		return
	_open_expedition_overlay()


func _open_expedition_overlay() -> void:
	_player.velocity = Vector2.ZERO
	_expedition_overlay.visible = true
	_confirm_button.grab_focus()


func _on_close_expedition_overlay() -> void:
	_expedition_overlay.visible = false
	if _player.global_position.x > VILLAGE_HALF_SIZE.x - 60.0:
		_player.global_position.x = VILLAGE_HALF_SIZE.x - 80.0


func _on_category_selected(cat_id: String) -> void:
	if cat_id == "forest":
		_dest_boar_btn.visible = true
		_dest_placeholder_btn.text = "迷雾林深处（占位，暂未开放）"
		_on_dest_selected(true)
	elif cat_id == "swamp":
		_dest_boar_btn.visible = false
		_dest_placeholder_btn.text = "腐泥沼泽出征点（分类占位）"
		_on_dest_selected(false)
	else:
		_dest_boar_btn.visible = false
		_dest_placeholder_btn.text = "远古石环出征点（分类占位）"
		_on_dest_selected(false)


func _on_dest_selected(is_boar_woods: bool) -> void:
	_selected_dest_valid = is_boar_woods
	_confirm_button.disabled = not is_boar_woods
	if is_boar_woods:
		_dest_desc_label.text = "当前目的地：【野猪林外围（出征点）】\n三波普通野兽与末段野猪王遭遇（已接入战斗场景）。"
	else:
		_dest_desc_label.text = "当前目的地：占位区域（尚未开放，请选择「近郊猎场」→「野猪林外围」出征）。"


func _on_confirm_expedition_pressed() -> void:
	if not _selected_dest_valid or _leaving:
		return
	_leaving = true
	BuildRunService.set_prepared_module_ids(_selected_module_ids())
	BuildRunService.set_extraction_wave_interval(_rhythm_option.get_selected_id())
	SceneFlow.go_to(SceneFlow.ARENA)


func _on_return_menu_pressed() -> void:
	if _leaving:
		return
	_leaving = true
	SceneFlow.go_to(SceneFlow.MAIN_MENU)


func _build_rhythm_options() -> void:
	_rhythm_option.clear()
	_rhythm_option.add_item("每波开放", BuildRunService.EXTRACTION_EVERY_WAVE)
	_rhythm_option.add_item("每两波开放", BuildRunService.EXTRACTION_EVERY_TWO_WAVES)
	var selected_index := 0
	if BuildRunService.extraction_wave_interval == BuildRunService.EXTRACTION_EVERY_TWO_WAVES:
		selected_index = 1
	_rhythm_option.select(selected_index)


func _build_module_options() -> void:
	for module in BuildRunService.get_module_definitions():
		var checkbox := CheckBox.new()
		checkbox.text = "%s：%s（临时原型值）" % [module.display_name, module.prototype_effect_label()]
		checkbox.button_pressed = BuildRunService.is_prepared(module.module_id)
		checkbox.custom_minimum_size = Vector2(0.0, 34.0)
		checkbox.toggled.connect(_on_module_toggled.bind(module.module_id))
		_module_checkboxes[module.module_id] = checkbox
		_build_options.add_child(checkbox)
	_update_build_summary()


func _on_module_toggled(_is_selected: bool, _module_id: String) -> void:
	_update_build_summary()


func _selected_module_ids() -> Array[String]:
	var selected_ids: Array[String] = []
	for module in BuildRunService.get_module_definitions():
		var checkbox := _module_checkboxes[module.module_id] as CheckBox
		if checkbox.button_pressed:
			selected_ids.append(module.module_id)
	return selected_ids


func _update_build_summary() -> void:
	var selected := PackedStringArray()
	for module_id in _selected_module_ids():
		var module := BuildRunService.get_module(module_id)
		if module != null:
			selected.append(module.display_name)
	_build_summary.text = "本次携带：" + ("、".join(selected) if not selected.is_empty() else "暂不携带模块")
