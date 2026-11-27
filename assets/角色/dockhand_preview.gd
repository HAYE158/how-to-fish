extends Node3D

const Avatar := preload("res://assets/角色/dockhand.gd")
const VEST := preload("res://assets/角色/rain_vest.tscn")
const CAP := preload("res://assets/角色/dock_cap.tscn")
const PADDLE := preload("res://assets/角色/hand_paddle.tscn")
const SAVE_PATH := "user://dockhand_appearance.cfg"
const PANEL_WIDTH := 312.0
const TARGET := Vector3(0, 0.91, 0)

@onready var avatar: Avatar = $Avatar
@onready var camera: Camera3D = $Camera

var brush_color := Color("#387cba")
var brush_radius := 20.0
var _painting := false
var _yaw := 0.12
var _pitch := 0.15
var _head_sliders: Array[HSlider] = []
var _skin_picker: ColorPickerButton
var _status: Label


func _ready() -> void:
	_set_held(false)
	_build_controls()
	get_viewport().size_changed.connect(_update_camera)
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					avatar.begin_paint_stroke()
					_painting = true
					_paint_at(event.position)
				else:
					_end_stroke()
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					var direction := -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
					camera.size = clampf(camera.size + direction * 0.15, 1.55, 3.65)
					_update_camera()
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			_end_stroke()
			_yaw -= event.relative.x * 0.011
			_pitch = clampf(_pitch + event.relative.y * 0.009, -0.52, 0.75)
			_update_camera()
		elif _painting and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_paint_at(event.position)
		elif _painting:
			_end_stroke()


func _paint_at(screen_point: Vector2) -> void:
	avatar.paint_ray(camera.project_ray_origin(screen_point), camera.project_ray_normal(screen_point), brush_color, brush_radius)


func _end_stroke() -> void:
	if _painting:
		avatar.end_paint_stroke()
		_painting = false


func _update_camera() -> void:
	var heading := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), -cos(_yaw) * cos(_pitch))
	camera.global_position = TARGET + heading * 5.2
	camera.look_at(TARGET)
	var visible_height := maxf(1.0, get_viewport().get_visible_rect().size.y)
	camera.h_offset = camera.size * PANEL_WIDTH * 0.48 / visible_height


func _set_held(active: bool) -> void:
	_end_stroke()
	avatar.equip(Avatar.EquipmentSlot.RIGHT_HAND, PADDLE if active else null)
	avatar.play_action(&"hold" if active else &"paint_pose", 0.0)
	avatar.animations.seek(0.0, true)
	avatar.animations.pause()


func _build_controls() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -PANEL_WIDTH - 24.0
	panel.offset_right = -24.0
	panel.offset_top = 26.0
	panel.offset_bottom = -26.0
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#192a37")
	panel_style.set_corner_radius_all(15)
	panel_style.content_margin_left = 20
	panel_style.content_margin_right = 20
	panel_style.content_margin_top = 18
	panel_style.content_margin_bottom = 18
	panel.add_theme_stylebox_override(&"panel", panel_style)
	layer.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override(&"separation", 9)
	scroll.add_child(controls)

	_add_label(controls, "角色外观", 25)
	_add_label(controls, "左键涂色 · 右键旋转 · 滚轮缩放", 14, Color("#a9c5d0"))
	controls.add_child(HSeparator.new())

	_skin_picker = _add_color_picker(controls, "肤色底色", avatar.skin_color)
	_skin_picker.color_changed.connect(func(color: Color) -> void: avatar.skin_color = color)
	_add_color_picker(controls, "画笔颜色", brush_color).color_changed.connect(
		func(color: Color) -> void: brush_color = color
	)
	_add_slider(controls, "笔刷大小", 3.0, 55.0, brush_radius, 1.0).value_changed.connect(
		func(value: float) -> void: brush_radius = value
	)

	var reset := Button.new()
	reset.text = "清除笔迹"
	controls.add_child(reset)
	reset.pressed.connect(avatar.clear_paint)
	controls.add_child(HSeparator.new())

	_add_label(controls, "头型", 17)
	var axes := ["头宽", "头高", "头深"]
	for axis in range(3):
		var slider := _add_slider(controls, axes[axis], 0.75, 1.25, avatar.head_shape[axis], 0.01)
		_head_sliders.append(slider)
		slider.value_changed.connect(_set_head_axis.bind(axis))
	controls.add_child(HSeparator.new())

	_add_label(controls, "装备", 17)
	_add_toggle(controls, "雨背心").toggled.connect(
		func(active: bool) -> void: avatar.wear_outfit(VEST if active else null)
	)
	_add_toggle(controls, "码头帽").toggled.connect(
		func(active: bool) -> void: avatar.equip(Avatar.EquipmentSlot.HEAD, CAP if active else null)
	)
	_add_toggle(controls, "手持船桨").toggled.connect(_set_held)
	controls.add_child(HSeparator.new())

	var files := HBoxContainer.new()
	controls.add_child(files)
	var save_button := Button.new()
	save_button.text = "保存涂装与头型"
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	files.add_child(save_button)
	save_button.pressed.connect(_save)
	var load_button := Button.new()
	load_button.text = "读取"
	files.add_child(load_button)
	load_button.pressed.connect(_load)
	_status = _add_label(controls, "", 14, Color("#9dd6cd"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _set_head_axis(value: float, axis: int) -> void:
	_end_stroke()
	var shape := avatar.head_shape
	shape[axis] = value
	avatar.head_shape = shape


func _save() -> void:
	var result := avatar.save_appearance(SAVE_PATH)
	_status.text = "已保存到本机。" if result == OK else "保存失败。"


func _load() -> void:
	var result := avatar.load_appearance(SAVE_PATH)
	if result == OK:
		for axis in range(3):
			_head_sliders[axis].set_value_no_signal(avatar.head_shape[axis])
		_skin_picker.color = avatar.skin_color
	_status.text = "已读取涂装与头型。" if result == OK else "找不到可用的外观存档。"


func _add_label(parent: Container, text: String, size: int, tint: Color = Color("#e9f2f2")) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", tint)
	parent.add_child(label)
	return label


func _add_color_picker(parent: Container, title: String, initial: Color) -> ColorPickerButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_add_label(row, title, 16).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var picker := ColorPickerButton.new()
	picker.color = initial
	picker.edit_alpha = false
	picker.custom_minimum_size = Vector2(68, 30)
	row.add_child(picker)
	return picker


func _add_slider(parent: Container, title: String, low: float, high: float, initial: float, step: float) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	parent.add_child(row)
	var label := _add_label(row, title, 15)
	label.custom_minimum_size.x = 75
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	return slider


func _add_toggle(parent: Container, text: String) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = text
	parent.add_child(toggle)
	return toggle
