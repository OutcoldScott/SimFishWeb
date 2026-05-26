# Generative ambient audio.
#
# Uses AudioStreamGenerator (Godot's procedural-sample stream) to emit short
# sine-wave plinks on a small pentatonic scale. Triggered sparsely by world
# events (plant new-leaf, fish dart, bubble pop) so a healthy mature tank
# sounds calmer + more melodic; a fresh/chaotic tank sounds sparser + dissonant.
#
# Attach to a Node child of Main; call play_event_plink() from anywhere.

extends Node


const SAMPLE_RATE: int = 44100
const PENTATONIC_HZ: Array[float] = [
	261.63, 293.66, 329.63, 392.00, 440.00,  # C4, D4, E4, G4, A4
	523.25, 587.33, 659.25, 783.99, 880.00,  # one octave up
]

var _stream_player: AudioStreamPlayer = null
var _playback: AudioStreamGeneratorPlayback = null
var _pending: Array = []  # queue of (freq_hz, duration_s, amplitude) to play
# Ambient auto-pulse — drops in occasional plinks even without explicit
# events, with a rate that varies by day_phase. Daytime peaks at one
# plink every ~3 sim seconds; midnight tapers to one every ~12 s. Pitch
# also drifts higher at day, lower at night, so the soundscape literally
# brightens with the lights.
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


func play_event_plink(intensity: float = 0.5) -> void:
	# Pick a pitch on the pentatonic scale; gentle events play lower notes,
	# excited events play higher. Amplitude scales with intensity but stays
	# small so the soundscape never gets loud.
	var note_idx: int = clampi(int(intensity * float(PENTATONIC_HZ.size())),
		0, PENTATONIC_HZ.size() - 1)
	var freq: float = PENTATONIC_HZ[note_idx] * (0.95 + randf() * 0.10)
	var dur: float = 0.35 + randf() * 0.2
	var amp: float = 0.06 + intensity * 0.10
	_pending.append([freq, dur, amp])


func _process(_dt: float) -> void:
	if _playback == null:
		return
	# Day/night ambient layer. Auto-trigger plinks at a rate that follows
	# sim.daylight() — lots at midday, sparse at midnight — and bias the
	# intensity (which the plink function maps to pitch) higher in the day.
	# Lazily resolve the sim ref; main.tscn doesn't guarantee its position.
	if _sim_ref == null:
		_sim_ref = get_tree().current_scene.get_node_or_null(
			"SubViewport/World/SimDriver")
	if _sim_ref != null:
		var daylight: float = 1.0
		if _sim_ref.has_method("daylight"):
			daylight = float(_sim_ref.daylight())
		var sim_dt: float = _dt * float(_sim_ref.time_scale)
		_ambient_t -= sim_dt
		if _ambient_t <= 0.0:
			# Next plink in 3-12 s depending on daylight (frequent at day,
			# rare at night). Add ±30% jitter so the cadence doesn't
			# feel mechanical.
			var base_interval: float = lerpf(12.0, 3.0, daylight)
			_ambient_t = base_interval * randf_range(0.7, 1.3)
			# Intensity sets pitch via play_event_plink's scale-to-octave
			# mapping. Bright daylight → higher notes; deep night → low.
			play_event_plink(clampf(daylight * 0.85 + randf() * 0.2, 0.05, 0.95))
	# Volume also dips at night so the day/night contrast is audible at
	# whatever overall volume the player has set on their system.
	if _sim_ref != null:
		var dl_for_vol: float = 1.0
		if _sim_ref.has_method("daylight"):
			dl_for_vol = float(_sim_ref.daylight())
		_stream_player.volume_db = lerpf(-14.0, -6.0, dl_for_vol)
	# Service the audio buffer: synthesize as many samples as the generator
	# is willing to accept this frame. We mix all pending plinks together.
	var frames_available: int = _playback.get_frames_available()
	if frames_available <= 0:
		return
	for i in frames_available:
		var v: float = 0.0
		# Each pending note: advance its phase, add its contribution, decrement
		# its remaining duration. Drop when expired.
		for j in range(_pending.size() - 1, -1, -1):
			var note = _pending[j]
			var freq: float = note[0]
			var dur: float = note[1]
			var amp: float = note[2]
			if dur <= 0.0:
				_pending.remove_at(j)
				continue
			# Phase index stored as a 4th array element on first use.
			if note.size() < 4:
				note.append(0.0)
				_pending[j] = note
			var phase: float = note[3]
			# Simple decay envelope: amplitude tapers as dur counts down.
			var env: float = clampf(dur * 2.5, 0.0, 1.0)
			v += sin(phase * TAU) * amp * env
			note[3] = fposmod(phase + freq / float(SAMPLE_RATE), 1.0)
			note[1] = dur - 1.0 / float(SAMPLE_RATE)
			_pending[j] = note
		v = clampf(v, -1.0, 1.0)
		_playback.push_frame(Vector2(v, v))
