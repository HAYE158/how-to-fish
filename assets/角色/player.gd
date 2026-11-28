class_name Player
extends CharacterBody3D

## 徒步玩家控制器。一套相机骨架同时驱动两种视角：
## - 第一人称：弹簧臂长度归零，head 骨骼缩放到 0.001（只藏头，身体和手还看得见）
## - 第三人称：弹簧臂拉长并自动避让地形，角色整体可见，身体朝移动方向转
## 移动方向始终相对相机水平朝向，所以两种视角手感一致。

signal view_changed(first_person: bool)

const HEAD_BONE_NAME := &"head"
const HEAD_HIDDEN_SCALE := Vector3.ONE * 0.001

@export_group("移动")
@export var walk_speed: float = 2.6
@export var sprint_speed: float = 5.2
@export var acceleration: float = 14.0
@export var jump_velocity: float = 4.6

@export_group("视角")
@export var first_person: bool = true
@export_range(0.0005, 0.01, 0.0001) var mouse_sensitivity: float = 0.0022
@export_range(-89.0, -1.0, 1.0) var pitch_min_degrees: float = -85.0
@export_range(1.0, 89.0, 1.0) var pitch_max_degrees: float = 85.0
@export var eye_height: float = 1.58
@export var third_person_distance: float = 3.2

@export_group("角色模型")
## 第三人称下如果角色是背对前进方向，把这个改成 180。
@export_range(-180.0, 180.0, 1.0) var avatar_yaw_offset: float = 0.0

@onready var avatar: DockhandAvatar = $Avatar
@onready var camera_rig: Node3D = $CameraRig
@onready var pitch_pivot: Node3D = $CameraRig/PitchPivot
@onready var spring_arm: SpringArm3D = $CameraRig/PitchPivot/SpringArm3D
@onready var camera: Camera3D = $CameraRig/PitchPivot/SpringArm3D/Camera3D

var _gravity: float = 9.8
var _head_bone: int = -1
var _playing_action: StringName = &""


func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	_head_bone = avatar.skeleton.find_bone(HEAD_BONE_NAME)
	if _head_bone == -1:
		push_warning("Player: 骨架里找不到 head 骨骼，第一人称无法隐藏头部。")
	camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	apply_view_mode()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var motion := event as InputEventMouseMotion
			camera_rig.rotate_y(-motion.relative.x * mouse_sensitivity)
			var pitch := pitch_pivot.rotation.x - motion.relative.y * mouse_sensitivity
			pitch_pivot.rotation.x = clampf(
				pitch,
				deg_to_rad(pitch_min_degrees),
				deg_to_rad(pitch_max_degrees)
			)
		return

	if event.is_action_pressed(&"toggle_view"):
		first_person = not first_person
		apply_view_mode()
		return

	if event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	if Input.is_action_just_pressed(&"jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_dir := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var yaw_basis := camera_rig.global_transform.basis
	var direction := yaw_basis.x * input_dir.x + yaw_basis.z * input_dir.y
	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		direction = direction.normalized()

	var speed := sprint_speed if Input.is_action_pressed(&"sprint") else walk_speed
	var blend := clampf(acceleration * delta, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, direction.x * speed, blend)
	velocity.z = lerpf(velocity.z, direction.z * speed, blend)

	move_and_slide()

	var planar_speed := Vector2(velocity.x, velocity.z).length()
	_update_locomotion_animation(planar_speed)
	_update_avatar_facing(direction, delta)


## 切换第一人称/第三人称。外部也可以直接改 first_person 再调用这个。
func apply_view_mode() -> void:
	spring_arm.spring_length = 0.0 if first_person else third_person_distance
	spring_arm.position = Vector3.ZERO
	camera_rig.position.y = eye_height
	_set_head_hidden(first_person)
	view_changed.emit(first_person)


func _set_head_hidden(hidden: bool) -> void:
	if _head_bone == -1:
		return
	if hidden:
		avatar.skeleton.set_bone_pose_scale(_head_bone, HEAD_HIDDEN_SCALE)
	else:
		avatar.skeleton.set_bone_pose_scale(_head_bone, avatar.head_shape * avatar.head_scale)


func _update_locomotion_animation(planar_speed: float) -> void:
	var target: StringName = &"walk" if planar_speed > 0.15 else &"idle"
	if target != _playing_action:
		if not avatar.play_action(target):
			return
		_playing_action = target
	avatar.animations.speed_scale = 1.0
	if target == &"walk":
		avatar.animations.speed_scale = clampf(planar_speed / walk_speed, 0.6, 1.8)


func _update_avatar_facing(direction: Vector3, delta: float) -> void:
	var target_yaw: float
	if first_person:
		target_yaw = camera_rig.rotation.y
	elif direction.length_squared() > 0.0001:
		target_yaw = atan2(direction.x, direction.z) + deg_to_rad(avatar_yaw_offset)
	else:
		return
	avatar.rotation.y = lerp_angle(avatar.rotation.y, target_yaw, clampf(delta * 25.0, 0.0, 1.0))
