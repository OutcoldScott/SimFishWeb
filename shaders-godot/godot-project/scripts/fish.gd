# A fish agent.
#
# Holds genome + state, builds its own voxel body, runs a small behavior tree
# every sim tick. Behaviors (in priority order):
#   1. Flee tank wall if too close
#   2. Breed if adult, healthy, near a conspecific of opposite sex with low hunger
#   3. Eat if hungry (herbivores seek plants; carnivores skipped here)
#   4. School: cohesion + alignment + separation with conspecifics
#   5. Wander
#
# Lifecycle: fry -> juvenile -> adult -> senescent -> dies (queue_free).
# Dying decomposes into a waste particle (so the loop closes nutrient-wise).

extends Node3D
class_name Fish

const MATURITY_FRY := 0
const MATURITY_JUVENILE := 1
const MATURITY_ADULT := 2
const MATURITY_SENESCENT := 3

# Behavior modes - what the fish is doing right now. Visible in the HUD if we
# add per-fish debug labels.
enum Mode { CRUISE, FORAGE, COURT, SPAWN, FLEE, REST }

# ---- Genome (set at spawn, immutable for this individual) ----
var species: String = "glassdart"
var base_color: Color = Color8(195, 59, 59)
var accent_color: Color = Color8(230, 201, 42)
var adult_voxel_scale: float = 0.18
var max_age_s: float = 240.0            # ~4 minutes lifespan for visible cycles
var max_speed: float = 1.8
var schooling_strength: float = 1.0
var separation_radius: float = 0.55
var herbivory: float = 0.0              # >0 means eats plants
var fecundity: float = 0.7
var clutch_size: int = 2
var preferred_y: float = 3.5            # mid-water by default
var sex: int = 0                        # 0 male, 1 female

# ---- State (mutable) ----
var age: float = 0.0
var hunger: float = 0.3        # 0 = full, 1 = starving
var energy: float = 1.0
var stress: float = 0.0
var maturity: int = MATURITY_FRY
var velocity: Vector3 = Vector3.ZERO
var breed_cooldown: float = 0.0
var nibble_cooldown: float = 0.0
var target_plant: Plant = null
var heading_offset: Vector3 = Vector3.ZERO  # personal randomness in schooling
var current_mode: Mode = Mode.CRUISE

# Courtship state machine:
#   partner: who we're trying to spawn with (or null)
#   court_timer: time spent courting (need to reach threshold to spawn)
#   pair_bond_timer: shared time post-spawn before the bond dissolves
var partner: Fish = null
var court_timer: float = 0.0
const COURT_DURATION: float = 6.0  # sim seconds of swimming together before spawn

# Burst mode: when fleeing or chasing food, fish can momentarily exceed
# max_speed by burst_multiplier. Drains energy faster.
var burst_remaining: float = 0.0

# Velocity has two parts: target (set by tick at 10Hz) and current (smoothed
# at render rate in _process). This keeps motion smooth even though the
# brain ticks slowly.
var target_velocity: Vector3 = Vector3.ZERO

# Animation - parts of the body that wag during swimming.
var _tail_pivot: Node3D = null      # rotates Y to wag the tail fin
var _body_mid_pivot: Node3D = null  # mild lateral undulation of mid-body
var _swim_phase: float = 0.0

# ---- Refs ----
var sim: Node = null


func _ready() -> void:
	heading_offset = Vector3(
		randf_range(-0.5, 0.5),
		randf_range(-0.2, 0.2),
		randf_range(-0.5, 0.5),
	)
	_swim_phase = randf() * TAU


# ---- Setup ----

