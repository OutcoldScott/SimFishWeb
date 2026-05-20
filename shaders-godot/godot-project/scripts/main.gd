# Main scene controller.
#
# Responsibilities:
#   - Bind the SubViewport's render output to the Display TextureRect.
#   - DRIVE THE ORBIT CAMERA. The Camera3D lives inside a SubViewport that has
#     no SubViewportContainer above it, which means input events and mouse
#     position queries inside the SubViewport are unreliable. So we do all
#     mouse + keyboard handling here at the root (where input absolutely
#     works) and just update the Camera3D's transform directly.
#   - Show a small debug HUD with live input state so we can diagnose what's
#     happening when the camera doesn't respond.

extends Node


@onready var sub_viewport: SubViewport = $SubViewport
@onready var display: TextureRect = $Display
@onready var camera: Camera3D = $SubViewport/World/Camera3D
@onready var hud: Label = $DebugHUD

# Orbit state - default angle is the "feels nice" view the user landed on
# (drag to refine, F to reset back to this).
const DEFAULT_TARGET := Vector3(0, 3.0, 0)
const DEFAULT_RADIUS := 14.0
const DEFAULT_YAW := -0.35
const DEFAULT_PITCH := 0.30

var target: Vector3 = DEFAULT_TARGET
var radius: float = DEFAULT_RADIUS
var yaw: float = DEFAULT_YAW
var pitch: float = DEFAULT_PITCH

const SENSITIVITY: float = 0.006
const ZOOM_FACTOR: float = 1.12
const MIN_RADIUS: float = 3.0
const MAX_RADIUS: float = 40.0
const MIN_PITCH: float = -1.45
const MAX_PITCH: float = 1.45
const PAN_SPEED: float = 6.0
const AUTO_ORBIT_SPEED: float = 0.08

var _orbiting: bool = false
var _last_mouse: Vector2 = Vector2.ZERO
var _auto_orbit: bool = false
var _space_was_pressed: bool = false


func _ready() -> void:
	display.texture = sub_viewport.get_texture()
	_apply_camera()


func _process(dt: float) -> void:
	# Mouse position: use the WINDOW's mouse position (not the SubViewport's),
	# since that's where the OS cursor actually lives. get_window() returns
	# this scene's OS window.
	var mouse_now: Vector2 = get_window().get_mouse_position()
	var any_btn: bool = (
		Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)
	)

	if any_btn and not _orbiting:
		_orbiting = true
		_last_mouse = mouse_now
	elif not any_btn and _orbiting:
		_orbiting = false

	if _orbiting:
		var delta: Vector2 = mouse_now - _last_mouse
		_last_mouse = mouse_now
		if delta.length_squared() > 0.0:
			yaw -= delta.x * SENSITIVITY
			pitch -= delta.y * SENSITIVITY
			pitch = clampf(pitch, MIN_PITCH, MAX_PITCH)
			_apply_camera()

	# WASD pan target along view direction.
	var fwd: Vector3 = (target - camera.global_position)
	fwd.y = 0.0
	if fwd.length_squared() > 0.001:
		fwd = fwd.normalized()
		var right: Vector3 = fwd.cross(Vector3.UP).normalized()
		var step: float = PAN_SPEED * dt
		var moved: bool = false
		if Input.is_key_pressed(KEY_W): target += fwd * step; moved = true
		if Input.is_key_pressed(KEY_S): target -= fwd * step; moved = true
		if Input.is_key_pressed(KEY_D): target += right * step; moved = true
		if Input.is_key_pressed(KEY_A): target -= right * step; moved = true
		if Input.is_key_pressed(KEY_E): target.y += step; moved = true
		if Input.is_key_pressed(KEY_Q): target.y -= step; moved = true
		if Input.is_key_pressed(KEY_F):
			target = DEFAULT_TARGET
			radius = DEFAULT_RADIUS
			yaw = DEFAULT_YAW
			pitch = DEFAULT_PITCH
			moved = true
		if moved:
			_apply_camera()

	# Space toggles auto-orbit.
	var space_now: bool = Input.is_key_pressed(KEY_SPACE)
	if space_now and not _space_was_pressed:
		_auto_orbit = not _auto_orbit
	_space_was_pressed = space_now
	if _auto_orbit:
		yaw += AUTO_ORBIT_SPEED * dt
		_apply_camera()

	# Update debug HUD every frame.
	_update_hud(mouse_now, any_btn)


# Scroll wheel comes through as button events, not as Input.is_pressed state.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				radius = maxf(MIN_RADIUS, radius / ZOOM_FACTOR)
				_apply_camera()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				radius = minf(MAX_RADIUS, radius * ZOOM_FACTOR)
				_apply_camera()


func _apply_camera() -> void:
	if camera == null:
		return
	var x := cos(pitch) * sin(yaw)
	var y := sin(pitch)
	var z := cos(pitch) * cos(yaw)
	camera.global_position = target + Vector3(x, y, z) * radius
	camera.look_at(target, Vector3.UP)


func _update_hud(mouse_pos: Vector2, any_btn: bool) -> void:
	if hud == null:
		return
	var lines: Array[String] = []
	lines.append("mouse: %d, %d" % [int(mouse_pos.x), int(mouse_pos.y)])
	lines.append("btn: %s  orbiting: %s  auto: %s" % [
		"yes" if any_btn else "no",
		"yes" if _orbiting else "no",
		"yes" if _auto_orbit else "no",
	])
	lines.append("yaw: %.2f  pitch: %.2f  radius: %.1f" % [yaw, pitch, radius])
	lines.append("target: %.1f, %.1f, %.1f" % [target.x, target.y, target.z])
	lines.append("cam: %.1f, %.1f, %.1f" % [
		camera.global_position.x, camera.global_position.y, camera.global_position.z])
	lines.append("drag any mouse button to orbit, scroll to zoom, WASDQE to pan, F to reset, SPACE auto")
	hud.text = "\n".join(lines)
