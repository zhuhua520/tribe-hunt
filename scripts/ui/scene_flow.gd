extends RefCounted
## 菜单与战斗场景之间的切换。离开当前场景时解除暂停。

const MAIN_MENU := "res://scenes/menu/main_menu.tscn"
const MODE_SELECT := "res://scenes/menu/mode_select.tscn"
const EXPEDITION_PREP := "res://scenes/menu/expedition_prep.tscn"
const LOCAL_COOP_STATUS := "res://scenes/menu/local_coop_status.tscn"
const ONLINE_LOBBY := "res://scenes/menu/online_lobby.tscn"
const ONLINE_FRIENDS := "res://scenes/menu/online_friends.tscn"
const ONLINE_PUBLIC_ROOMS := "res://scenes/menu/online_public_rooms.tscn"
const WORKSHOP := "res://scenes/menu/workshop_placeholder.tscn"
const SETTINGS := "res://scenes/menu/settings_menu.tscn"
const ARENA := "res://scenes/combat/arena.tscn"
const MP_MOVE_ARENA := "res://scenes/combat/mp_move_arena.tscn"


static func go_to(scene_path: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("SceneFlow: 没有场景树")
		return
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_error("SceneFlow: 找不到场景 %s" % scene_path)
		return
	tree.paused = false
	DisplayServer.window_set_title("TribeHunt")
	tree.call_deferred("change_scene_to_file", scene_path)


static func quit() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	tree.quit()
