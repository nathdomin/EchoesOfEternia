extends Node
## Autoload "GameAudio" (Fase 6): musica por zona (com troca suave) e efeitos
## sonoros. So toca no cliente; no servidor dedicado tudo vira no-op.
##
## Barramentos: "Music" e "Sfx" (criados aqui), volumes salvos em
## user://client.cfg (secao "audio"). Qualquer botao que entra na arvore
## ganha o som de clique automaticamente.
##
## Sons: arquivos em res://audio/sfx/<nome>.wav (gerados por
## tools/gen_sfx.py). `play("hit")` toca em volume cheio; `play_at("hit", pos)`
## baixa o volume com a distancia ate o jogador local.

const SFX_DIR := "res://audio/sfx/%s.wav"
const MUSIC_FADE := 1.2
## Volume base da musica (as faixas do pacote sao altas).
const MUSIC_DB := -14.0
## Distancia (px) a partir da qual um som do mundo nao e mais ouvido.
const HEAR_DISTANCE := 300.0
const POOL_SIZE := 12
## Gate 5: ajuste de volume por faixa (dB), medido para todas soarem iguais
## (alvo -20 dB RMS). Chave = nome do arquivo sem extensao.
const MUSIC_GAIN := {"17 - Fight": 3.9, "21 - Dungeon": -1.0, "36 - Village": 1.2, "37 - Dark Forest": -4.5}

var music_volume := 0.7
var sfx_volume := 0.8

var _enabled := false
var _cache: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_path := ""
var _amb: AudioStreamPlayer
var _amb_oneshots: Array = []
var _amb_every := Vector2(4, 9)
var _amb_next := 0.0
## Evita o mesmo som repetido no mesmo quadro (ex.: varios monstros atingidos).
var _last_played: Dictionary = {}


func _ready() -> void:
	_enabled = not Session.is_server_mode() and DisplayServer.get_name() != "headless"
	if not _enabled:
		return
	for bus in ["Music", "Sfx"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = &"Sfx"
		add_child(p)
		_pool.append(p)
	_music_a = _new_music_player()
	_music_b = _new_music_player()
	_amb = AudioStreamPlayer.new()
	_amb.bus = &"Sfx"
	_amb.volume_db = -60.0
	add_child(_amb)
	_load_prefs()
	_apply_volumes()
	get_tree().node_added.connect(_on_node_added)


func _new_music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = &"Music"
	p.volume_db = -60.0
	add_child(p)
	return p


# ---------- efeitos ----------

func play(sound: String, pitch_jitter := 0.06, volume := 1.0) -> void:
	if not _enabled or volume <= 0.01:
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(sound, -1000)) < 40:
		return
	_last_played[sound] = now
	var stream := _stream(sound)
	if stream == null:
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = stream
	p.volume_db = linear_to_db(volume)
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


## Som que acontece em `pos` (coordenadas do mapa): mais baixo se longe.
func play_at(sound: String, pos: Vector2, pitch_jitter := 0.08) -> void:
	if not _enabled:
		return
	var listener: Variant = _listener_position()
	var d: float = pos.distance_to(listener) if listener != null else 0.0
	if d > HEAR_DISTANCE:
		return
	play(sound, pitch_jitter, clampf(1.0 - d / HEAR_DISTANCE, 0.15, 1.0))


func _stream(sound: String) -> AudioStream:
	if not _cache.has(sound):
		var path := SFX_DIR % sound
		_cache[sound] = load(path) if sound.is_valid_identifier() and ResourceLoader.exists(path) else null
	return _cache[sound]


func _listener_position() -> Variant:
	var scene := get_tree().current_scene
	var player := scene.get_node_or_null("World/Player") as Node2D if scene else null
	return player.global_position if player else null


func _on_node_added(node: Node) -> void:
	if node is BaseButton and not node.has_meta("silent"):
		(node as BaseButton).pressed.connect(play.bind("click", 0.0, 1.0))


# ---------- musica ----------

## Troca a musica com fade. Mesma faixa = nada muda. "" = silencio.
func play_music(path: String) -> void:
	if not _enabled or path == _music_path:
		return
	_music_path = path
	var old := _music_a
	_music_a = _music_b
	_music_b = old
	var t := create_tween().set_parallel()
	t.tween_property(old, "volume_db", -60.0, MUSIC_FADE)
	t.chain().tween_callback(old.stop)
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStream
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_music_a.stream = stream
	_music_a.volume_db = -40.0
	_music_a.play()
	var target := MUSIC_DB + float(MUSIC_GAIN.get(path.get_file().get_basename(), 0.0))
	create_tween().tween_property(_music_a, "volume_db", target, MUSIC_FADE)


func stop_music() -> void:
	play_music("")
	play_ambience({})


# ---------- ambiente (Gate 5) ----------

## Som de fundo da zona (Zones.AMBIENCE). {} = silencio.
func play_ambience(cfg: Dictionary) -> void:
	if not _enabled:
		return
	_amb_oneshots = cfg.get("oneshots", [])
	_amb_every = cfg.get("every", Vector2(4, 9))
	_amb_next = randf_range(_amb_every.x, _amb_every.y)
	var loop: String = cfg.get("loop", "")
	var stream := _stream(loop) as AudioStreamWAV if loop != "" else null
	if stream == null:
		create_tween().tween_property(_amb, "volume_db", -60.0, MUSIC_FADE)
		return
	if stream.loop_mode != AudioStreamWAV.LOOP_FORWARD:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	if _amb.stream != stream:
		_amb.stream = stream
		_amb.volume_db = -40.0
		_amb.play()
	create_tween().tween_property(_amb, "volume_db", float(cfg.get("db", 0.0)), MUSIC_FADE)


func _process(delta: float) -> void:
	if not _enabled or _amb_oneshots.is_empty():
		return
	_amb_next -= delta
	if _amb_next <= 0.0:
		_amb_next = randf_range(_amb_every.x, _amb_every.y)
		play(_amb_oneshots[randi() % _amb_oneshots.size()], 0.1, randf_range(0.45, 1.0))


# ---------- volumes ----------

func set_volumes(music: float, sfx: float) -> void:
	music_volume = clampf(music, 0.0, 1.0)
	sfx_volume = clampf(sfx, 0.0, 1.0)
	_apply_volumes()
	var cfg := ConfigFile.new()
	cfg.load(Session.PREFS_PATH)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.save(Session.PREFS_PATH)


func _apply_volumes() -> void:
	for pair in [["Music", music_volume], ["Sfx", sfx_volume]]:
		var i := AudioServer.get_bus_index(pair[0])
		if i != -1:
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(pair[1], 0.0001)))
			AudioServer.set_bus_mute(i, pair[1] <= 0.001)


func _load_prefs() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(Session.PREFS_PATH) != OK:
		return
	music_volume = float(cfg.get_value("audio", "music", music_volume))
	sfx_volume = float(cfg.get_value("audio", "sfx", sfx_volume))
