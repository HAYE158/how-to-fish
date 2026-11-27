extends Node3D

const Avatar := preload("res://assets/角色/dockhand.gd")
const Knife := preload("res://assets/道具/hand_knife.gd")
const ITEMS := [
	"res://assets/道具/folding_knife.tscn",
	"res://assets/道具/butterfly_knife.tscn",
	"res://assets/道具/field_knife.tscn",
]
const MOTIONS := "res://assets/道具/knife_moves.tres"
const CAP := preload("res://assets/角色/dock_cap.tscn")
const VEST := preload("res://assets/角色/rain_vest.tscn")

@onready var avatar: Avatar = $Avatar
@onready var display: Array[Knife] = [$FoldingDisplay, $ButterflyDisplay, $FieldDisplay]

var _held: Knife
var _selection := 0
var _cutting := false
var _choice: OptionButton
var _toggle: Button
var _cut: Button
var _status: Label


func _ready() -> void:
	avatar.wear_outfit(VEST)
	avatar.equip(Avatar.EquipmentSlot.HEAD, CAP)
	avatar.animations.add_animation_library(&"knife", load(MOTIONS))
	avatar.animations.animation_finished.connect(_motion_finished)
	_build_controls()
	_select(0)
	for model in display:
		model.blade_state_changed.connect(_update_controls)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1: _select(0)
		KEY_2: _select(1)
		KEY_3: _select(2)
		KEY_E: _toggle_blade()
		KEY_SPACE: _try_cut()


func _select(index: int) -> void:
	if _cutting or (_held != null and _held.is_moving()) or display[index].is_moving():
		_choice.select(_selection)
		return
	var item: PackedScene = load(ITEMS[index])
	if not avatar.equip(Avatar.EquipmentSlot.RIGHT_HAND, item):
		return
	_selection = index
	_choice.select(index)
	var socket := avatar.get_node(Avatar.SOCKETS[Avatar.EquipmentSlot.RIGHT_HAND])
	_held = socket.get_child(0)
	_held.set_blade_open(display[index].blade_is_open(), false)
	_held.blade_state_changed.connect(_update_controls)
	avatar.play_action(&"knife/ready", 0.0)
	_update_controls()


func _toggle_blade() -> void:
	if _held == null or _held.fixed_blade or _cutting or _held.is_moving() or display[_selection].is_moving():
		return
	var open := not _held.blade_is_open()
	display[_selection].set_blade_open(open)
	_held.set_blade_open(open)


func _try_cut() -> void:
	if _held == null or _cutting or not _held.blade_is_open() or display[_selection].is_moving():
		return
	_cutting = avatar.play_action(&"knife/cut", 0.0)
	_update_controls()


func _motion_finished(clip: StringName) -> void:
	if clip == &"knife/cut":
		_cutting = false
		avatar.play_action(&"knife/ready", 0.0)
		_update_controls()


func _update_controls() -> void:
	var is_open := _held.blade_is_open()
	var busy := _held.is_moving() or display[_selection].is_moving()
	_choice.disabled = _cutting or busy
	_toggle.disabled = _held.fixed_blade or _cutting or busy
	_cut.disabled = _cutting or busy or not is_open
	_toggle.text = "固定刀片" if _held.fixed_blade else ("收起 · E" if is_open else "展开 · E")
	if _cutting:
		_status.text = "切削"
	elif busy:
		_status.text = "刀片移动中"
	else:
		_status.text = "刀片已展开" if is_open else "刀片已收起"


func _build_controls() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -296.0
	panel.offset_right = 296.0
	panel.offset_top = -84.0
	panel.offset_bottom = -24.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1b2b37")
	style.set_corner_radius_all(13)
	style.content_margin_left = 14
	style.content_margin_top = 10
	style.content_margin_right = 14
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override(&"panel", style)
	canvas.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	panel.add_child(row)
	_choice = OptionButton.new()
	_choice.add_item("折刀 · 1")
	_choice.add_item("蝴蝶刀 · 2")
	_choice.add_item("军刀 · 3")
	_choice.custom_minimum_size.x = 133
	_choice.focus_mode = Control.FOCUS_NONE
	_choice.item_selected.connect(_select)
	row.add_child(_choice)

	_toggle = Button.new()
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.custom_minimum_size.x = 102
	_toggle.pressed.connect(_toggle_blade)
	row.add_child(_toggle)
	_cut = Button.new()
	_cut.text = "试切 · 空格"
	_cut.focus_mode = Control.FOCUS_NONE
	_cut.custom_minimum_size.x = 114
	_cut.pressed.connect(_try_cut)
	row.add_child(_cut)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.add_theme_color_override(&"font_color", Color("#a9d1d3"))
	row.add_child(_status)
