extends Node

## 测试场地专用：
## 1. 地形没有碰撞时补一个 trimesh（编辑器里已经加过就跳过）
## 2. 用向下射线把玩家吸附到地表，避免出生点高度被父节点 5 倍缩放坑到

@export var terrain_path: NodePath = ^"../IslandAndSeabed/CoastalTerrain"
@export var player_path: NodePath = ^"../Player"


func _ready() -> void:
	var terrain := get_node_or_null(terrain_path) as MeshInstance3D
	if terrain == null:
		push_warning("LevelSetup: 找不到地形节点 %s" % terrain_path)
		return

	var has_collision := false
	for child in terrain.get_children():
		if child is StaticBody3D:
			has_collision = true
			break

	if not has_collision:
		if terrain.mesh == null:
			push_warning("LevelSetup: 地形没有网格，无法生成碰撞。")
			return
		terrain.create_trimesh_collision()

	_drop_player_on_ground()


func _drop_player_on_ground() -> void:
	await get_tree().physics_frame
	var player := get_node_or_null(player_path) as CharacterBody3D
	if player == null:
		return
	var space := player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		player.global_position + Vector3.UP * 40.0,
		player.global_position + Vector3.DOWN * 80.0
	)
	query.exclude = [player.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		push_warning("LevelSetup: 玩家下方没有地面，出生点可能需要调整。")
		return
	player.global_position = (hit["position"] as Vector3) + Vector3.UP * 0.2
	player.velocity = Vector3.ZERO
