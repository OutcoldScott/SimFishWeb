# Orbit camera using POLLED input (Input class), not event subscription.
# This sidesteps the issue that Camera3D inside a SubViewport doesn't reliably
# receive InputEvent callbacks - the SubViewport has no SubViewportContainer
# forwarding events to it, so _input/_unhandled_input on the Camera never fires.
#
# Polling the global Input class works regardless of viewport plumbing.
#
# Controls:
#   left or right mouse drag : orbit (yaw / pitch around target)
#   scroll wheel             : zoom in / out (events still needed for wheel)
#   W / S                    : pan target forward / back along view direction
#   A / D                    : pan target left / right
#   Q / E                    : pan target down / up
#   F                        : reset to default view
#   space                    : toggle slow auto-orbit (cinematic mode)

extends Camera3D

@export var target: Vector3 = Vector3(0, 3.0, 0)
@export var radius: float = 14.0
@export var yaw: float = 0.0
@export var pitch: float = -0.2

@export var sensitivity_x: float = 0.006
@export var sensitivity_y: float = 0.006
@export var zoom_factor: float = 1.12
@export var min_radius: float = 3.0
@export var max_radius: float = 40.0
@export var min_pitch: float = -1.45
@export var max_pitch: float = 1.45
@export var pan_speed: float = 6.0
@export var auto_orbit_speed: float = 0.08

var _orbiting: bool = false
var _last_mouse_pos: Vector2 = Vector2.ZERO
var _auto_orbit: bool = false
var _space_was_pressed: bool = false


func _ready() -> void:
	_refresh()


func _process(dt: float) -> void:
	# ---- Mouse orbit (polling-based) ----
	var mouse_now: Vector2 = get_viewport().get_mouse_position()
	var any_btn: bool = (
		Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)
	)
	if any_btn and not _orbiting:
		_orbiting = true
		_last_mouse_pos = mouse_now
	elif not any_btn and _orbiting:
		_orbiting = false

	if _orbiting:
		var delta: Vector2 = mouse_now - _last_mouse_pos
		_last_mouse_pos = mouse_now
		if delta.length_squared() > 0.0:
			yaw   -= delta.x * sensitivity_x
			pitch -= delta.y * sensitivity_y
			pitch = clampf(pitch, min_pitch, max_pitch)
			_refresh()

	# ---- WASD pan (camera-relative) ----
	var forward: Vector3 = (target - global_position)
	forward.y = 0.0
	if forward.length_squared() > 0.001:
		forward = forward.normalized()
		var right: Vector3 = forward.cross(Vector3.UP).normalized()
		var step: float = pan_speed * dt
		var moved: bool = false
		if Input.is_key_pressed(KEY_W): target += forward * step; moved = true
		if Input.is_key_pressed(KEY_S): target -= forward * step; moved = true
		if Input.is_key_pressed(KEY_D): target += right * step;   moved = true
		if Input.is_key_pressed(KEY_A): target -= right * step;   moved = true
		if Input.is_key_pressed(KEY_E): target.y += step;          moved = true
		if Input.is_key_pressed(KEY_Q): target.y -= step;          moved = true
		if Input.is_key_pressed(KEY_F):
			target = Vector3(0, 3.0, 0)
			radius = 14.0
			yaw = 0.0
			pitch = -0.2
			moved = true
		if moved:
			_refresh()

	# ---- Space toggle (edge-triggered) ----
	var space_now: bool = Input.is_key_pressed(KEY_SPACE)
	if space_now and not _space_was_pressed:
		_auto_orbit = not _auto_orbit
	_space_was_pressed = space_now

	# ---- Auto-orbit ----
	if _auto_orbit:
		yaw += auto_orbit_speed * dt
		_refresh()


# Scroll wheel doesn't come through Input class polling, so we still need an
# event handler for it. Try _input on the root via the Main node instead;
# attach a tiny forwarder script there if this doesn't fire.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				radius = maxf(min_radius, radius / zoom_factor)
				_refresh()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				radius = minf(max_radius, radius * zoom_factor)
				_refresh()


# Public API so something at the root viewport can forward events here
# if needed (the Main scene controller does this as a belt-and-suspenders).
func apply_zoom(direction: int) -> void:
	# direction: +1 = zoom in, -1 = zoom out
	if direction > 0:
		radius = maxf(min_radius, radius / zoom_factor)
	else:
		radius = minf(max_radius, radius * zoom_factor)
	_refresh()


func _refresh() -> void:
	var x := cos(pitch) * sin(yaw)
	var y := sin(pitch)
	var z := cos(pitch) * cos(yaw)
	global_position = target + Vector3(x, y, z) * radius
	look_at(target, Vector3.UP)