func init_genome(genome: Dictionary) -> void:
	species = genome.get("species", species)
	base_color = genome.get("base_color", base_color)
	accent_color = genome.get("accent_color", accent_color)
	adult_voxel_scale = genome.get("adult_voxel_scale", adult_voxel_scale)
	max_age_s = genome.get("max_age_s", max_age_s)
	max_speed = genome.get("max_speed", max_speed)
	schooling_strength = genome.get("schooling_strength", schooling_strength)
	separation_radius = genome.get("separation_radius", separation_radius)
	herbivory = genome.get("herbivory", herbivory)
	fecundity = genome.get("fecundity", fecundity)
	clutch_size = genome.get("clutch_size", clutch_size)
	preferred_y = genome.get("preferred_y", preferred_y)
	sex = genome.get("sex", randi() % 2)
	# A fry is born tiny - we'll lerp scale as it matures.
	scale = Vector3.ONE * _maturity_scale()
	_build_body()


func _maturity_scale() -> float:
	match maturity:
		MATURITY_FRY:        return 0.35
		MATURITY_JUVENILE:   return 0.65
		MATURITY_ADULT:      return 1.0
		MATURITY_SENESCENT:  return 0.95
		_: return 1.0


func _build_body() -> void:
	# Voxel fish facing +X. Layout:
	#   - Head:        rigid, contains eye
	#   - BodyMid:     pivot rotates Y mildly for undulation
	#   - TailPivot:   pivot at the tail base, wags Y strongly for the swim
	#   - DorsalFin:   small block on top
	#   - AnalFin:     small block on bottom
	#
	# Body widths sample a teardrop profile - thicker just behind the head,
	# tapering to the tail. Each segment is built from a few voxels of slightly
	# different shades so the fish has visible depth.
	var v: float = adult_voxel_scale
	var mat_body := _make_mat(base_color)
	var mat_top := _make_mat(base_color.lightened(0.15))
	var mat_belly := _make_mat(base_color.darkened(0.35))
	var mat_accent := _make_mat(accent_color)
	var mat_eye := _make_mat(Color8(11, 26, 34))
	var mat_fin := _make_mat(base_color.darkened(0.15))

	# ---- HEAD (rigid, sits at x = -3v..-2v) ----
	var head := Node3D.new()
	head.name = "Head"
	add_child(head)
	_add_voxel_to(head, Vector3(-2.5 * v, 0, 0), Vector3(v, v * 0.9, v * 0.95), mat_body)
	# Forehead/top - lighter (catches more light).
	_add_voxel_to(head, Vector3(-2.5 * v, v * 0.5, 0), Vector3(v, v * 0.3, v * 0.6), mat_top)
	# Belly under head.
	_add_voxel_to(head, Vector3(-2.5 * v, -v * 0.5, 0), Vector3(v, v * 0.3, v * 0.6), mat_belly)
	# Eye - one small dark block on each side.
	_add_voxel_to(head, Vector3(-2.4 * v, v * 0.1, v * 0.4),
		Vector3(v * 0.25, v * 0.25, v * 0.2), mat_eye)
	_add_voxel_to(head, Vector3(-2.4 * v, v * 0.1, -v * 0.4),
		Vector3(v * 0.25, v * 0.25, v * 0.2), mat_eye)

	# ---- BODY MID (slight wag) - the thickest part of the fish ----
	_body_mid_pivot = Node3D.new()
	_body_mid_pivot.name = "BodyMid"
	_body_mid_pivot.position = Vector3(-1.5 * v, 0, 0)
	add_child(_body_mid_pivot)
	# Segments at x offsets 0, v, 2v (relative to pivot).
	var seg_widths: Array[float] = [1.15, 1.20, 1.0]
	for i in seg_widths.size():
		var bw: float = seg_widths[i]
		var bs: float = v * bw
		var bx: float = i * v
		_add_voxel_to(_body_mid_pivot, Vector3(bx, 0, 0),
			Vector3(v, bs, bs * 0.95), mat_body)
		# Top + belly accents.
		_add_voxel_to(_body_mid_pivot, Vector3(bx, bs * 0.5, 0),
			Vector3(v, v * 0.25, bs * 0.55), mat_top)
		_add_voxel_to(_body_mid_pivot, Vector3(bx, -bs * 0.5, 0),
			Vector3(v, v * 0.25, bs * 0.55), mat_belly)
	# Lateral stripe accent along the body's side.
	for i in seg_widths.size():
		_add_voxel_to(_body_mid_pivot, Vector3(i * v, 0, v * 0.5),
			Vector3(v * 0.9, v * 0.35, v * 0.15), mat_accent)
		_add_voxel_to(_body_mid_pivot, Vector3(i * v, 0, -v * 0.5),
			Vector3(v * 0.9, v * 0.35, v * 0.15), mat_accent)
	# Dorsal fin (top, behind midpoint).
	_add_voxel_to(_body_mid_pivot, Vector3(v * 1.0, v * 0.95, 0),
		Vector3(v * 1.2, v * 0.4, v * 0.15), mat_fin)
	_add_voxel_to(_body_mid_pivot, Vector3(v * 1.2, v * 1.2, 0),
		Vector3(v * 0.6, v * 0.25, v * 0.12), mat_fin)
	# Anal fin (bottom).
	_add_voxel_to(_body_mid_pivot, Vector3(v * 1.6, -v * 0.85, 0),
		Vector3(v * 0.7, v * 0.35, v * 0.12), mat_fin)
	# Pectoral fins (sides, behind head).
	_add_voxel_to(_body_mid_pivot, Vector3(v * 0.2, -v * 0.1, v * 0.6),
		Vector3(v * 0.5, v * 0.25, v * 0.12), mat_fin)
	_add_voxel_to(_body_mid_pivot, Vector3(v * 0.2, -v * 0.1, -v * 0.6),
		Vector3(v * 0.5, v * 0.25, v * 0.12), mat_fin)

	# ---- TAIL (strong wag) - tail base at body's end, fin extends further ----
	_tail_pivot = Node3D.new()
	_tail_pivot.name = "TailPivot"
	# Pivot at the end of the body so rotation wags the whole tail visibly.
	_tail_pivot.position = Vector3(1.5 * v, 0, 0)
	add_child(_tail_pivot)
	# Tail peduncle (narrow connector).
	_add_voxel_to(_tail_pivot, Vector3(0, 0, 0),
		Vector3(v, v * 0.6, v * 0.5), mat_body)
	# Forked tail fin - top prong + bottom prong.
	_add_voxel_to(_tail_pivot, Vector3(v * 0.9, v * 0.45, 0),
		Vector3(v * 0.6, v * 0.4, v * 0.15), mat_fin)
	_add_voxel_to(_tail_pivot, Vector3(v * 0.9, -v * 0.45, 0),
		Vector3(v * 0.6, v * 0.4, v * 0.15), mat_fin)
	# Outer fin tips (a bit further back).
	_add_voxel_to(_tail_pivot, Vector3(v * 1.4, v * 0.7, 0),
		Vector3(v * 0.4, v * 0.3, v * 0.12), mat_fin)
	_add_voxel_to(_tail_pivot, Vector3(v * 1.4, -v * 0.7, 0),
		Vector3(v * 0.4, v * 0.3, v * 0.12), mat_fin)


