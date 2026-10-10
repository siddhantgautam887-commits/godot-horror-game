extends CharacterBody3D

# Player movement variables
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var acceleration: float = 10.0
@export var friction: float = 15.0
var current_speed: float = 0.0
var is_sprinting: bool = false

# Camera and look variables
@onready var camera: Camera3D = $Camera3D
@onready var head: Node3D = $Head
@export var mouse_sensitivity: float = 0.003
@export var min_pitch: float = -PI / 2
@export var max_pitch: float = PI / 2

# Inventory and equipment
var inventory: Dictionary = {
	"torch": true,
	"walkie_talkie": true,
	"baton": true
}

var active_item: String = "torch"

# Torch variables
@onready var torch: Node3D = $Torch
@export var torch_flicker_chance: float = 0.05
@export var torch_brightness: float = 1.0
var torch_on: bool = true
var flicker_timer: float = 0.0

# Walkie-talkie variables
@onready var walkie_talkie: Node3D = $WalkieTalkie
var walkie_on: bool = false
var last_message_time: float = 0.0

# Baton variables
@onready var baton: Node3D = $Baton
var baton_equipped: bool = false

# Fear/Sanity system
@export var max_sanity: float = 100.0
var current_sanity: float = 100.0
@export var sanity_drain_rate: float = 5.0
var is_near_ghost: bool = false
var ghost_scare_intensity: float = 0.0

# Audio
@onready var footstep_player: AudioStreamPlayer3D = $FootstepPlayer
@onready var ambient_player: AudioStreamPlayer3D = $AmbientPlayer
@onready var heartbeat_player: AudioStreamPlayer3D = $HeartbeatPlayer

# State machine
var state: String = "idle"  # idle, walking, running, scared

func _ready():
	# Hide cursor and lock it to window
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Initialize torch
	torch_on = true
	update_torch_state()
	
	# Start ambient sounds
	play_ambient_sound()
	
	# Initialize sanity
	current_sanity = max_sanity

func _process(delta: float) -> void:
	handle_input()
	update_camera_look()
	handle_torch_flicker(delta)
	update_sanity(delta)
	update_heartbeat(delta)
	update_state()

func _physics_process(delta: float) -> void:
	handle_movement(delta)
	move_and_slide()

# ============================================================================
# INPUT HANDLING
# ============================================================================

func handle_input() -> void:
	# Unlock cursor
	if Input.is_action_just_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Sprint toggle
	is_sprinting = Input.is_action_pressed("sprint")
	
	# Torch toggle
	if Input.is_action_just_pressed("torch"):
		toggle_torch()
	
	# Walkie-talkie toggle
	if Input.is_action_just_pressed("walkie"):
		toggle_walkie_talkie()
	
	# Baton equip
	if Input.is_action_just_pressed("baton"):
		equip_baton()

# ============================================================================
# MOVEMENT SYSTEM
# ============================================================================

func handle_movement(delta: float) -> void:
	# Get input direction
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Determine target speed
	var target_speed = walk_speed
	if is_sprinting and input_dir.length() > 0:
		target_speed = sprint_speed
	
	# Apply acceleration/friction
	if direction.length() > 0:
		current_speed = lerp(current_speed, target_speed, acceleration * delta)
		play_footsteps()
	else:
		current_speed = lerp(current_speed, 0.0, friction * delta)
	
	# Apply gravity
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0
	
	# Set velocity
	velocity.x = direction.x * current_speed
	velocity.z = direction.z * current_speed

# ============================================================================
# CAMERA LOOK
# ============================================================================

func update_camera_look() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	
	var mouse_velocity = Input.get_last_mouse_velocity()
	
	# Horizontal rotation (player body)
	rotate_y(-mouse_velocity.x * mouse_sensitivity)
	
	# Vertical rotation (camera pitch)
	var pitch_change = -mouse_velocity.y * mouse_sensitivity
	var new_pitch = camera.rotation.x + pitch_change
	new_pitch = clamp(new_pitch, min_pitch, max_pitch)
	camera.rotation.x = new_pitch

# ============================================================================
# TORCH SYSTEM
# ============================================================================

func toggle_torch() -> void:
	if not inventory["torch"]:
		return
	
	torch_on = not torch_on
	update_torch_state()

func update_torch_state() -> void:
	if torch and torch.has_node("OmniLight3D"):
		var light = torch.get_node("OmniLight3D")
		light.visible = torch_on

