extends Node
## Autoload "Characters" (E8/E9): personagem salvo e presenca no mundo.
##
## Servidor:
##  - no login carrega (ou cria) o personagem da conta e envia ao cliente a
##    zona, a posicao e a direcao onde ele parou;
##  - recebe a posicao do cliente (~10x por segundo enquanto anda) e confere
##    a velocidade e os limites da zona; movimento impossivel e desfeito;
##  - salva ao sair, a cada AUTOSAVE_SEC e quando o servidor e desligado;
##  - (E9) cria um RemotePlayer por jogador no `Players` da zona. O
##    MultiplayerSpawner/Synchronizer leva esse avatar so para quem esta na
##    mesma zona e ja avisou que carregou o jogo (notify_ready), e nunca para
##    o dono. Quem entra depois recebe todos os que ja estao la (late join).
## Cliente:
##  - guarda `spawn` (recebido antes do login ser aceito) para a cena do jogo;
##  - envia a posicao com report_position();
##  - avisa com notify_ready() quando a cena do jogo carregou.

signal position_corrected(pos: Vector2)

const AUTOSAVE_SEC := 60.0
## Folga sobre a velocidade do Player (lag, quadros irregulares).
const SPEED_SLACK := 1.25
## Distancia maxima acumulada sem reportar (evita "guardar" movimento parado).
const MAX_BUDGET := Player.SPEED * 0.5
const TOLERANCE_PX := 4.0
const FACING_VECTORS := {"down": Vector2i.DOWN, "up": Vector2i.UP, "left": Vector2i.LEFT, "right": Vector2i.RIGHT}
const REMOTE_PLAYER := preload("res://scenes/characters/remote_player.tscn")

## Cliente: { "zone", "position": Vector2, "facing": Vector2i, "skin", "is_new" }
var spawn: Dictionary = {}

# ---------- so no servidor ----------
var _store: CharacterStore
## zona -> { "bounds": Rect2, "spawn": Vector2, "players": Node2D }
var _zones: Dictionary = {}
## peer_id -> { "data": Dictionary, "budget": float, "last_ms": int,
##              "since_ms": int, "dirty": bool, "warned_ms": int, "corrected_ms": int,
##              "ready": bool, "avatar": RemotePlayer }
var _online: Dictionary = {}
var _default_zone := ""
var _autosave: Timer


func _ready() -> void:
	NetworkManager.account_logged_in.connect(_on_account_logged_in)
	NetworkManager.account_logged_out.connect(_on_account_logged_out)
	NetworkManager.connection_ended.connect(func(_r: String) -> void: spawn.clear())


# ---------- API do servidor ----------

func start_server(store: CharacterStore) -> void:
	_store = store
	_online.clear()
	_autosave = Timer.new()
	_autosave.wait_time = AUTOSAVE_SEC
	_autosave.autostart = true
	_autosave.timeout.connect(save_all.bind(false))
	add_child(_autosave)


## O servidor registra cada zona carregada (cena com get_bounds(),
## get_spawn_position() e um no "Players"). A primeira e a zona inicial.
func register_zone(zone: String, map: Node) -> void:
	_zones[zone] = {"bounds": map.get_bounds(), "spawn": map.get_spawn_position(), "players": map.get_node("Players")}
	if _default_zone.is_empty():
		_default_zone = zone


## Salva os personagens online. `all` = inclusive os que nao mudaram.
## Retorna quantos foram salvos.
func save_all(all := true) -> int:
	var n := 0
	for id: int in _online:
		if all or _online[id].dirty:
			_save(id)
			n += 1
	return n


func online_count() -> int:
	return _online.size()


# ---------- API do cliente ----------

func report_position(pos: Vector2, facing: Vector2i) -> void:
	if NetworkManager.is_logged_in():
		_report_position.rpc_id(1, pos, facing)


## A cena do jogo carregou: o servidor pode mandar os outros jogadores.
func notify_ready() -> void:
	if NetworkManager.is_logged_in():
		_client_ready.rpc_id(1)


# ---------- servidor: login e saida ----------

func _on_account_logged_in(id: int, account_key: String, display_name: String) -> void:
	if _store == null:
		return
	var zone := _default_zone
	var r := _store.load_or_create(account_key, display_name, zone, _zones[zone].spawn)
	var data: Dictionary = r.data
	# Zona que nao existe mais ou posicao fora do mapa: volta ao inicio
	if not _zones.has(data.zone) or not _zones[data.zone].bounds.has_point(Vector2(data.x, data.y)):
		data.zone = zone
		data.x = _zones[zone].spawn.x
		data.y = _zones[zone].spawn.y
	var now := Time.get_ticks_msec()
	_online[id] = {"data": data, "budget": MAX_BUDGET, "last_ms": now, "since_ms": now, "dirty": r.is_new,
			"warned_ms": -10000, "corrected_ms": -10000, "ready": false, "avatar": _spawn_avatar(id, data)}
	if r.is_new:
		_store.save(data)
	_log("%s %s em %s (%d, %d)" % [display_name, "criou o personagem" if r.is_new else "carregado",
			data.zone, int(data.x), int(data.y)])
	# Vai antes da lista de jogadores (mesmo canal confiavel = chega antes):
	# quando o cliente souber que foi aceito, ja sabe onde aparecer.
	_spawn_character.rpc_id(id, data.zone, Vector2(data.x, data.y), FACING_VECTORS[data.facing], data.skin, r.is_new)