func _add_voxel_to(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


func _make_mat(color: Color) -> ShaderMaterial:
	return VoxelMat.make(color)


func _add_voxel(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)


# ---- Tick (called by SimDriver) ----

func tick(dt: float, neighbors: Array, plants: Array, world_bounds: AABB) -> Dictionary:
	# Returns events for the SimDriver to act on (lay egg, spawn waste, die).
	var events: Dictionary = {}

	age += dt
	hunger = clampf(hunger + dt * 0.012, 0.0, 1.0)
	# Energy drains faster while bursting.
	var energy_drain := 0.005 + (0.04 if burst_remaining > 0.0 else 0.0)
	energy = clampf(energy - dt * energy_drain, 0.0, 1.0)
	burst_remaining = maxf(0.0, burst_remaining - dt)
	breed_cooldown = maxf(0.0, breed_cooldown - dt)
	nibble_cooldown = maxf(0.0, nibble_cooldown - dt)

	# Schooling stress climbs if too few conspecifics nearby.
	var conspecifics_nearby: int = 0
	for n in neighbors:
		if n is Fish and (n as Fish).species == species:
			conspecifics_nearby += 1
	if conspecifics_nearby < 2 and maturity != MATURITY_FRY:
		stress = clampf(stress + dt * 0.05, 0.0, 1.0)
	else:
		stress = maxf(0.0, stress - dt * 0.08)

	_update_maturity()

	# Senescent fish: slowly fade their colors.
	if maturity == MATURITY_SENESCENT:
		_apply_aging_tint()

	# Death conditions.
	if maturity == MATURITY_SENESCENT and age >= max_age_s * 1.15:
		events["die"] = true
		return events
	if hunger >= 1.0 and energy < 0.1:
		events["die"] = true
		return events

	# Behavior priority - higher tier wins. Each tier produces a desired velocity
	# (or events) for the brain.
	var desired := Vector3.ZERO
	var effective_max := max_speed * (1.6 if burst_remaining > 0.0 else 1.0)
	current_mode = Mode.CRUISE

	# Tier 0: wall avoidance always runs (additive).
	desired += _wall_avoid(world_bounds) * 3.0

	# Tier 1: COURTSHIP. Already paired? Continue the dance toward spawn.
	if partner != null:
		if not is_instance_valid(partner) or partner.maturity != MATURITY_ADULT:
			partner = null
			court_timer = 0.0
		else:
			current_mode = Mode.COURT
			var to_partner: Vector3 = partner.position - position
			var dist: float = to_partner.length()
			# Swim alongside (not into) the partner: target a point slightly to one side.
			var side: Vector3 = to_partner.cross(Vector3.UP).normalized() * 0.4
			var courtship_target: Vector3 = partner.position + side
			desired += (courtship_target - position).normalized() * effective_max * 0.7
			court_timer += dt
			# Spawn when we've been close enough for long enough.
			if dist < 1.2 and court_timer >= COURT_DURATION:
				current_mode = Mode.SPAWN
				events["lay_egg_with"] = partner
				breed_cooldown = 35.0
				energy = maxf(0.0, energy - 0.35)
				partner.breed_cooldown = 35.0
				partner.energy = maxf(0.0, partner.energy - 0.35)
				partner.partner = null
				partner = null
				court_timer = 0.0
			target_velocity = desired.limit_length(effective_max)
			return events

	# Tier 2: HUNGRY HERBIVORE. Chase plants if low food.
	if herbivory > 0.0 and hunger > 0.5 and maturity != MATURITY_FRY:
		if target_plant == null or not is_instance_valid(target_plant) \
				or target_plant.biomass() <= 0:
			target_plant = _find_nearest_plant(plants, 5.0)
		if target_plant != null:
			current_mode = Mode.FORAGE
			var top: Vector3 = target_plant.global_position
			top.y = target_plant.top_world_y()
			var dist: float = top.distance_to(position)
			if dist < 0.5 and nibble_cooldown <= 0.0:
				var taken := target_plant.nibble(1)
				if taken > 0:
					hunger = maxf(0.0, hunger - 0.30 * float(taken))
					energy = minf(1.0, energy + 0.06)
					nibble_cooldown = 0.9
					events["waste_at"] = position + Vector3(0, -0.1, 0)
					events["waste_amount"] = 0.15 * float(taken)
				target_plant = null
			else:
				# Burst toward the food if very hungry.
				if hunger > 0.8 and burst_remaining <= 0.0 and energy > 0.3:
					burst_remaining = 0.6
				desired += (top - position).normalized() * effective_max
				target_velocity = desired.limit_length(effective_max)
				return events

	# Tier 3: SEEK PARTNER. Adult, well-fed, not on cooldown, no current partner.
	if maturity == MATURITY_ADULT and breed_cooldown <= 0.0 and partner == null \
			and hunger < 0.5 and energy > 0.65 and stress < 0.4:
		var candidate: Fish = _find_breeding_partner(neighbors)
		if candidate != null and candidate.partner == null:
			# Mutual pair-bond.
			partner = candidate
			candidate.partner = self
			court_timer = 0.0
			candidate.court_timer = 0.0

	# Tier 4: SCHOOL. Default behavior - boids with dynamic tightness.
	current_mode = Mode.CRUISE
	# When stressed (too few neighbors), tighten the school dramatically.
	var tightness: float = 1.0 + stress * 1.5
	desired += _boids(neighbors, tightness) * schooling_strength

	# Drift toward preferred Y layer, more strongly when far from it.
	var dy: float = preferred_y - position.y
	desired.y += dy * 0.6

	# Mild wander via personal heading offset.
	desired += heading_offset * 0.5

	target_velocity = desired.limit_length(effective_max)
	# Position + facing now updated in _process at render rate.

	# Senescence speeds death.
	if maturity == MATURITY_SENESCENT:
		hunger = clampf(hunger + dt * 0.01, 0.0, 1.0)

	# Starvation kills.
	if hunger >= 1.0 and energy < 0.1:
		events["die"] = true

	# Update body scale across maturity.
	scale = scale.lerp(Vector3.ONE * _maturity_scale(), dt * 0.5)

	return events


# Per-frame: smooth velocity toward target (set by 10Hz brain), apply position,
# update facing, animate swim tail. Keeps motion buttery while brain ticks slowly.
func _process(dt: float) -> void:
	# Smooth current velocity toward the target the brain wants.
	velocity = velocity.lerp(target_velocity, clampf(dt * 3.0, 0.0, 1.0))
	position += velocity * dt

	# Face the direction of travel.
	if velocity.length_squared() > 0.0001:
		var dir: Vector3 = velocity.normalized()
		if absf(dir.dot(Vector3.UP)) < 0.95:
			look_at(position + velocity, Vector3.UP)

	# Swim animation: tail wags + body slightly counter-wags. Frequency
	# scales with speed - hovering fish wag slowly, dashing fish wag fast.
	var speed: float = velocity.length()
	var wag_freq: float = 2.5 + speed * 5.5
	_swim_phase += dt * wag_freq
	if _tail_pivot != null:
		_tail_pivot.rotation.y = sin(_swim_phase) * (0.35 + minf(speed * 0.18, 0.25))
	if _body_mid_pivot != null:
		_body_mid_pivot.rotation.y = -sin(_swim_phase) * 0.10


func _update_maturity() -> void:
	var t := age / max_age_s
	if t < 0.1:
		maturity = MATURITY_FRY
	elif t < 0.3:
		maturity = MATURITY_JUVENILE
	elif t < 0.85:
		maturity = MATURITY_ADULT
	else:
		maturity = MATURITY_SENESCENT


# ---- Boids ----

func _boids(neighbors: Array, tightness: float = 1.0) -> Vector3:
	# Standard 3-rule boids with two upgrades:
	#   - `tightness` shrinks the personal-space radius and amplifies cohesion,
	#     so stressed/threatened fish form tight balls and feeding fish spread.
	#   - Alignment and cohesion only count conspecifics; separation considers
	#     all neighbors (you don't want to swim into another species either).
	if neighbors.is_empty():
		return Vector3.ZERO
	var sep := Vector3.ZERO
	var ali := Vector3.ZERO
	var coh := Vector3.ZERO
	var count_conspecific: int = 0
	var effective_sep_radius: float = separation_radius / tightness
	for n in neighbors:
		if not n is Fish or n == self:
			continue
		var f: Fish = n
		var diff: Vector3 = position - f.position
		var d2: float = diff.length_squared()
		if d2 < 0.0001:
			continue
		if d2 < effective_sep_radius * effective_sep_radius:
			# Inverse-distance push so close fish push harder.
			sep += diff.normalized() / maxf(sqrt(d2), 0.1)
		if f.species == species:
			ali += f.velocity
			coh += f.position
			count_conspecific += 1
	var steer := sep * 2.0
	if count_conspecific > 0:
		ali /= float(count_conspecific)
		coh /= float(count_conspecific)
		# Cohesion strengthens with tightness (stressed -> ball up).
		var ali_strength: float = 0.7
		var coh_strength: float = 0.8 * tightness
		steer += (ali.normalized() if ali.length() > 0 else Vector3.ZERO) * ali_strength
		steer += ((coh - position).normalized()) * coh_strength
	return steer


func _apply_aging_tint() -> void:
	# Senescent fish fade their voxel materials toward a desaturated, darker
	# version of base_color. We only need to do this once when entering
	# senescence; track via _aged_applied to avoid repeated work.
	if _aged_applied:
		return
	_aged_applied = true
	var fade: Color = base_color.lerp(Color8(120, 110, 100), 0.45)
	# Walk all MeshInstance3D descendants and tint their material to the
	# faded color. Cheap since fish are small.
	for child in _all_meshes(self):
		var mi: MeshInstance3D = child
		var m: Material = mi.material_override
		if m is ShaderMaterial:
			(m as ShaderMaterial).set_shader_parameter("albedo", fade)


var _aged_applied: bool = false

func _all_meshes(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is MeshInstance3D:
			out.append(c)
		out.append_array(_all_meshes(c))
	return out


func _wall_avoid(b: AABB) -> Vector3:
	var margin := 1.0
	var v := Vector3.ZERO
	if position.x < b.position.x + margin:
		v.x += 1.0
	if position.x > b.position.x + b.size.x - margin:
		v.x -= 1.0
	if position.y < b.position.y + margin:
		v.y += 1.0
	if position.y > b.position.y + b.size.y - margin:
		v.y -= 1.0
	if position.z < b.position.z + margin:
		v.z += 1.0
	if position.z > b.position.z + b.size.z - margin:
		v.z -= 1.0
	return v


func _find_breeding_partner(neighbors: Array) -> Fish:
	# Prefer same-species adults of opposite sex, with no current partner,
	# low hunger, high energy, low stress. Within 3 units.
	var best: Fish = null
	var best_d2: float = 9.0
	for n in neighbors:
		if not n is Fish or n == self:
			continue
		var f: Fish = n
		if f.species != species or f.sex == sex:
			continue
		if f.maturity != MATURITY_ADULT or f.breed_cooldown > 0.0:
			continue
		if f.partner != null:
			continue
		if f.hunger > 0.5 or f.energy < 0.55 or f.stress > 0.4:
			continue
		var d2: float = f.position.distance_squared_to(position)
		if d2 < best_d2:
			best_d2 = d2
			best = f
	return best


func _find_nearest_plant(plants: Array, max_dist: float) -> Plant:
	var best: Plant = null
	var best_d: float = max_dist
	for p in plants:
		if not is_instance_valid(p) or p.biomass() <= 0:
			continue
		var top_pos: Vector3 = (p as Plant).global_position
		top_pos.y = (p as Plant).top_world_y()
		var d: float = top_pos.distance_to(position)
		if d < best_d:
			best_d = d
			best = p
	return best


# Used by SimDriver when this fish breeds with a partner.
func produce_offspring_genome(partner: Fish) -> Dictionary:
	# Average parental traits with small mutation, mix colors.
	var mix := 0.5
	var muta := 0.05
	var g: Dictionary = {
		"species": species,
		"base_color": base_color.lerp(partner.base_color, mix).lerp(
			Color(randf(), randf(), randf()), muta),
		"accent_color": accent_color.lerp(partner.accent_color, mix),
		"adult_voxel_scale": adult_voxel_scale,
		"max_age_s": max_age_s + randf_range(-20.0, 20.0),
		"max_speed": (max_speed + partner.max_speed) * 0.5 + randf_range(-0.1, 0.1),
		"schooling_strength": (schooling_strength + partner.schooling_strength) * 0.5,
		"separation_radius": separation_radius,
		"herbivory": herbivory,
		"fecundity": fecundity,
		"clutch_size": clutch_size,
		"preferred_y": preferred_y + randf_range(-0.3, 0.3),
		"sex": randi() % 2,
	}
	return g
