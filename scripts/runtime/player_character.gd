class_name PlayerCharacter
extends CharacterBody2D
## Simple player character for play-test mode. WASD movement, collides with walls.

const SPEED: float = 200.0
const SIZE: float = 24.0

## The direction the player is currently facing (for event interaction).
var facing_direction: Vector2i = Vector2i(0, 1)


func _ready() -> void:
	# Visual — colored rect.
	var sprite := ColorRect.new()
	sprite.color = Color(0.9, 0.85, 0.2)
	sprite.size = Vector2(SIZE, SIZE)
	sprite.position = Vector2(-SIZE / 2.0, -SIZE / 2.0)
	add_child(sprite)

	# Collision shape.
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(SIZE, SIZE)
	col.shape = shape
	add_child(col)


func _physics_process(_delta: float) -> void:
	var input_dir := Vector2.ZERO
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
