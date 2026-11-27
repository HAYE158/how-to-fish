extends Node3D

signal blade_state_changed

@export var starts_open := true
@export var fixed_blade := false

@onready var animations: AnimationPlayer = $AnimationPlayer
@onready var edge_start: Marker3D = $BladePivot/EdgeStart
@onready var edge_tip: Marker3D = $BladePivot/EdgeTip

var _open := false


func _ready() -> void:
	if fixed_blade:
		_open = true
		return
	animations.animation_finished.connect(_on_finished)
	set_blade_open(starts_open, false)


func blade_is_open() -> bool:
	return _open and not animations.is_playing()


func is_moving() -> bool:
	return animations.is_playing()


func toggle_blade() -> bool:
	return set_blade_open(not _open)


func set_blade_open(open: bool, animated: bool = true) -> bool:
	if fixed_blade:
		return open
	if animated and is_moving():
		return false
	if animated and open == _open:
		return true
	_open = open
	var clip := animations.get_animation(&"deploy")
	if animated:
		animations.play(&"deploy", 0.0, 1.0 if open else -1.0, not open)
		animations.seek(0.0 if open else clip.length, true)
	else:
		animations.play(&"deploy", 0.0)
		animations.seek(clip.length if open else 0.0, true)
		animations.pause()
	blade_state_changed.emit()
	return true


func _on_finished(_clip: StringName) -> void:
	blade_state_changed.emit()
