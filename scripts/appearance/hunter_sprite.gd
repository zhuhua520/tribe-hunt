extends Sprite2D
## 城镇猎人。图集四列是待机、走路、走路、攻击，四行是下、左、右、上。
## 脚对齐格子底边，这样和房屋、树使用同一个 Y 排序原点。

const FRAME_SIZE := Vector2i(128, 168)
const DIRECTION_ROWS := {
	"down": 0,
	"left": 1,
	"right": 2,
	"up": 3,
}

var state: String = "idle"
var _direction: String = "down"
var _clock: float = 0.0
var _attack_left: float = 0.0


func _ready() -> void:
	hframes = 4
	vframes = 4
	centered = true
	offset = Vector2(0, -FRAME_SIZE.y * 0.5 + 4.0)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_apply_frame()


func update_motion(motion: Vector2, delta: float) -> void:
	if _attack_left > 0.0:
		_attack_left -= delta
		_clock += delta
		if _attack_left <= 0.0:
			state = "idle"
			_clock = 0.0
		_apply_frame()
		return
	if motion.length_squared() > 0.001:
		if absf(motion.x) > absf(motion.y):
			_direction = "right" if motion.x > 0.0 else "left"
		else:
			_direction = "down" if motion.y > 0.0 else "up"
		if state != "walk":
			state = "walk"
			_clock = 0.0
		_clock += delta
	else:
		state = "idle"
		_clock = 0.0
	_apply_frame()


func set_facing(direction: Vector2) -> void:
	if direction.length_squared() < 0.0001:
		return
	if absf(direction.x) > absf(direction.y):
		_direction = "right" if direction.x > 0.0 else "left"
	else:
		_direction = "down" if direction.y > 0.0 else "up"
	_apply_frame()


func play_attack(direction: Vector2 = Vector2.ZERO) -> void:
	if direction.length_squared() > 0.001:
		if absf(direction.x) > absf(direction.y):
			_direction = "right" if direction.x > 0.0 else "left"
		else:
			_direction = "down" if direction.y > 0.0 else "up"
	state = "attack"
	_attack_left = 0.32
	_clock = 0.0
	_apply_frame()


func _apply_frame() -> void:
	var column := 0
	if state == "walk":
		column = 1 + int(_clock * 8.0) % 2
	elif state == "attack":
		column = 3
	frame_coords = Vector2i(column, int(DIRECTION_ROWS[_direction]))
