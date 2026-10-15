extends CanvasLayer
## 战斗 HUD：波次提示与胜负面板。

@onready var status_label: Label = $Root/StatusLabel
@onready var result_panel: PanelContainer = $Root/ResultPanel
@onready var result_label: Label = $Root/ResultPanel/VBox/ResultLabel
@onready var restart_button: Button = $Root/ResultPanel/VBox/RestartButton


func _ready() -> void:
	result_panel.visible = false
	restart_button.pressed.connect(_on_restart_pressed)
	var wave_manager := get_parent().get_node_or_null("WaveManager")
	if wave_manager != null:
		if wave_manager.has_signal("status_changed"):
			wave_manager.status_changed.connect(_on_status_changed)
		if wave_manager.has_signal("run_won"):
			wave_manager.run_won.connect(_on_run_won)
		if wave_manager.has_signal("run_lost"):
			wave_manager.run_lost.connect(_on_run_lost)


func _on_status_changed(text: String) -> void:
	status_label.text = text


func _on_run_won() -> void:
	_show_result("狩猎成功！三波野兽已被击退。")


func _on_run_lost() -> void:
	_show_result("狩猎失败。按重新开始再试。")


func _show_result(text: String) -> void:
	result_label.text = text
	result_panel.visible = true


func _on_restart_pressed() -> void:
	get_tree().reload_current_scene()
