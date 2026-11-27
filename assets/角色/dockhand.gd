@tool
class_name DockhandAvatar
extends Node3D

enum EquipmentSlot { RIGHT_HAND, LEFT_HAND, HEAD, BACK }

const Paint := preload("res://assets/角色/dockhand_paint.gd")
const HEAD_MIN := Vector3(0.75, 0.75, 0.75)
const HEAD_MAX := Vector3(1.25, 1.25, 1.25)
const SOCKETS := {
	EquipmentSlot.RIGHT_HAND: ^"Skeleton/RightHandAttachment/Socket",
	EquipmentSlot.LEFT_HAND: ^"Skeleton/LeftHandAttachment/Socket",
	EquipmentSlot.HEAD: ^"Skeleton/HeadwearAttachment/Socket",
	EquipmentSlot.BACK: ^"Skeleton/BackAttachment/Socket",
}

@export_group("Appearance")
@export var skin_color: Color = Color("#f7f7f7"):
	set(value):
		skin_color = value
		if _skin_material != null:
			_skin_material.set_shader_parameter("skin_color", value)
@export var outfit_color: Color = Color("#287e7c"):
	set(value):
		outfit_color = value
		_refresh_palette()
@export_range(0.85, 1.15, 0.01) var head_scale: float = 1.0:
	set(value):
		head_scale = value
		if is_node_ready():
			_apply_head_scale()
@export var head_shape := Vector3.ONE:
	set(value):
		head_shape = value.clamp(HEAD_MIN, HEAD_MAX)
		if is_node_ready():
			_apply_head_scale()

@export_group("Starting equipment")
@export var starting_outfit: PackedScene:
	set(value):
		starting_outfit = value
		if is_node_ready():
			wear_outfit(value)
@export var starting_right_hand: PackedScene:
	set(value):
		starting_right_hand = value
		if is_node_ready():
			equip(EquipmentSlot.RIGHT_HAND, value)
@export var starting_left_hand: PackedScene:
	set(value):
		starting_left_hand = value
		if is_node_ready():
			equip(EquipmentSlot.LEFT_HAND, value)
@export var starting_headwear: PackedScene:
	set(value):
		starting_headwear = value
		if is_node_ready():
			equip(EquipmentSlot.HEAD, value)
@export var starting_backwear: PackedScene:
	set(value):
		starting_backwear = value
		if is_node_ready():
			equip(EquipmentSlot.BACK, value)

@onready var skeleton: Skeleton3D = $Skeleton
@onready var animations: AnimationPlayer = $AnimationPlayer
@onready var wardrobe: Node3D = $Wardrobe
@onready var body: MeshInstance3D = $PaintableBody

var _active_outfit: Node3D
var _equipped: Dictionary[EquipmentSlot, Node3D] = {}
var _skin_material: ShaderMaterial
var _painter: Paint


func _ready() -> void:
	_skin_material = body.material_override.duplicate()
	body.material_override = _skin_material
	_skin_material.set_shader_parameter("skin_color", skin_color)
	wear_outfit(starting_outfit)
	equip(EquipmentSlot.RIGHT_HAND, starting_right_hand)
	equip(EquipmentSlot.LEFT_HAND, starting_left_hand)
	equip(EquipmentSlot.HEAD, starting_headwear)
	equip(EquipmentSlot.BACK, starting_backwear)
	_refresh_palette()
	_apply_head_scale()


func play_action(action: StringName, blend: float = 0.14) -> bool:
	if not animations.has_animation(action):
		return false
	animations.play(action, blend)
	return true


## Sample the current pose once per stroke. Keep it steady while painting.
func begin_paint_stroke() -> void:
	_get_painter().begin()


func paint_ray(origin: Vector3, direction: Vector3, color: Color, radius: float) -> bool:
	return _painter != null and _painter.paint_ray(origin, direction, color, radius)


func end_paint_stroke() -> void:
	if _painter != null:
		_painter.end()


func clear_paint() -> void:
	if _painter != null:
		_painter.clear()


func save_appearance(path: String) -> Error:
	var file := ConfigFile.new()
	file.set_value("appearance", "skin", skin_color)
	file.set_value("appearance", "outfit_color", outfit_color)
	file.set_value("appearance", "head", head_shape)
	file.set_value("appearance", "head_scale", head_scale)
	if _painter != null:
		file.set_value("appearance", "paint", _painter.get_image().save_png_to_buffer())
	return file.save(path)


