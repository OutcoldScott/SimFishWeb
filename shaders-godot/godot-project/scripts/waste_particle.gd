# Fish waste / detritus particle. Falls due to gravity, deposits its nutrient
# value into the SubstrateGrid when it reaches the substrate top, then queues
# itself for removal. Lives ~30 sim seconds max so the scene doesn't fill up.

extends Node3D
class_name WasteParticle

const VOXEL_SIZE: float = 0.12
const FALL_SPEED: float = 0.6
const MAX_LIFE: float = 30.0

var nutrient_value: float = 0.2
var substrate_top_y: float = 1.6
var _life: float = 0.0
var _settled: bool = false
var _settle_timer: float = 0.0


func init(value: float, top_y: float) -> void:
	nutrient_value = value
	substrate_top_y = top_y
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE)
	mi.mesh = bm
	mi.material_override = VoxelMat.make(Color8(60, 45, 30))
	add_child(mi)


func tick(dt: float, substrate: SubstrateGrid) -> bool:
	# Returns true if the particle should be removed this tick.
	_life += dt
	if _life >= MAX_LIFE:
		return true
	if not _settled:
		position.y -= FALL_SPEED * dt
		# Gentle horizontal drift so they spread.
		position.x += sin(_life * 1.7) * 0.04 * dt
		if position.y <= substrate_top_y + VOXEL_SIZE * 0.5:
			position.y = substrate_top_y + VOXEL_SIZE * 0.5
			_settled = true
			substrate.add_at(position, nutrient_value)
	else:
		_settle_timer += dt
		if _settle_timer > 4.0:
			return true
	return false
