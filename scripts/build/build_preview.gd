extends Control
## 临时构筑预览。直接打开本场景核对样例数据和两种计数。
## 不是正式入口，不保存，不进入战斗或联机。

const CATALOG_PATH := "res://data/build/sample_catalog.tres"

var _catalog: BuildCatalog
var _state := BuildProbeState.new()
var _snapshot: Dictionary = {}
var _summary: Label
var _notice: Label


func _ready() -> void:
	_catalog = load(CATALOG_PATH) as BuildCatalog
	if _catalog == null:
		push_error("BuildPreview: 无法加载样例目录 %s" % CATALOG_PATH)
		return
	_snapshot = _definition_snapshot()
	_build_view()
	_refresh("ready")


func _build_view() -> void:
	var root := $Margin/Scroll/Root as VBoxContainer
	var title := _make_label("临时构筑预览", 28)
	root.add_child(title)
	_notice = _make_label("", 16)
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_notice)
	_summary = _make_label("", 18)
	root.add_child(_summary)

	var weapon_heading := _make_label("武器样例", 22)
	root.add_child(weapon_heading)
	for weapon in _catalog.weapons:
		root.add_child(_make_label(_weapon_text(weapon), 16))

	var module_heading := _make_label("模块样例（按钮只改本次运行的测试状态）", 22)
	root.add_child(module_heading)
	for module in _catalog.modules:
		root.add_child(_make_module_block(module))


func _make_module_block(module: ModuleDefinition) -> VBoxContainer:
	var block := VBoxContainer.new()
	block.name = "Module_%s" % module.module_id
	block.add_theme_constant_override("separation", 4)
	var detail := _make_label("", 16)
	detail.name = "Detail"
	block.add_child(detail)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_make_button("标记发现", _on_discover, module))
	row.add_child(_make_button("装备一件", _on_equip, module))
	row.add_child(_make_button("卸下一件", _on_unequip, module))
	row.add_child(_make_button("运行时强化 +1", _on_raise_upgrade, module))
	block.add_child(row)
	return block


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _make_button(text: String, handler: Callable, module: ModuleDefinition) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 36)
	button.pressed.connect(handler.bind(module))
	return button


func _on_discover(module: ModuleDefinition) -> void:
	var is_new := _state.discover_star(module.star_point_id)
	_refresh("discover star=%s new=%s" % [module.star_point_id, str(is_new).to_lower()])


func _on_equip(module: ModuleDefinition) -> void:
	_state.equip(module.module_id)
	_refresh("equip module=%s" % module.module_id)


func _on_unequip(module: ModuleDefinition) -> void:
	var removed := _state.unequip_one(module.module_id)
	_refresh("unequip module=%s removed=%s" % [module.module_id, str(removed).to_lower()])


func _on_raise_upgrade(module: ModuleDefinition) -> void:
	var level := _state.raise_upgrade(module.module_id)
	_refresh(
		"upgrade module=%s runtime_level=%d initial_star=%d"
		% [module.module_id, level, module.initial_star]
	)


func _refresh(action: String) -> void:
	var constellation := _catalog.constellations[0]
	var unique_count := _state.unique_discovered_count(constellation)
	var star_total := constellation.star_point_ids.size()
	var equipped_count := _state.equipped_piece_count(constellation, _catalog.modules)
	var unchanged := _definition_snapshot() == _snapshot
	_notice.text = (
		"本场景只核对样例数据。不保存玩家成长，不改单人战斗，也不进入联机。"
		+ "收集完成度按独特星点去重；装备件数按当前测试列表里的模块件数计算。"
		+ "槽位上限、掉落、重复模块能否同时装备、套装门槛和奖励效果都未定。"
	)
	var lines: PackedStringArray = PackedStringArray()
	lines.append(
		"星座 %s　已发现独特星点 %d/%d　当前装备件数 %d"
		% [constellation.display_name, unique_count, star_total, equipped_count]
	)
	lines.append("套装奖励：未定义　完整收集奖励：未定义")
	lines.append("共享定义未被改写：%s" % ("是" if unchanged else "否"))
	for module in _catalog.modules:
		var block := $Margin/Scroll/Root.get_node("Module_%s" % module.module_id) as VBoxContainer
		var detail := block.get_node("Detail") as Label
		var upgrade_level := _state.latest_upgrade_level(module.module_id)
		var upgrade_text := "未装备" if upgrade_level < 0 else str(upgrade_level)
		detail.text = _module_text(module, upgrade_text)
	_summary.text = "\n".join(lines)
	print(
		"BUILD_PROBE action=%s unique=%d/%d equipped=%d definitions_unchanged=%s"
		% [action, unique_count, star_total, equipped_count, str(unchanged).to_lower()]
	)


func _weapon_text(weapon: WeaponDefinition) -> String:
	return (
		"%s（%s）　攻击方式 %s　类别 %s　稀有度 %s　品质 %s　属性/固有/特效/强化上限/掉落：占位未定"
		% [
			weapon.display_name,
			weapon.weapon_id,
			weapon.attack_style_label(),
			weapon.category_label,
			weapon.rarity_label(),
			weapon.quality_label(),
		]
	)


func _module_text(module: ModuleDefinition, upgrade_text: String) -> String:
	var discovered := "已发现" if _state.has_discovered(module.star_point_id) else "未发现"
	return (
		"%s　类别 %s　初始星级 %d　运行时强化 %s　元素 %s（值 %d，不生效）　适配类别 %s　原型战斗效果 %s　星点 %s　本模块测试装备 %d 件　%s"
		% [
			module.display_name,
			module.category_label(),
			module.initial_star,
			upgrade_text,
			module.element_label(),
			module.element_value,
			module.weapon_category_label,
			module.prototype_effect_label(),
			discovered,
			_state.equipped_count_for(module.module_id),
			module.module_id,
		]
	)


func _definition_snapshot() -> Dictionary:
	var data: Dictionary = {}
	for weapon in _catalog.weapons:
		data["weapon:%s" % weapon.weapon_id] = "%s|%s|%s|%s|%s|%s" % [
			weapon.weapon_id,
			str(weapon.rarity),
			str(weapon.quality),
			str(weapon.upgrade_cap),
			str(weapon.drop_weight),
			weapon.unique_effect_id,
		]
	for module in _catalog.modules:
		data["module:%s" % module.module_id] = "%s|%s|%s|%s|%s" % [
			str(module.initial_star),
			str(module.element_kind),
			str(module.element_value),
			module.weapon_category_tag,
			"%s|%s|%s" % [module.special_affix_id, str(module.prototype_effect), str(module.prototype_effect_percent)],
		]
	for constellation in _catalog.constellations:
		data["constellation:%s" % constellation.constellation_id] = "%s|%s|%s" % [
			",".join(constellation.star_point_ids),
			constellation.set_bonus_placeholder,
			constellation.completion_reward_placeholder,
		]
	return data
