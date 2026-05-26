# Generative ambient audio.
#
# Uses AudioStreamGenerator (Godot's procedural-sample stream) to emit short
# FM synthesised chimes and arpeggios on a dynamic scale that crossfades
# between Major Pentatonic (C) during the day and Minor Pentatonic (A) at night.
# Triggered by world events (plant new-leaf, fish dart, bubble pop, eating, spawning, dying)
# so the actions of the aquarium creatures generate real-time music.
#
# Attach to a Node child of Main; call play_event_plink() or play_aquarium_event() from anywhere.

extends Node

const SAMPLE_RATE: int = 44100

# Day scale: C major pentatonic (joyful, bright)
const SCALE_MAJOR: Array[float] = [
	261.63, 293.66, 329.63, 392.00, 440.00,  # C4, D4, E4, G4, A4
	523.25, 587.33, 659.25, 783.99, 880.00,  # C5, D5, E5, G5, A5
]

# Night scale: A minor pentatonic (calm, mysterious)
const SCALE_MINOR: Array[float] = [
	220.00, 261.63, 293.66, 329.63, 392.00,  # A3, C4, D4, E4, G4
	440.00, 523.25, 587.33, 659.25, 783.99,  # A4, C5, D5, E5, G5
]

var _stream_player: AudioStreamPlayer = null
var _playback: AudioStreamGeneratorPlayback = null

# Queue of active playing notes. Each note is an array:
# [freq, dur, amp, phase, mod_phase, mod_ratio, mod_index, decay_speed, attack_time, initial_dur]
var _pending: Array = []

var _ambient_t: float = 0.0
var _sim_ref: Node = null


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = SAMPLE_RATE
	gen.buffer_length = 0.2
	_stream_player = AudioStreamPlayer.new()
	_stream_player.stream = gen
	_stream_player.volume_db = -8.0
	add_child(_stream_player)
	_stream_player.play()
	_playback = _stream_player.get_stream_playback() as AudioStreamGeneratorPlayback


func _is_music_enabled() -> bool:
	var cfg = get_node_or_null("/root/TankConfig")
	if cfg != null:
		return bool(cfg.music_enabled)
	return true


func silence_immediately() -> void:
	_pending.clear()
	if _stream_player != null:
		_stream_player.volume_db = -80.0


func _get_current_scale() -> Array[float]:
	if _sim_ref != null and _sim_ref.has_method("daylight"):
		var dl: float = float(_sim_ref.daylight())
		if dl > 0.35:
			return SCALE_MAJOR
		else:
			return SCALE_MINOR
	return SCALE_MAJOR


func play_note(freq: float, amp: float, dur: float, mod_ratio: float = 2.01, mod_index: float = 1.5, decay_speed: float = 2.5, attack_time: float = 0.0) -> void:
	if not _is_music_enabled():
		return
	# Limit maximum simultaneous notes to prevent audio clipping/distortion (keep it musical and clear)
	if _pending.size() > 16:
		return
	_pending.append([freq, dur, amp, 0.0, 0.0, mod_ratio, mod_index, decay_speed, attack_time, dur])


func play_event_plink(intensity: float = 0.5) -> void:
	if not _is_music_enabled():
		return
	var scale := _get_current_scale()
	var note_idx: int = clampi(int(intensity * float(scale.size())), 0, scale.size() - 1)
	var freq: float = scale[note_idx] * randf_range(0.97, 1.03)
	
	# Play as a warm chime bell
	play_note(freq, 0.04 + intensity * 0.06, 0.6 + randf() * 0.3, 2.01, 1.5, 2.0)


# Main router for aquarium boid events converting actions into melodic lines.
func play_aquarium_event(event_name: String) -> void:
	if not _is_music_enabled():
		return
		
	match event_name:
		"birth":
			play_birth_sfx()
		"spawn":
			play_spawn_sfx()
		"death":
			play_death_sfx()
		"eat":
			play_eat_sfx(randf_range(0.35, 0.65))
		_:
			play_event_plink(0.5)


func play_eat_sfx(intensity: float = 0.5) -> void:
	var scale := _get_current_scale()
	# Pick a higher note for eating (high chime/pluck)
	var note_idx: int = clampi(int(intensity * 4.0) + 5, 0, scale.size() - 1)
	var freq: float = scale[note_idx] * randf_range(0.99, 1.01)
	# Fast-decay pluck
	play_note(freq, 0.07 + intensity * 0.05, 0.18, 1.0, 0.5, 5.5)


func play_birth_sfx() -> void:
	var scale := _get_current_scale()
	# Upward cascading major arpeggio using attack offsets as onset delays
	var base_idx: int = randi() % 4
	var notes = [base_idx, base_idx + 2, base_idx + 4]
	var attack_offsets = [0.0, 0.08, 0.16]
	for i in range(notes.size()):
		var note_idx = clampi(notes[i], 0, scale.size() - 1)
		var freq = scale[note_idx]
		play_note(freq, 0.09, 0.7 - attack_offsets[i], 2.01, 1.8, 2.2, attack_offsets[i])


