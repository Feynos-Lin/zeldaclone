extends Node
## Background music: the eerie forest theme on a loop, on its own bus so it can
## be muffled indoors. Volume is a setting (Off / Low / Medium / High).

const TRACK := "res://assets/music/forest.ogg"
const SAVE_PATH := "user://settings.cfg"
const LEVELS := [-80.0, -18.0, -11.0, -6.0]
const LEVEL_NAMES := ["Off", "Low", "Medium", "High"]

var player: AudioStreamPlayer
var level := 2
var indoors := false
var bus := -1
var lowpass: AudioEffectLowPassFilter
var cutoff := 20000.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		level = clampi(int(cfg.get_value("audio", "music", level)), 0, LEVELS.size() - 1)
	bus = AudioServer.bus_count
	AudioServer.add_bus(bus)
	AudioServer.set_bus_name(bus, "Music")
	AudioServer.set_bus_send(bus, "Master")
	lowpass = AudioEffectLowPassFilter.new()
	lowpass.cutoff_hz = cutoff
	AudioServer.add_bus_effect(bus, lowpass)
	player = AudioStreamPlayer.new()
	player.bus = "Music"
	if ResourceLoader.exists(TRACK):
		var s: AudioStream = load(TRACK)
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		player.stream = s
	add_child(player)
	player.volume_db = LEVELS[level]
	if level > 0 and player.stream != null:
		player.play()


func _process(delta: float) -> void:
	var want := 900.0 if indoors else 20000.0
	cutoff = lerpf(cutoff, want, minf(1.0, delta * 3.0))
	lowpass.cutoff_hz = cutoff
	var vol: float = LEVELS[level] - (3.0 if indoors else 0.0)
	player.volume_db = lerpf(player.volume_db, vol, minf(1.0, delta * 3.0)) if level > 0 else -80.0
	if level > 0 and not player.playing and player.stream != null:
		player.play()
	elif level == 0 and player.playing:
		player.stop()


func cycle(dir: int) -> void:
	level = posmod(level + dir, LEVELS.size())
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("audio", "music", level)
	cfg.save(SAVE_PATH)


func level_name() -> String:
	return LEVEL_NAMES[level]
