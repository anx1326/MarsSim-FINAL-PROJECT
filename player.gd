extends CharacterBody3D

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.5
@export var jump_velocity: float = 4.8
@export var mouse_sensitivity: float = 0.003
@export var jetpack_thrust: float = 3.5

var gravity: float = 3.71 # Martian Gravity (m/s^2)
var stamina: float = 100.0
var head_bob_time: float = 0.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		if camera_pivot:
			camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
			camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(-75), deg_to_rad(75))

func _physics_process(delta: float) -> void:
	# 1. Martian Gravity & Jetpack Handling
	if not is_on_floor():
		if Input.is_action_pressed("ui_accept") and stamina > 5.0:
			velocity.y += jetpack_thrust * delta
			stamina -= 10.0 * delta # Jetpack consumes suit stamina
		else:
			velocity.y -= gravity * delta
	else:
		# Recharge stamina slowly on the ground
		stamina = min(100.0, stamina + 20.0 * delta)
		if Input.is_action_just_pressed("ui_accept"):
			velocity.y = jump_velocity

	# 2. Sprinting with Stamina Check
	var is_sprinting := Input.is_key_pressed(KEY_SHIFT) and stamina > 10.0
	var current_speed = sprint_speed if is_sprinting else walk_speed
	
	if is_sprinting:
		stamina -= 15.0 * delta

	# 3. Movement Direction
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
		
		# Procedural Head Bobbing effect when moving on floors
		if is_on_floor():
			head_bob_time += delta * (12.0 if is_sprinting else 7.0)
			if camera:
				camera.position.y = sin(head_bob_time) * 0.06
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)
		head_bob_time = 0.0
		if camera:
			camera.position.y = move_toward(camera.position.y, 0.0, delta * 5.0)

	move_and_slide()
