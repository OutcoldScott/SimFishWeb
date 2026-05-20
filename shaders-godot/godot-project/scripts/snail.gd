# Crawling snail. Slides slowly along a tank-glass wall.
#
# The snail picks a direction in the tangent plane of its wall and inches that
# way. Periodically it pauses or turns. It clamps to a rectangle on the wall
# so it can't slide off into geometry.

extends Node3D

@export var wall_normal: Vector3 = Vector3.RIGHT
@export var wall_min: Vector3 = Vector3(-7.6, 2.0, -3.6)
@export var wall_max: Vector3 = Vector3(7.6, 6.0, 3.6)
@export var is_baby: bool = false     # baby snails are 0.5x scale until they grow up

const SPEED: float = 0.18                  # units per second; ~3 minutes coast-to-coast
const TURN_INTERVAL_MIN: float = 6.0
const TURN_INTERVAL_MAX: float = 14.0
const PAUSE_CHANCE: float = 0.3            # when turning, sometimes just sit still

# Breeding: snails breed once they've been alive a while; lay egg sacs (small
# pale blobs) that hatch into a baby snail after some seconds. Population
# grows visibly over a few minutes of play.
const BREEDING_INTERVAL_MIN: float = 90.0
const BREEDING_INTERVAL_MAX: float = 180.0
const MATURITY_AGE: float = 60.0          # baby -> adult after a minute

var _direction: Vector2 = Vector2.RIGHT     # in wall-tangent space
var _t_until_turn: float = 0.0
var _paused: bool = false
var _age: float = 0.0
var _t_until_breed: float = 0.0


func _ready() -> void:
	_choose_new_direction()
	_t_until_breed = randf_range(BREEDING_INTERVAL_MIN, BREEDING_INTERVAL_MAX)
	if is_baby:
		scale = Vector3.ONE * 0.5


func _process(dt: float) -> void:
	_age += dt
	# Babies grow into adults over time.
	if is_baby and _age >= MATURITY_AGE:
		is_baby = false
		# Animate the scale change.
	if is_baby:
		var growth: float = clampf(_age / MATURITY_AGE, 0.5, 1.0)
		scale = Vector3.ONE * (0.5 + 0.5 * growth)

	_t_until_turn -= dt
	if _t_until_turn <= 0.0:
		_choose_new_direction()

	# Breeding: lay an egg sac once the timer expires. Only adults breed.
	if not is_baby:
		_t_until_breed -= dt
		if _t_until_breed <= 0.0:
			_lay_egg_sac()
			_t_until_breed = randf_range(BREEDING_INTERVAL_MIN, BREEDING_INTERVAL_MAX)

	if _paused:
		return

	# Build tangent vectors for this wall.
	var up := Vector3.UP
	var tangent: Vector3
	if absf(wall_normal.dot(up)) > 0.95:
		# Top/bottom walls - unlikely but handle.
		tangent = Vector3.RIGHT
	else:
		tangent = wall_normal.cross(up).normalized()
	var delta: Vector3 = tangent * _direction.x + up * _direction.y
	position += delta * SPEED * dt
	# Clamp to wall rectangle.
	position.x = clampf(position.x, wall_min.x, wall_max.x)
	position.y = clampf(position.y, wall_min.y, wall_max.y)
	position.z = clampf(position.z, wall_min.z, wall_max.z)


func _lay_egg_sac() -> void:
	# Spawn an egg sac at our current location. After a delay it hatches
	# into a new baby snail on the same wall. The sac is just a small
	# pale-yellow voxel cluster that uses the SnailEgg script.
	var sac := Node3D.new()
	sac.set_script(load("res://scripts/snail_egg.gd"))
	get_parent().add_child(sac)
	sac.position = position + wall_normal * 0.04
	sac.set("wall_normal", wall_normal)
	sac.set("wall_min", wall_min)
	sac.set("wall_max", wall_max)


func _choose_new_direction() -> void:
	_t_until_turn = randf_range(TURN_INTERVAL_MIN, TURN_INTERVAL_MAX)
	_paused = randf() < PAUSE_CHANCE
	if _paused:
		return
	var ang := randf() * TAU
	_direction = Vector2(cos(ang), sin(ang))