func handle_torch_flicker(delta: float) -> void:
	if not torch_on:
		return
	
	flicker_timer += delta
	
	# Random flicker chance
	if randf() < torch_flicker_chance:
		if torch and torch.has_node("OmniLight3D"):
			var light = torch.get_node("OmniLight3D")
			# Flicker effect - reduce brightness
			light.energy_multiplier = torch_brightness * randf_range(0.3, 1.0)
			await get_tree().create_timer(0.1).timeout
			light.energy_multiplier = torch_brightness
	
	# Increase flicker chance when sanity is low
	if current_sanity < 30:
		flicker_timer = 0.0

# ============================================================================
# WALKIE-TALKIE SYSTEM
# ============================================================================

func toggle_walkie_talkie() -> void:
	if not inventory["walkie_talkie"]:
		return
	
	walkie_on = not walkie_on
	
	if walkie_on:
		play_walkie_static()

func play_walkie_static() -> void:
	# Play static/broken audio - placeholder
	print("Walkie-talkie: *STATIC* ... Team members are... *STATIC*")
	last_message_time = Time.get_ticks_msec() / 1000.0

# ============================================================================
# BATON SYSTEM
# ============================================================================

func equip_baton() -> void:
	if not inventory["baton"]:
		return
	
	baton_equipped = not baton_equipped
	
	if baton_equipped:
		print("Baton equipped. (Useless for combat)")
	else:
		print("Baton unequipped.")

# ============================================================================
# SANITY/FEAR SYSTEM
# ============================================================================

func update_sanity(delta: float) -> void:
	# Drain sanity if near ghost or scared
	if is_near_ghost or ghost_scare_intensity > 0:
		current_sanity -= sanity_drain_rate * delta
		ghost_scare_intensity = max(0, ghost_scare_intensity - delta)
	
	# Clamp sanity
	current_sanity = clamp(current_sanity, 0, max_sanity)
	
	# Low sanity effects
	if current_sanity < 20:
		apply_fear_effects()

func apply_fear_effects() -> void:
	# Apply visual/audio distortions when sanity is critically low
	if randf() < 0.02:  # 2% chance per frame
		# Screen shake or distortion effects
		camera.position += Vector3(randf_range(-0.05, 0.05), randf_range(-0.05, 0.05), 0)
		await get_tree().create_timer(0.1).timeout
		camera.position = Vector3.ZERO

func take_scare_damage(intensity: float) -> void:
	current_sanity -= intensity
	ghost_scare_intensity = 1.0

# ============================================================================
# HEARTBEAT SYSTEM (increases with fear)
# ============================================================================

func update_heartbeat(delta: float) -> void:
	var sanity_ratio = current_sanity / max_sanity
	
	if sanity_ratio < 0.5:
		# Play heartbeat sound when sanity is low
		if not heartbeat_player.playing:
			heartbeat_player.play()
		
		# Increase playback speed as sanity decreases
		var heartbeat_speed = lerp(0.8, 2.0, 1.0 - sanity_ratio)
		heartbeat_player.pitch_scale = heartbeat_speed
	else:
		heartbeat_player.stop()

# ============================================================================
# FOOTSTEPS
# ============================================================================

func play_footsteps() -> void:
	if not is_on_floor():
		return
	
	# Play footstep sound - placeholder
	if not footstep_player.playing and current_speed > 0:
		# Randomize footstep sound
		pass

# ============================================================================
# AMBIENT SOUNDS
# ============================================================================

func play_ambient_sound() -> void:
	# Play background ambient horror sounds
	if ambient_player:
		ambient_player.play()

# ============================================================================
# STATE MACHINE
# ============================================================================

func update_state() -> void:
	if current_sanity <= 0:
		state = "dead"
		handle_death()
	elif is_sprinting or current_speed > walk_speed * 0.8:
		state = "running"
	elif current_speed > 0:
		state = "walking"
	elif current_sanity < 30:
		state = "scared"
	else:
		state = "idle"

func handle_death() -> void:
	print("Player has lost all sanity. Game Over!")
	# Implement game over logic

# ============================================================================
# GHOST DETECTION
# ============================================================================

func set_ghost_nearby(nearby: bool, intensity: float = 1.0) -> void:
	is_near_ghost = nearby
	if nearby:
		ghost_scare_intensity = intensity

# ============================================================================
# DEBUG / INFO
# ============================================================================

func get_player_info() -> Dictionary:
	return {
		"position": global_position,
		"sanity": current_sanity,
		"state": state,
		"torch_on": torch_on,
		"walkie_on": walkie_on,
		"baton_equipped": baton_equipped
	}
