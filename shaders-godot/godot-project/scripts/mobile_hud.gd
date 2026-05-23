# Mobile HUD overlay.
#
# Shows on-screen buttons for actions that have no touch equivalent (speed
# control, photo, undo). Only visible when OS.has_feature("mobile") is true.
# The Main script wires up signals in _setup_mobile_ui().
#
# Layout: bottom-left speed row, bottom-right action cluster. All buttons are
# sized at ≥48×48dp to meet Android touch-target guidelines.

extends Control

signal pause_pressed
signal speed_pressed(scale: float)
signal photo_pressed
signal undo_pressed

var _pause_btn: Button
var _speed_btns: Dictionary = {}
var _photo_btn: Button
var _undo_btn: Button
var _current_speed: float = 1.0
var _is_paused: bool = false


func _ready() -> void:
	# Only show on mobile.
	if not (OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")):
		visible = false
		return
	
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_speed_row()
	_build_action_row()


func _build_speed_row() -> void:
	# Bottom-left: ⏸ 1× 4× 16×
	var container := HBoxContainer.new()
	container.add_theme_constant_override("separation", 6)
	container.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(container)
	
	# Anchor to bottom-left.
	container.anchor_left = 0.0
	container.anchor_top = 1.0
	container.anchor_right = 0.0
	container.anchor_bottom = 1.0
	container.offset_left = 16.0
	container.offset_top = -64.0
	container.offset_right = 300.0
	container.offset_bottom = -8.0
	
	_pause_btn = _make_btn("⏸", Color8(220, 180, 80))
	_pause_btn.pressed.connect(func():
		_is_paused = not _is_paused
		_pause_btn.text = "▶" if _is_paused else "⏸"
		pause_pressed.emit())
	container.add_child(_pause_btn)
	
	for entry in [
		{"label": "1×", "scale": 1.0},
		{"label": "4×", "scale": 4.0},
		{"label": "16×", "scale": 16.0},
	]:
		var btn := _make_btn(String(entry["label"]), Color8(180, 200, 220))
		var s: float = float(entry["scale"])
		btn.pressed.connect(func():
			_current_speed = s
			_is_paused = false
			_pause_btn.text = "⏸"
			_highlight_speed(s)
			speed_pressed.emit(s))
		container.add_child(btn)
		_speed_btns[s] = btn
	_highlight_speed(1.0)


func _build_action_row() -> void:
	# Bottom-right: 📷 ↩
	var container := HBoxContainer.new()
	container.add_theme_constant_override("separation", 6)
	container.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(container)
	
	# Anchor to bottom-right.
	container.anchor_left = 1.0
	container.anchor_top = 1.0
	container.anchor_right = 1.0
	container.anchor_bottom = 1.0
	container.offset_left = -160.0
	container.offset_top = -64.0
	container.offset_right = -16.0
	container.offset_bottom = -8.0
	
	_photo_btn = _make_btn("📷", Color8(150, 200, 170))
	_photo_btn.pressed.connect(func(): photo_pressed.emit())
	container.add_child(_photo_btn)
	
	_undo_btn = _make_btn("↩", Color8(220, 130, 130))
	_undo_btn.pressed.connect(func(): undo_pressed.emit())
	_undo_btn.visible = false  # Only shown in aquascape mode.
	container.add_child(_undo_btn)


func _make_btn(label: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(56, 48)
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", color)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	return btn


func _highlight_speed(active: float) -> void:
	for s in _speed_btns.keys():
		var btn: Button = _speed_btns[s]
		if is_equal_approx(float(s), active):
			btn.modulate = Color(1.3, 1.3, 0.8)
		else:
			btn.modulate = Color(0.7, 0.7, 0.7)


# Called by the main script when aquascape mode toggles.
func set_aquascape_mode(on: bool) -> void:
	if _undo_btn != null:
		_undo_btn.visible = on
