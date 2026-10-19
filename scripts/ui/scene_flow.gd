extends RefCounted
## 菜单与战斗场景之间的切换。离开当前场景时解除暂停。
## 探索地图之间用 go_to_entry 传入口 ID；目标场景在 _ready 用 place_at_entry 取出并放置玩家。

const MAIN_MENU := "res://scenes/menu/main_menu.tscn"
const MODE_SELECT := "res://scenes/menu/mode_select.tscn"
const VILLAGE := "res://scenes/village/village.tscn"
const OUTSKIRTS := "res://scenes/exploration/outskirts.tscn"
const EXPEDITION_PREP := "res://scenes/menu/expedition_prep.tscn"
const LOCAL_COOP_STATUS := "res://scenes/menu/local_coop_status.tscn"
const ONLINE_LOBBY := "res://scenes/menu/online_lobby.tscn"
const ONLINE_FRIENDS := "res://scenes/menu/online_friends.tscn"
const ONLINE_PUBLIC_ROOMS := "res://scenes/menu/online_public_rooms.tscn"
const WORKSHOP := "res://scenes/menu/workshop_placeholder.tscn"
const SETTINGS := "res://scenes/menu/settings_menu.tscn"
const ARENA := "res://scenes/combat/arena.tscn"
const MP_MOVE_ARENA := "res://scenes/combat/mp_move_arena.tscn"

static var _pending_entry_id: StringName = &""


static func go_to(scene_path: String) -> void:
	_pending_entry_id = &""
	_change_to_file(scene_path)


static func go_to_entry(scene_path: String, entry_id: StringName) -> void:
	_pending_entry_id = &""
	if _change_to_file(scene_path):
		_pending_entry_id = entry_id


static func go_to_packed(packed_scene: PackedScene) -> void:
	_pending_entry_id = &""
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or packed_scene == null:
		return
	tree.paused = false
	DisplayServer.window_set_title("TribeHunt")
	tree.call_deferred("change_scene_to_packed", packed_scene)


## 取出并清空入口 ID，把 body 放到 spawn_root 下同名的 Node2D。未知或缺省入口回退到 fallback_id。
static func place_at_entry(body: Node2D, spawn_root: Node, fallback_id: StringName) -> StringName:
	var entry_id := _pending_entry_id
	_pending_entry_id = &""
	var marker: Node2D = null
	if entry_id != &"":
		marker = spawn_root.get_node_or_null(NodePath(String(entry_id))) as Node2D
		if marker == null:
			push_warning("SceneFlow: 未知入口 %s，使用默认入口 %s" % [entry_id, fallback_id])
	if marker == null:
		entry_id = fallback_id
		marker = spawn_root.get_node_or_null(NodePath(String(fallback_id))) as Node2D
	if marker == null:
		push_error("SceneFlow: 缺少默认入口 %s" % fallback_id)
		return &""
	body.global_position = marker.global_position
	return entry_id


static func quit() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	tree.quit()


static func _change_to_file(scene_path: String) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("SceneFlow: 没有场景树")
		return false
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_error("SceneFlow: 找不到场景 %s" % scene_path)
		return false
	tree.paused = false
	DisplayServer.window_set_title("TribeHunt")
	tree.call_deferred("change_scene_to_file", scene_path)
	return true
