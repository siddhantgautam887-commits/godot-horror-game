extends Node3D

@export var mouse_sensitivity: float = 0.0025
@export var min_pitch: float = -1.5
@export var max_pitch: float = 1.5
@export var bob_speed: float = 8.0
@export var bob_amount: float = 0.03
@export var sprint_bob_multiplier: float = 1.7

@onready var camera: Camera3D = $Camera3D

var pitch: float = 0.0
var base_position: Vector3
var bob_time: float = 0.0
var player: Node3D

func _ready() -> void:
	base_position = position
	player = get_parent()
	
	if camera == null:
		push_warning("Head node is missing a Camera3D child.")
	
	if player == null:
		push_warning("Head node must be a child of Player.")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mouse_motion: InputEventMouseMotion = event
		if player != null:
			player.rotate_y(-mouse_motion.relative.x * mouse_sensitivity)
		pitch = clamp(pitch - mouse_motion.relative.y * mouse_sensitivity, min_pitch, max_pitch)
		if camera != null:
			camera.rotation.x = pitch

func _process(delta: float) -> void:
	update_head_bob(delta)

func update_head_bob(delta: float) -> void:
	if player == null:
		return
	
	# Access player properties safely
	var player_cast = player as CharacterBody3D
	if player_cast == null:
		return
	
	var moving: bool = player_cast.current_speed > 0.1
	var sprinting: bool = player_cast.is_sprinting

	if moving and player_cast.is_on_floor():
		bob_time += delta * bob_speed
		var current_bob: float = bob_amount
		if sprinting:
			current_bob *= sprint_bob_multiplier

		var x_bob: float = sin(bob_time) * current_bob
		var y_bob: float = cos(bob_time * 2.0) * current_bob * 0.5
		position = base_position + Vector3(x_bob, y_bob, 0.0)
	else:
		bob_time = 0.0
		position = position.lerp(base_position, 0.15)
