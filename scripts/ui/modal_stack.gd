extends RefCounted
## 模态页关闭栈。不是 Autoload。Escape 先关顶层，再交给暂停菜单。


static var _layers: Array = []


static func push(panel: Node) -> void:
	if panel == null:
		return
	_layers.erase(panel)
	_layers.append(panel)


static func pop(panel: Node) -> void:
	_layers.erase(panel)


static func close_all_except(keep: Node) -> void:
	var copy: Array = _layers.duplicate()
	for panel in copy:
		if panel == keep:
			continue
		if typeof(panel) != TYPE_OBJECT or not is_instance_valid(panel):
			_layers.erase(panel)
			continue
		if panel.has_method("is_open") and panel.is_open() and panel.has_method("close"):
			panel.close()


static func close_top() -> bool:
	while not _layers.is_empty():
		var panel: Variant = _layers.back()
		if typeof(panel) != TYPE_OBJECT or not is_instance_valid(panel):
			_layers.pop_back()
			continue
		if not panel.has_method("is_open") or not panel.is_open():
			_layers.pop_back()
			continue
		if panel.has_method("close"):
			panel.close()
		return true
	return false


static func has_open() -> bool:
	for panel in _layers:
		if typeof(panel) == TYPE_OBJECT and is_instance_valid(panel) and panel.has_method("is_open") and panel.is_open():
			return true
	return false