func _on_account_logged_out(id: int, _account_key: String) -> void:
	if not _online.has(id):
		return
	_save(id)
	var avatar: Node = _online[id].avatar
	if is_instance_valid(avatar):
		avatar.queue_free()  # o spawner remove dos outros clientes
	_online.erase(id)


func _spawn_avatar(id: int, data: Dictionary) -> RemotePlayer:
	var avatar := REMOTE_PLAYER.instantiate() as RemotePlayer
	avatar.name = str(id)
	avatar.display_name = data.name
	avatar.skin = data.skin
	avatar.net_position = Vector2(data.x, data.y)
	avatar.facing = FACING_VECTORS[data.facing]
	(avatar.get_node("Sync") as MultiplayerSynchronizer).add_visibility_filter(_can_see.bind(id))
	_zones[data.zone].players.add_child(avatar, true)
	return avatar


## Filtro de visibilidade: `peer` recebe o avatar de `owner_id`?
## So se estiver na mesma zona, ja tiver carregado o jogo e nao for o dono.
func _can_see(peer: int, owner_id: int) -> bool:
	if peer == owner_id or not _online.has(peer) or not _online.has(owner_id):
		return false
	var viewer: Dictionary = _online[peer]
	return viewer.ready and viewer.data.zone == _online[owner_id].data.zone


func _save(id: int) -> void:
	var c: Dictionary = _online[id]
	var now := Time.get_ticks_msec()
	c.data.play_time = int(c.data.play_time) + (now - c.since_ms) / 1000
	c.since_ms = now - (now - c.since_ms) % 1000
	if _store.save(c.data) == OK:
		c.dirty = false


# ---------- RPCs ----------

## Servidor -> cliente: onde o personagem aparece.
@rpc("authority", "call_remote", "reliable")
func _spawn_character(zone: String, pos: Vector2, facing: Vector2i, skin: String, is_new: bool) -> void:
	spawn = {"zone": zone, "position": pos, "facing": facing, "skin": skin, "is_new": is_new}


## Cliente -> servidor: a cena do jogo (com os spawners) ja existe.
@rpc("any_peer", "call_remote", "reliable")
func _client_ready() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if _online.has(id):
		_online[id].ready = true


## Cliente -> servidor: posicao atual. O servidor so aceita o que daria para
## andar desde o ultimo aviso; senao devolve a ultima posicao valida.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _report_position(pos: Vector2, facing: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not _online.has(id):
		return
	var c: Dictionary = _online[id]
	var data: Dictionary = c.data
	var now := Time.get_ticks_msec()
	c.budget = minf(c.budget + Player.SPEED * SPEED_SLACK * (now - c.last_ms) / 1000.0, MAX_BUDGET)
	c.last_ms = now
	var current := Vector2(data.x, data.y)
	var dist := current.distance_to(pos)
	var bounds: Rect2 = _zones[data.zone].bounds
	if not pos.is_finite() or not bounds.has_point(pos) or dist > c.budget + TOLERANCE_PX:
		if now - c.warned_ms > 5000:
			c.warned_ms = now
			_log("Movimento recusado de %s: %.0f px (permitido %.0f)" % [data.name, dist, c.budget + TOLERANCE_PX])
		# Os avisos que ja estavam a caminho tambem serao recusados: uma
		# correcao basta ate o cliente recebe-la.
		if now - c.corrected_ms > 250:
			c.corrected_ms = now
			_correct_position.rpc_id(id, current)
		return
	c.budget = maxf(c.budget - dist, 0.0)
	data.x = pos.x
	data.y = pos.y
	var f: Variant = FACING_VECTORS.find_key(facing)
	if f != null:
		data.facing = f
	var avatar: RemotePlayer = c.avatar
	avatar.position = pos
	avatar.net_position = pos
	avatar.facing = FACING_VECTORS[data.facing]
	c.dirty = true


## Servidor -> cliente: volta para a ultima posicao valida.
@rpc("authority", "call_remote", "reliable")
func _correct_position(pos: Vector2) -> void:
	position_corrected.emit(pos)


func _log(text: String) -> void:
	print("[%s] [Personagem] %s" % [Time.get_time_string_from_system(), text])
