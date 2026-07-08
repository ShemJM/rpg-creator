class_name CharacterSprite
extends Node2D
## Reusable directional character sprite used by the player and events at runtime.
## Renders a CharacterGraphic charset (atlas region chosen by facing + walk frame),
## or a solid colour block fallback when no valid graphic is assigned. Animates the
## walk cycle only while moving.

const CELL_SIZE: int = 32
const FALLBACK_INSET: float = 8.0

var _graphic: CharacterGraphic = null
var _sprite: Sprite2D = null
var _fallback: ColorRect = null
var _facing: Vector2i = Vector2i(0, 1)
var _moving: bool = false
var _frame: int = 0
var _anim_accum: float = 0.0


## Configure this sprite. Pass a valid graphic to show a charset, otherwise a solid
## colour block of `fallback_color` is drawn.
func setup(graphic: CharacterGraphic, fallback_color: Color) -> void:
	_graphic = graphic
	_frame = 0
	_anim_accum = 0.0
	_clear_visual()
	var texture: Texture2D = null
	if graphic != null and graphic.is_valid():
		texture = ProjectState.load_texture(graphic.source_path)
	if texture != null:
		_sprite = Sprite2D.new()
		_sprite.texture = texture
		_sprite.centered = true
		_sprite.region_enabled = true
		add_child(_sprite)
		_update_region()
	else:
		_fallback = ColorRect.new()
		_fallback.color = fallback_color
		_fallback.size = Vector2(CELL_SIZE - FALLBACK_INSET, CELL_SIZE - FALLBACK_INSET)
		_fallback.position = -_fallback.size / 2.0
		add_child(_fallback)


func set_fallback_color(color: Color) -> void:
	if _fallback:
		_fallback.color = color


func set_direction(dir: Vector2i) -> void:
	if dir == Vector2i.ZERO or dir == _facing:
		return
	_facing = dir
	_update_region()


func get_direction() -> Vector2i:
	return _facing


func set_moving(moving: bool) -> void:
	if _moving == moving:
		return
	_moving = moving
	if not moving:
		_frame = 0
		_anim_accum = 0.0
		_update_region()


func _process(delta: float) -> void:
	if _sprite == null or _graphic == null or not _moving:
		return
	var fps: float = maxf(_graphic.anim_fps, 0.1)
	_anim_accum += delta
	if _anim_accum >= 1.0 / fps:
		_anim_accum -= 1.0 / fps
		var frame_count: int = maxi(_graphic.frames_per_direction, 1)
		_frame = (_frame + 1) % frame_count
		_update_region()


func _update_region() -> void:
	if _sprite == null or _graphic == null:
		return
	_sprite.region_rect = Rect2(_graphic.region_for(_facing, _frame))
	var fw: float = maxf(float(_graphic.frame_width), 1.0)
	var fh: float = maxf(float(_graphic.frame_height), 1.0)
	# Scale so a single frame fills roughly one map cell.
	_sprite.scale = Vector2(CELL_SIZE / fw, CELL_SIZE / fh)


func _clear_visual() -> void:
	if _sprite:
		_sprite.queue_free()
		_sprite = null
	if _fallback:
		_fallback.queue_free()
		_fallback = null
