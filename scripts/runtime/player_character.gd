class_name PlayerCharacter
extends CharacterBody2D
## Simple player character for play-test mode. WASD/arrow movement plus scripted control.

const SPEED: float = 200.0
const SIZE: float = 24.0

## The direction the player is currently facing (for event interaction).
var facing_direction: Vector2i = Vector2i(0, 1)

## When set by scripted control, overrides live input for one physics frame.
var _scripted_dir: Vector2 = Vector2.ZERO
var _use_scripted: bool = false

var _char_sprite: CharacterSprite = null


func _ready() -> void:
	# Visual — directional character sprite (falls back to a colour block when the
	# project has no player graphic assigned).
	_char_sprite = CharacterSprite.new()
	_char_sprite.setup(ProjectState.player_graphic, Color(0.9, 0.85, 0.2))
	_char_sprite.set_direction(facing_direction)
	add_child(_char_sprite)

	# Collision shape.
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(SIZE, SIZE)
	col.shape = shape
	add_child(col)


## Called by ScenarioRunner / agents to move one tile-step programmatically.
## direction must be one of: "left", "right", "up", "down"
func scripted_move(direction: String) -> void:
	match direction:
		"left":  _scripted_dir = Vector2(-1,  0)
		"right": _scripted_dir = Vector2( 1,  0)
		"up":    _scripted_dir = Vector2( 0, -1)
		"down":  _scripted_dir = Vector2( 0,  1)
		_:       _scripted_dir = Vector2.ZERO
	_use_scripted = true


func _physics_process(_delta: float) -> void:
	var input_dir := Vector2.ZERO

	if _use_scripted:
		input_dir = _scripted_dir
		_use_scripted = false
		_scripted_dir = Vector2.ZERO
	else:
		if Input.is_action_pressed("ui_left"):
			input_dir.x -= 1
		if Input.is_action_pressed("ui_right"):
			input_dir.x += 1
		if Input.is_action_pressed("ui_up"):
			input_dir.y -= 1
		if Input.is_action_pressed("ui_down"):
			input_dir.y += 1

	velocity = input_dir.normalized() * SPEED
	if input_dir != Vector2.ZERO:
		facing_direction = Vector2i(roundi(input_dir.x), roundi(input_dir.y))
	move_and_slide()

	if _char_sprite:
		_char_sprite.set_direction(facing_direction)
		_char_sprite.set_moving(velocity.length() > 1.0)
