extends RefCounted
## 通过 Godot 导入资源加载临时素材，兼容打包后的路径重映射并共享纹理。

const ASSET_BASE := "res://assets/borrowed_preview/ninja_adventure/"

static var _texture_cache: Dictionary = {}


static func texture(file_name: String) -> Texture2D:
	if _texture_cache.has(file_name):
		return _texture_cache[file_name] as Texture2D
	var path := ASSET_BASE + file_name
	var loaded_texture := load(path) as Texture2D
	if loaded_texture == null:
		push_error("无法读取临时美术资源: " + path)
		return null
	_texture_cache[file_name] = loaded_texture
	return loaded_texture
