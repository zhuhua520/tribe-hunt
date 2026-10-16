extends VBoxContainer
## 可复用的设置控件。修改会立即作用于主音量或窗口，并写入设置存档。

signal back_pressed

const SettingsStore = preload("res://scripts/save/settings_store.gd")

const _WINDOW_LABELS: PackedStringArray = ["窗口", "全屏"]

@export var back_text: String = "返回"

@onready var _volume_slider: HSlider = $VolumeSlider
@onready var _volume_value: Label = $VolumeValue
@onready var _window_option: OptionButton = $WindowOption
@onready var _back_button: Button = $BackButton

var _updating: bool = false
var _dragging_volume: bool = false


func _ready() -> void:
	_back_button.text = back_text
	_back_button.pressed.connect(_on_back_pressed)
	_window_option.clear()
	for label in _WINDOW_LABELS:
		_window_option.add_item(label)
	_volume_slider.drag_started.connect(_on_volume_drag_started)
	_volume_slider.value_changed.connect(_on_volume_changed)
	_volume_slider.drag_ended.connect(_on_volume_drag_ended)
	_window_option.item_selected.connect(_on_window_selected)
	SettingsStore.load_and_apply()
	refresh()


func refresh() -> void:
	_updating = true
	_volume_slider.value = SettingsStore.master_volume
	_volume_value.text = _volume_text(SettingsStore.master_volume)
	_window_option.select(_index_for_mode(SettingsStore.window_mode))
	_updating = false


func _index_for_mode(mode: String) -> int:
	if mode == SettingsStore.WINDOW_FULLSCREEN:
		return 1
	return 0


func _volume_text(volume: float) -> String:
	return "当前 %d%%" % int(round(clampf(volume, 0.0, 1.0) * 100.0))


func _on_volume_drag_started() -> void:
	_dragging_volume = true


func _on_volume_changed(value: float) -> void:
	if _updating:
		return
	_volume_value.text = _volume_text(value)
	SettingsStore.set_master_volume(value, not _dragging_volume)


func _on_volume_drag_ended(_value_changed: bool) -> void:
	_dragging_volume = false
	if _updating:
		return
	SettingsStore.set_master_volume(_volume_slider.value, true)


func _on_window_selected(index: int) -> void:
	if _updating:
		return
	var mode: String = SettingsStore.WINDOW_WINDOWED
	if index == 1:
		mode = SettingsStore.WINDOW_FULLSCREEN
	SettingsStore.set_window_mode(mode, true)


func focus_back() -> void:
	_back_button.grab_focus()


func _on_back_pressed() -> void:
	back_pressed.emit()
