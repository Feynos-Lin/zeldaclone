extends Node
## Synthesizes every sound effect at startup — no audio files needed.

const RATE := 22050

var streams := {}
var pool: Array = []
var pool3d: Array = []
var next := 0
var next3d := 0


func _ready() -> void:
	streams["swing"] = make(gen_swing(0.18, 0.35))
	streams["spin"] = make(gen_swing(0.42, 0.25))
	streams["hit"] = make(gen_hit())
	streams["hurt"] = make(gen_sweep(520.0, 200.0, 0.28, "square", 0.35))
	streams["roll"] = make(gen_swing(0.22, 0.6, 0.18))
	streams["lock"] = make(gen_tones([660.0, 990.0], 0.05, "square", 0.18))
	streams["charged"] = make(gen_tones([1320.0, 1760.0], 0.05, "sine", 0.3))
	streams["shard"] = make(gen_tones([1046.0, 1568.0], 0.06, "square", 0.2))
	streams["heart"] = make(gen_tones([523.0, 659.0, 784.0, 1046.0], 0.06, "sine", 0.35))
	streams["blip"] = make(gen_tones([1200.0], 0.02, "square", 0.08))
	streams["swipe"] = make(gen_swing(0.2, 0.15, 0.4))
	streams["groan"] = make(gen_groan(1.3, 78.0))
	streams["die"] = make(gen_groan(1.0, 60.0))
	streams["gameover"] = make(gen_sweep(330.0, 82.0, 1.4, "square", 0.3))
	streams["stomp"] = make(gen_thud(95.0, 0.28, 0.5))
	streams["land"] = make(gen_thud(70.0, 0.14, 0.25))
	streams["jump"] = make(gen_swing(0.16, 0.25, 0.25))
	streams["block"] = make(gen_clang())
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.volume_db = -6.0
		add_child(p)
		pool.append(p)


func get_stream(sname: String) -> AudioStream:
	return streams.get(sname)


func play(sname: String, pitch: float = 1.0) -> void:
	if not streams.has(sname):
		return
	var p: AudioStreamPlayer = pool[next]
	next = (next + 1) % pool.size()
	p.stream = streams[sname]
	p.pitch_scale = pitch * randf_range(0.96, 1.04)
	p.play()


func play_at(sname: String, pos: Vector3) -> void:
	if not streams.has(sname):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = streams[sname]
	p.max_distance = 30.0
	p.unit_size = 6.0
	p.pitch_scale = randf_range(0.92, 1.08)
	add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


func make(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


func gen_swing(dur: float, brightness: float, vol: float = 0.7) -> PackedFloat32Array:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / n
		var cutoff := 0.03 + brightness * sin(t * PI)
		lp += (randf_range(-1.0, 1.0) - lp) * cutoff
		out[i] = lp * sin(t * PI) * vol * 2.0
	return out


func gen_hit() -> PackedFloat32Array:
	var n := int(RATE * 0.22)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 160.0 * exp(-t * 18.0) + 55.0
		phase += f / RATE
		var env := exp(-t * 16.0)
		var noise := randf_range(-1.0, 1.0) * exp(-t * 60.0)
		out[i] = (sin(phase * TAU) * 0.8 + noise * 0.6) * env
	return out


## Low knock: falling sine body plus a short burst of filtered noise.
func gen_thud(f0: float, dur: float, vol: float) -> PackedFloat32Array:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += (f0 * (0.6 + 0.4 * exp(-t * 30.0))) / RATE
		lp += (randf_range(-1.0, 1.0) - lp) * 0.25
		out[i] = (sin(phase * TAU) * exp(-t * 14.0) + lp * exp(-t * 45.0) * 0.8) * vol * 2.0
	return out


## Metal on metal: a few inharmonic partials ringing out over a hit.
func gen_clang() -> PackedFloat32Array:
	var n := int(RATE * 0.45)
	var out := PackedFloat32Array()
	out.resize(n)
	var partials := [[523.0, 1.0], [1187.0, 0.6], [1803.0, 0.45], [2633.0, 0.3]]
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for pr in partials:
			v += sin(TAU * float(pr[0]) * t) * float(pr[1]) * exp(-t * (6.0 + float(pr[0]) / 400.0))
		v += randf_range(-1.0, 1.0) * exp(-t * 80.0) * 0.8
		out[i] = v * 0.28
	return out


func osc(kind: String, phase: float) -> float:
	match kind:
		"square":
			return 1.0 if fposmod(phase, 1.0) < 0.5 else -1.0
		"saw":
			return fposmod(phase, 1.0) * 2.0 - 1.0
	return sin(phase * TAU)


func gen_sweep(f0: float, f1: float, dur: float, kind: String, vol: float) -> PackedFloat32Array:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		phase += lerpf(f0, f1, t) / RATE
		out[i] = osc(kind, phase) * vol * (1.0 - t)
	return out


func gen_tones(freqs: Array, each: float, kind: String, vol: float) -> PackedFloat32Array:
	var per := int(RATE * each)
	var out := PackedFloat32Array()
	out.resize(per * freqs.size() + int(RATE * 0.05))
	var phase := 0.0
	for k in freqs.size():
		for i in per:
			var idx := k * per + i
			phase += float(freqs[k]) / RATE
			var env := 1.0 if k < freqs.size() - 1 else 1.0 - float(i) / per
			out[idx] = osc(kind, phase) * vol * env
	return out


func gen_groan(dur: float, base: float) -> PackedFloat32Array:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / n
		var f := base * (1.0 + 0.25 * sin(t * PI)) + sin(t * 40.0) * 4.0
		phase += f / RATE
		var raw := osc("saw", phase) * 0.7 + randf_range(-1.0, 1.0) * 0.25
		lp += (raw - lp) * 0.12
		var env := sin(t * PI) * (0.8 + 0.2 * sin(t * 23.0))
		out[i] = lp * env * 0.9
	return out