func play_death_sfx() -> void:
	var scale := _get_current_scale()
	# Low, solemn descending minor arpeggio (dropped one octave)
	var base_idx: int = randi() % 3
	var notes = [base_idx + 4, base_idx + 2, base_idx]
	var attack_offsets = [0.0, 0.12, 0.24]
	for i in range(notes.size()):
		var note_idx = clampi(notes[i], 0, scale.size() - 1)
		var freq = scale[note_idx] * 0.5 # Drop 1 octave
		play_note(freq, 0.12, 1.2 - attack_offsets[i], 1.0, 0.6, 1.6, attack_offsets[i])


func play_spawn_sfx() -> void:
	var scale := _get_current_scale()
	# Beautiful concurrent harmonic triad
	var base_idx: int = randi() % 3 + 2
	var notes = [base_idx, base_idx + 2, base_idx + 4]
	for i in range(notes.size()):
		var note_idx = clampi(notes[i], 0, scale.size() - 1)
		var freq = scale[note_idx]
		play_note(freq, 0.07, 1.0, 2.01, 2.2, 1.8)


func _process(_dt: float) -> void:
	if _playback == null:
		return
		
	# Lazily resolve the sim ref
	if _sim_ref == null:
		_sim_ref = get_tree().current_scene.get_node_or_null("SubViewport/World/SimDriver")
		
	if not _is_music_enabled():
		return
		
	if _sim_ref != null:
		var daylight: float = 1.0
		if _sim_ref.has_method("daylight"):
			daylight = float(_sim_ref.daylight())
		var sim_dt: float = _dt * float(_sim_ref.time_scale)
		_ambient_t -= sim_dt
		if _ambient_t <= 0.0:
			var complexity: float = 0.5
			var cfg = get_node_or_null("/root/TankConfig")
			if cfg != null:
				complexity = float(cfg.music_complexity)
				
			if complexity <= 0.05:
				_ambient_t = 5.0 # only events make music, skip background melody
			else:
				# High complexity -> fast background melody; low complexity -> sparse
				var complexity_scale: float = lerpf(3.0, 0.4, complexity)
				var base_interval: float = lerpf(12.0, 3.0, daylight) * complexity_scale
				_ambient_t = base_interval * randf_range(0.7, 1.3)
				play_event_plink(clampf(daylight * 0.85 + randf() * 0.2, 0.05, 0.95))
				
	# Master volume scaling based on user config and day/night cycle
	if _sim_ref != null:
		var dl_for_vol: float = 1.0
		if _sim_ref.has_method("daylight"):
			dl_for_vol = float(_sim_ref.daylight())
			
		var user_volume: float = 0.7
		var cfg = get_node_or_null("/root/TankConfig")
		if cfg != null:
			user_volume = float(cfg.music_volume)
			
		if user_volume <= 0.01:
			_stream_player.volume_db = -80.0
		else:
			var max_vol_db: float = lerpf(-30.0, -6.0, user_volume)
			var min_vol_db: float = lerpf(-40.0, -14.0, user_volume)
			_stream_player.volume_db = lerpf(min_vol_db, max_vol_db, dl_for_vol)
			
	# Service the audio buffer
	var frames_available: int = _playback.get_frames_available()
	if frames_available <= 0:
		return
		
	for i in frames_available:
		var v: float = 0.0
		for j in range(_pending.size() - 1, -1, -1):
			var note = _pending[j]
			var freq: float = note[0]
			var dur: float = note[1]
			var amp: float = note[2]
			if dur <= 0.0:
				_pending.remove_at(j)
				continue
				
			var phase: float = note[3]
			var mod_phase: float = note[4]
			var mod_ratio: float = note[5]
			var mod_index: float = note[6]
			var decay_speed: float = note[7]
			var attack_time: float = note[8]
			var initial_dur: float = note[9]
			
			# Envelope computation (Attack-Decay)
			var env: float = 1.0
			var elapsed: float = initial_dur - dur
			
			if attack_time > 0.0 and elapsed < attack_time:
				env = elapsed / attack_time
			else:
				env = clampf(dur * decay_speed, 0.0, 1.0)
				
			# FM Synthesis
			var mod_freq: float = freq * mod_ratio
			var current_mod_index: float = mod_index * env
			var modulator: float = sin(mod_phase * TAU) * mod_freq * current_mod_index
			
			# Carrier
			var carrier_out: float = sin(phase * TAU + modulator / float(SAMPLE_RATE))
			v += carrier_out * amp * env
			
			# Advance phases
			note[3] = fposmod(phase + freq / float(SAMPLE_RATE), 1.0)
			note[4] = fposmod(mod_phase + mod_freq / float(SAMPLE_RATE), 1.0)
			note[1] = dur - 1.0 / float(SAMPLE_RATE)
			_pending[j] = note
			
		v = clampf(v, -1.0, 1.0)
		_playback.push_frame(Vector2(v, v))
