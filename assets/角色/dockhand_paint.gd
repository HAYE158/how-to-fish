extends RefCounted

const SIZE := 768
const TILE := Vector2i(256, 384)
const PADDING := Vector2i(10, 10)

var texture: ImageTexture

var _image: Image
var _target: MeshInstance3D
var _skeleton: Skeleton3D
var _vertices: PackedVector3Array
var _uvs: PackedVector2Array
var _indices: PackedInt32Array
var _bones: PackedInt32Array
var _weights: PackedFloat32Array
var _posed: PackedVector3Array
var _last_uv := Vector2.ZERO
var _last_tile := Vector2i(-1, -1)


func _init(target: MeshInstance3D, skeleton: Skeleton3D) -> void:
	_target = target
	_skeleton = skeleton
	var arrays := target.mesh.surface_get_arrays(0)
	_vertices = arrays[Mesh.ARRAY_VERTEX]
	_uvs = arrays[Mesh.ARRAY_TEX_UV]
	_indices = arrays[Mesh.ARRAY_INDEX]
	_bones = arrays[Mesh.ARRAY_BONES]
	_weights = arrays[Mesh.ARRAY_WEIGHTS]
	_image = Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	_image.fill(Color.TRANSPARENT)
	texture = ImageTexture.create_from_image(_image)


static func atlas_uv(piece: int, uv: Vector2) -> Vector2:
	var tile := Vector2i(posmod(piece, 3), floori(float(piece) / 3.0))
	var span := TILE - PADDING * 2 - Vector2i.ONE
	return (Vector2(tile * TILE + PADDING) + uv * Vector2(span) + Vector2(0.5, 0.5)) / SIZE


func begin() -> void:
	var skin := _target.skin
	_skeleton.force_update_all_bone_transforms()
	var transforms: Array[Transform3D] = []
	for bind in range(skin.get_bind_count()):
		var bone := _skeleton.find_bone(skin.get_bind_name(bind))
		transforms.append(_skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(bind))

	_posed.resize(_vertices.size())
	for vertex in range(_vertices.size()):
		var position := Vector3.ZERO
		for i in range(4):
			var k := vertex * 4 + i
			if _weights[k] > 0.0:
				position += (transforms[_bones[k]] * _vertices[vertex]) * _weights[k]
		_posed[vertex] = position
	_last_tile = Vector2i(-1, -1)


func end() -> void:
	_posed.clear()
	_last_tile = Vector2i(-1, -1)


func clear() -> void:
	_image.fill(Color.TRANSPARENT)
	texture.update(_image)


func get_image() -> Image:
	return _image.duplicate()


func set_image(image: Image) -> bool:
	if image == null or image.get_width() != SIZE or image.get_height() != SIZE:
		return false
	_image = image.duplicate()
	_image.convert(Image.FORMAT_RGBA8)
	_image.clear_mipmaps()
	texture.update(_image)
	return true


func paint_ray(origin: Vector3, direction: Vector3, color: Color, radius: float) -> bool:
	if _posed.is_empty():
		return false
	var inverse := _target.global_transform.affine_inverse()
	var hit := _pick_uv(inverse * origin, (inverse.basis * direction).normalized())
	if hit.is_empty():
		_last_tile = Vector2i(-1, -1)
		return false

	var pixel: Vector2 = hit[0] * SIZE - Vector2(0.5, 0.5)
	var tile := Vector2i(floori(pixel.x / TILE.x), floori(pixel.y / TILE.y))
	var rect := Rect2i(tile * TILE + PADDING, TILE - PADDING * 2)
	var world_radius := clampf(radius, 3.0, 55.0) * 0.0035
	var texel_size: Vector2 = hit[1]
	var radii := (Vector2.ONE * world_radius / texel_size).clamp(Vector2.ONE * 2.0, Vector2.ONE * 78.0)
	var from := pixel
	if tile == _last_tile:
		from = _last_uv
		var difference := pixel.x - from.x
		if absf(difference) > rect.size.x * 0.5:
			from.x += signf(difference) * rect.size.x
		# Avoid painting through a distant UV point when two surfaces overlap.
		if from.distance_to(pixel) > 110.0:
			from = pixel
	var steps := maxi(1, ceili(((pixel - from) / radii).length() / 0.42))
	for step in range(1, steps + 1):
		_stamp(from.lerp(pixel, float(step) / steps), rect, color, radii)
	_last_uv = pixel
	_last_tile = tile
	texture.update(_image)
	return true


func _pick_uv(origin: Vector3, direction: Vector3) -> Array[Vector2]:
	var nearest := INF
	var closest := -1
	var point := Vector3.ZERO
	for tri in range(0, _indices.size(), 3):
		var ai := _indices[tri]
		var bi := _indices[tri + 1]
		var ci := _indices[tri + 2]
		var a := _posed[ai]
		var b := _posed[bi]
		var c := _posed[ci]
		var result: Variant = Geometry3D.ray_intersects_triangle(origin, direction, a, b, c)
		if result == null:
			continue
		var distance := origin.distance_squared_to(result)
		if distance >= nearest:
			continue
		nearest = distance
		closest = tri
		point = result
	if closest < 0:
		return []

	var ai := _indices[closest]
	var bi := _indices[closest + 1]
	var ci := _indices[closest + 2]
	var edge_a := _posed[bi] - _posed[ai]
	var edge_b := _posed[ci] - _posed[ai]
	var barycentric := Geometry3D.get_triangle_barycentric_coords(point, _posed[ai], _posed[bi], _posed[ci])
	var uv := _uvs[ai] * barycentric.x + _uvs[bi] * barycentric.y + _uvs[ci] * barycentric.z
	var uva := _uvs[bi] - _uvs[ai]
	var uvb := _uvs[ci] - _uvs[ai]
	var area := absf(uva.cross(uvb))
	var texel := Vector2.ONE * 0.0035
	if area > 0.0000001:
		texel.x = (edge_a * uvb.y - edge_b * uva.y).length() / (area * SIZE)
		texel.y = (edge_b * uva.x - edge_a * uvb.x).length() / (area * SIZE)
	return [uv, texel.max(Vector2.ONE * 0.0001)]


func _stamp(center: Vector2, rect: Rect2i, color: Color, radii: Vector2) -> void:
	for y in range(maxi(rect.position.y, floori(center.y - radii.y)), mini(rect.end.y, ceili(center.y + radii.y + 1.0))):
		for x in range(floori(center.x - radii.x), ceili(center.x + radii.x + 1.0)):
			var distance := ((Vector2(x, y) - center) / radii).length()
			if distance >= 1.0:
				continue
			var wrapped_x := rect.position.x + posmod(x - rect.position.x, rect.size.x)
			var ink := color
			ink.a *= 1.0 - smoothstep(0.65, 1.0, distance)
			_image.set_pixel(wrapped_x, y, _image.get_pixel(wrapped_x, y).blend(ink))
