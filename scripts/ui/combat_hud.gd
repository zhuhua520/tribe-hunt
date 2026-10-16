extends CanvasLayer
## 战斗 HUD：波次提示、暂停提示与胜负面板。

const SceneFlow = preload("res://scripts/ui/scene_flow.gd")
const BUILD_ADJUSTMENT_PANEL := preload("res://scenes/build/build_adjustment_panel.tscn")
const EXTRACTION_CHOICE_PANEL := preload("res://scenes/ui/extraction_choice_panel.tscn")

@onready var wave_label: Label = $Root/WaveLabel
@onready var status_label: Label = $Root/StatusLabel
@onready var build_status_label: Label = $Root/BuildStatusLabel
@onready var pause_hint: Label = $Root/PauseHint
@onready var result_panel: PanelContainer = $Root/ResultPanel
@onready var result_label: Label = $Root/ResultPanel/VBox/ResultLabel
@onready var stats_label: Label = $Root/ResultPanel/VBox/StatsLabel
@onready var restart_button: Button = $Root/ResultPanel/VBox/RestartButton
@onready var main_menu_button: Button = $Root/ResultPanel/VBox/MainMenuButton

var _build_adjustment_panel: Node
var _extraction_choice_panel: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	result_panel.visible = false
	pause_hint.text = _pause_hint_text()
	restart_button.pressed.connect(_on_restart_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	_build_adjustment_panel = BUILD_ADJUSTMENT_PANEL.instantiate()
	add_child(_build_adjustment_panel)
	_build_adjustment_panel.connect("confirmed", _on_build_adjustment_confirmed)
	_extraction_choice_panel = EXTRACTION_CHOICE_PANEL.instantiate()
	add_child(_extraction_choice_panel)
	_extraction_choice_panel.connect("continue_selected", _on_extraction_continue)
	_extraction_choice_panel.connect("extract_selected", _on_extraction_leave)
	BuildRunService.loadout_changed.connect(_update_build_status)
	_update_build_status()
	var wave_manager := get_parent().get_node_or_null("WaveManager")
	if wave_manager != null:
		if wave_manager.has_signal("wave_changed"):
			wave_manager.wave_changed.connect(_on_wave_changed)
		if wave_manager.has_signal("status_changed"):
			wave_manager.status_changed.connect(_on_status_changed)
		var total_waves := 3
		if "waves" in wave_manager:
			total_waves = maxi(1, wave_manager.waves.size())
		wave_label.text = "0/%d" % total_waves
		if wave_manager.has_signal("run_won"):
			wave_manager.run_won.connect(_on_run_won, CONNECT_DEFERRED)
		if wave_manager.has_signal("run_lost"):
			wave_manager.run_lost.connect(_on_run_lost, CONNECT_DEFERRED)
		if wave_manager.has_signal("run_extracted"):
			wave_manager.run_extracted.connect(_on_run_extracted, CONNECT_DEFERRED)
		if wave_manager.has_signal("build_adjustment_requested"):
			wave_manager.build_adjustment_requested.connect(_on_build_adjustment_requested)
		if wave_manager.has_signal("extraction_choice_requested"):
			wave_manager.extraction_choice_requested.connect(_on_extraction_choice_requested)


func _pause_hint_text() -> String:
	var events := InputMap.action_get_events("pause")
	for event in events:
		if event is InputEventKey:
			var key_event := event as InputEventKey
			var code := key_event.physical_keycode
			if code == 0:
				code = key_event.keycode
			if code != 0:
				return "%s 暂停" % OS.get_keycode_string(code)
	return "暂停"


func _on_wave_changed(wave_index: int, total_waves: int) -> void:
	wave_label.text = "%d/%d" % [wave_index, total_waves]
	if status_label.text == "准备狩猎" or status_label.text.begins_with("狩猎即将开始"):
		status_label.text = ""


func _on_status_changed(text: String) -> void:
	status_label.text = text


func _update_build_status() -> void:
	build_status_label.text = BuildRunService.active_summary()


func _on_build_adjustment_requested(wave_index: int, total_waves: int) -> void:
	_build_adjustment_panel.call("open_for_wave", wave_index, total_waves)


func _on_build_adjustment_confirmed() -> void:
	var wave_manager := get_parent().get_node_or_null("WaveManager")
	if wave_manager != null and wave_manager.has_method("complete_build_adjustment"):
		wave_manager.complete_build_adjustment()


func _on_extraction_choice_requested(wave_index: int, total_waves: int) -> void:
	_extraction_choice_panel.call("open_for_wave", wave_index, total_waves)


func _on_extraction_continue() -> void:
	var wave_manager := get_parent().get_node_or_null("WaveManager")
	if wave_manager != null and wave_manager.has_method("complete_extraction_continue"):
		wave_manager.complete_extraction_continue()


func _on_extraction_leave() -> void:
	var wave_manager := get_parent().get_node_or_null("WaveManager")
	if wave_manager != null and wave_manager.has_method("complete_extraction_leave"):
		wave_manager.complete_extraction_leave()


func _on_run_won() -> void:
	var headline := "狩猎成功！野猪王已被击败。"
	var stats := get_parent().get_node_or_null("RunStats")
	if stats == null or not ("boar_defeated" in stats) or not bool(stats.boar_defeated):
		headline = "狩猎成功！三波野兽已被击退。"
	_show_result(headline)


func _on_run_lost() -> void:
	_show_result("狩猎失败。按重新开始再试。")


func _on_run_extracted() -> void:
	_show_result("已撤离。本次运行在这里结束，没有发放奖励。")


func _show_result(text: String) -> void:
	# 胜负或撤离已经结束本局。构筑/撤离面板若仍盖在上面，结果按钮无法点击。
	if _build_adjustment_panel != null:
		_build_adjustment_panel.visible = false
	if _extraction_choice_panel != null:
		_extraction_choice_panel.visible = false
	get_tree().paused = false
	result_label.text = text
	stats_label.text = _stats_text()
	result_panel.visible = true


func _stats_text() -> String:
	var stats := get_parent().get_node_or_null("RunStats")
	if stats != null and stats.has_method("summary_text"):
		return str(stats.summary_text())
	return ""


func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_main_menu_pressed() -> void:
	SceneFlow.go_to(SceneFlow.MAIN_MENU)
