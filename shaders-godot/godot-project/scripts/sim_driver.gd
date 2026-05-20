# Central simulation ticker.
#
# Runs at a fixed rate (SIM_HZ) independent of the render rate. Each tick:
#   1. Gather neighbor lists (O(N^2) - fine for N <= 60 fish)
#   2. Tick every fish, collect events (waste, breed, die)
#   3. Tick every plant against the substrate grid
#   4. Tick every waste particle
#   5. Tick the substrate grid (diffuse + decay)
#   6. Resolve events: spawn fry, spawn waste, free dead fish
#
# Also tracks an autosave-able snapshot of the population stats and exposes
# a few signals for HUD/debug overlays.

extends Node
class_name SimDriver

signal stats_changed(stats: Dictionary)

const SIM_HZ: float = 10.0
const SIM_DT: float = 1.0 / SIM_HZ

var fish: Array[Fish] = []
var plants: Array[Plant] = []
var waste: Array[WasteParticle] = []
var eggs: Array[FishEgg] = []
var substrate: SubstrateGrid = null
var world_bounds: AABB = AABB(Vector3(-8, 1.6, -4), Vector3(16, 5, 8))
var substrate_top_y: float = 1.6

# Layout-related: where to parent new spawns.
var fauna_root: Node3D = null
var waste_root: Node3D = null
var plants_root: Node3D = null

var _accum: float = 0.0
var _stats_timer: float = 0.0


func register_fish(f: Fish) -> void:
	fish.append(f)
	f.sim = self


func register_plant(p: Plant) -> void:
	plants.append(p)


func register_waste(w: WasteParticle) -> void:
	waste.append(w)


func register_egg(e: FishEgg) -> void:
	eggs.append(e)


func _physics_process(dt: float) -> void:
	_accum += dt
	while _accum >= SIM_DT:
		_accum -= SIM_DT
		_tick(SIM_DT)
	_stats_timer += dt
	if _stats_timer >= 1.0:
		_stats_timer = 0.0
		_emit_stats()


func _tick(dt: float) -> void:
	# 1. Prune invalid refs (queue_freed nodes).
	fish = fish.filter(func(f): return is_instance_valid(f))
	plants = plants.filter(func(p): return is_instance_valid(p))
	waste = waste.filter(func(w): return is_instance_valid(w))
	eggs = eggs.filter(func(e): return is_instance_valid(e))

	# 2. Substrate field.
	if substrate != null:
		substrate.tick(dt)

	# 3. Plants.
	for p in plants:
		p.tick(dt, substrate)

	# 4. Fish: gather neighbors, tick, collect events.
	# Use O(N^2) - fine up to ~60.
	var events: Array[Dictionary] = []
	for f in fish:
		var neighbors: Array = []
		for g in fish:
			if g == f: continue
			if g.position.distance_squared_to(f.position) < 9.0:  # 3.0 radius
				neighbors.append(g)
		var ev: Dictionary = f.tick(dt, neighbors, plants, world_bounds)
		if ev.size() > 0:
			ev["actor"] = f
			events.append(ev)

	# 5. Waste.
	var dead_waste: Array[WasteParticle] = []
	for w in waste:
		if w.tick(dt, substrate):
			dead_waste.append(w)
	for w in dead_waste:
		w.queue_free()

	# 6. Eggs - tick incubation, hatch when ready.
	var hatched: Array[FishEgg] = []
	for e in eggs:
		if e.tick(dt):
			hatched.append(e)
	for e in hatched:
		_hatch(e)
		e.queue_free()

	# 7. Resolve fish events.
	for ev in events:
		var actor: Fish = ev.get("actor", null)
		if actor == null or not is_instance_valid(actor):
			continue
		if ev.has("waste_at"):
			_spawn_waste(ev["waste_at"], ev.get("waste_amount", 0.2))
		if ev.has("lay_egg_with"):
			var partner: Fish = ev["lay_egg_with"]
			if is_instance_valid(partner):
				_lay_eggs(actor, partner)
		if ev.get("die", false):
			# On death, drop a single waste particle worth a bit of nutrient,
			# then free the fish. This closes the loop: fish biomass -> substrate.
			_spawn_waste(actor.position, 0.4)
			actor.queue_free()


func _spawn_waste(at: Vector3, amount: float) -> void:
	if waste_root == null:
		return
	var w := WasteParticle.new()
	waste_root.add_child(w)
	w.global_position = at
	w.init(amount, substrate_top_y)
	register_waste(w)


func _lay_eggs(a: Fish, b: Fish) -> void:
	# Place eggs on a plant if one is nearby (substrate spawners) OR on the
	# substrate directly. Each egg is a separate node that incubates and
	# hatches into a fry.
	if fauna_root == null:
		return
	var n: int = mini(a.clutch_size, 4)
	var mid: Vector3 = (a.position + b.position) * 0.5
	# Find a plant near the spawn site to lay eggs on (more realistic - many
	# species use plant leaves as a substrate). Fall back to dropping eggs
	# onto the tank floor.
	var lay_at: Vector3 = mid
	lay_at.y = maxf(substrate_top_y + 0.15, mid.y - 0.5)
	var best_plant: Plant = null
	var best_d2: float = 16.0
	for p in plants:
		if not is_instance_valid(p) or p.biomass() <= 0:
			continue
		var pp: Vector3 = p.global_position
		pp.y = p.top_world_y()
		var d2: float = pp.distance_squared_to(mid)
		if d2 < best_d2:
			best_d2 = d2
			best_plant = p
	if best_plant != null:
		lay_at = best_plant.global_position
		lay_at.y = best_plant.top_world_y()

	for i in n:
		var g: Dictionary = a.produce_offspring_genome(b)
		var e := FishEgg.new()
		fauna_root.add_child(e)
		e.global_position = lay_at + Vector3(
			randf_range(-0.2, 0.2),
			randf_range(0.0, 0.15),
			randf_range(-0.2, 0.2),
		)
		e.init(g)
		register_egg(e)


func _hatch(e: FishEgg) -> void:
	if fauna_root == null:
		return
	var fry := Fish.new()
	fry.species = e.species
	fauna_root.add_child(fry)
	fry.global_position = e.global_position + Vector3(0, 0.1, 0)
	fry.init_genome(e.genome)
	# Newborn fry start hungry but with full energy.
	fry.hunger = 0.3
	fry.energy = 1.0
	register_fish(fry)


func _emit_stats() -> void:
	var total_biomass: int = 0
	var n_adults: int = 0
	var n_fry: int = 0
	for f in fish:
		if f.maturity == Fish.MATURITY_ADULT:
			n_adults += 1
		elif f.maturity == Fish.MATURITY_FRY:
			n_fry += 1
	for p in plants:
		total_biomass += p.biomass()
	var s: Dictionary = {
		"fish_total": fish.size(),
		"fish_adults": n_adults,
		"fish_fry": n_fry,
		"eggs": eggs.size(),
		"plants_alive": plants.size(),
		"plant_total_biomass": total_biomass,
		"waste_particles": waste.size(),
		"substrate_nutrients_total": substrate.total_above_baseline() if substrate else 0.0,
	}
	stats_changed.emit(s)
	print("[vivarium] ", s)
