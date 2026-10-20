extends RefCounted
## 分类占位图标。颜色之外用形状区分，缺图时用这块兜底，不依赖外部贴图。

static var _cache: Dictionary = {}


static func texture_for(category_id: String) -> Texture2D:
	if _cache.has(category_id):
		return _cache[category_id]
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	match category_id:
		"weapon":
			_fill_rect(image, Color(0.72, 0.42, 0.22, 1))
		"material":
			_fill_diamond(image, Color(0.38, 0.62, 0.32, 1))
		"blueprint":
			_fill_circle(image, Color(0.32, 0.48, 0.78, 1))
		"core":
			_fill_rect(image, Color(0.82, 0.68, 0.28, 1))
		"support":
			_fill_diamond(image, Color(0.58, 0.52, 0.78, 1))
		_:
			_fill_rect(image, Color(0.45, 0.45, 0.42, 1))
	var texture := ImageTexture.create_from_image(image)
	_cache[category_id] = texture
	return texture


static func _fill_rect(image: Image, color: Color) -> void:
	for y in range(3, 13):
		for x in range(3, 13):
			image.set_pixel(x, y, color)


static func _fill_diamond(image: Image, color: Color) -> void:
	for y in 16:
		for x in 16:
			if absi(x - 7) + absi(y - 7) <= 6:
				image.set_pixel(x, y, color)


static func _fill_circle(image: Image, color: Color) -> void:
	for y in 16:
		for x in 16:
			if Vector2(x - 7.5, y - 7.5).length() <= 6.0:
				image.set_pixel(x, y, color)