func load_appearance(path: String) -> Error:
	var file := ConfigFile.new()
	var result := file.load(path)
	if result != OK:
		return result
	var ink: Variant = file.get_value("appearance", "paint", PackedByteArray())
	var tint: Variant = file.get_value("appearance", "skin", Color("#f7f7f7"))
	var outfit_tint: Variant = file.get_value("appearance", "outfit_color", Color("#287e7c"))
	var shape: Variant = file.get_value("appearance", "head", Vector3.ONE)
	var size: Variant = file.get_value("appearance", "head_scale", 1.0)
	if not (ink is PackedByteArray and tint is Color and outfit_tint is Color and shape is Vector3 and size is float):
		return ERR_INVALID_DATA
	if not ink.is_empty():
		var image := Image.new()
		if image.load_png_from_buffer(ink) != OK or not _get_painter().set_image(image):
			return ERR_INVALID_DATA
	else:
		clear_paint()
	skin_color = tint
	outfit_color = outfit_tint
	head_shape = shape
	head_scale = clampf(size, 0.85, 1.15)
	return OK


func _get_painter() -> Paint:
	if _painter == null:
		_painter = Paint.new(body, skeleton)
		_skin_material.set_shader_parameter("skin_paint", _painter.texture)
	return _painter


## The item's origin is its grip or attachment point. Pass null to clear the slot.
func equip(slot: EquipmentSlot, item: PackedScene) -> bool:
	var socket: Node3D = get_node_or_null(SOCKETS.get(slot, NodePath()))
	if socket == null:
		return false
	var next: Node3D
	if item != null:
		next = _instantiate_3d(item)
		if next == null:
			return false
	var previous: Node3D = _equipped.get(slot)
	if is_instance_valid(previous):
		socket.remove_child(previous)
		previous.queue_free()
	_equipped.erase(slot)
	if next != null:
		socket.add_child(next)
		_equipped[slot] = next
	return true


## Apparel is authored in the character's rest pose with named skin binds.
## Pass null to remove the current outfit.
func wear_outfit(outfit: PackedScene) -> bool:
	var next: Node3D
	var weighted_meshes: Array[MeshInstance3D] = []
	if outfit != null:
		next = _instantiate_3d(outfit)
		if next == null:
			return false
		if next is MeshInstance3D and next.skin != null:
			weighted_meshes.append(next)
		for mesh: MeshInstance3D in next.find_children("*", "MeshInstance3D", true, false):
			if mesh.skin != null:
				weighted_meshes.append(mesh)
		if weighted_meshes.is_empty():
			next.free()
			return false
		for mesh in weighted_meshes:
			for bind in range(mesh.skin.get_bind_count()):
				if skeleton.find_bone(mesh.skin.get_bind_name(bind)) == -1:
					next.free()
					return false

	if is_instance_valid(_active_outfit):
		wardrobe.remove_child(_active_outfit)
		_active_outfit.queue_free()
	_active_outfit = next
	if next != null:
		# Mesh paths are assigned after both nodes share a parent hierarchy.
		wardrobe.add_child(next)
		for mesh in weighted_meshes:
			mesh.skeleton = mesh.get_path_to(skeleton)
		_refresh_palette()
	return true


func _instantiate_3d(scene: PackedScene) -> Node3D:
	var instance := scene.instantiate()
	if instance is Node3D:
		return instance
	if instance != null:
		instance.free()
	return null


func _apply_head_scale() -> void:
	skeleton.set_bone_pose_scale(skeleton.find_bone("head"), head_shape * head_scale)


func _refresh_palette() -> void:
	if not is_node_ready():
		return
	for mesh: MeshInstance3D in wardrobe.find_children("*", "MeshInstance3D", true, false):
		if mesh.get_meta(&"avatar_color", &"") != &"outfit" or not mesh.material_override is StandardMaterial3D:
			continue
		var material := mesh.material_override as StandardMaterial3D
		if material.get_meta(&"avatar_owner", 0) != get_instance_id():
			material = material.duplicate()
			material.set_meta(&"avatar_owner", get_instance_id())
			mesh.material_override = material
		material.albedo_color = outfit_color
