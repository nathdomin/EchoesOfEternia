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
## Cliente: o servidor levou o personagem para outra zona (E23).
signal zone_changed(zone: String, pos: Vector2)
## Servidor: o avatar do jogador foi recriado (troca de zona).
signal avatar_replaced(id: int)

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
var _travel_pending := false  ## cliente: esperando a resposta de uma viagem


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
	# Ponto inicial em coordenadas LOCAIS da zona: no servidor as zonas ficam
	# afastadas (x = 0, 20000, 40000) e a posicao global apontava para fora
	# do mapa (renascer na floresta/caverna jogava o personagem no vazio).
	var spawn_point := map.get_node("SpawnPoint") as Node2D
	_zones[zone] = {"bounds": map.get_bounds(), "spawn": spawn_point.position,
			"players": map.get_node("Players"), "map": map}
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


## Zona do jogador, ou "" se offline ou ainda carregando o jogo.
func zone_of(id: int) -> String:
	if not _online.has(id) or not _online[id].ready:
		return ""
	return _online[id].data.zone


## Jogadores com o jogo carregado na zona.
func players_in_zone(zone: String) -> Array[int]:
	var out: Array[int] = []
	for id: int in _online:
		if _online[id].ready and _online[id].data.zone == zone:
			out.append(id)
	return out


## Dados salvos do personagem (o mesmo dicionario que vai para o disco).
## Outros sistemas (PlayerData) alteram e chamam mark_dirty().
func data_of(id: int) -> Dictionary:
	return _online[id].data if _online.has(id) else {}


func mark_dirty(id: int) -> void:
	if _online.has(id):
		_online[id].dirty = true


## Ultima posicao validada do jogador.
func position_of(id: int) -> Vector2:
	if not _online.has(id):
		return Vector2.INF
	return Vector2(_online[id].data.x, _online[id].data.y)


func avatar_of(id: int) -> RemotePlayer:
	if not _online.has(id) or not is_instance_valid(_online[id].avatar):
		return null
	return _online[id].avatar


## Vida salva no personagem (-1 = cheia).
func saved_hp(id: int) -> int:
	return int(_online[id].data.get("hp", -1)) if _online.has(id) else -1


## Servidor move o jogador (renascimento). O cliente e avisado pelo Combat.
func teleport(id: int, pos: Vector2) -> void:
	if not _online.has(id):
		return
	var c: Dictionary = _online[id]
	c.data.x = pos.x
	c.data.y = pos.y
	c.budget = MAX_BUDGET
	c.last_ms = Time.get_ticks_msec()
	c.dirty = true
	var avatar := avatar_of(id)
	if avatar:
		avatar.position = pos
		avatar.net_position = pos


# ---------- API do cliente ----------

func report_position(pos: Vector2, facing: Vector2i) -> void:
	if NetworkManager.is_logged_in():
		_report_position.rpc_id(1, pos, facing)


## O player encostou numa passagem (ZoneExit) da zona atual.
func request_travel(exit_name: String) -> void:
	if NetworkManager.is_logged_in() and not _travel_pending:
		_travel_pending = true
		_request_travel.rpc_id(1, exit_name)


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
	var avatar := avatar_of(id)
	if avatar:
		c.data.hp = avatar.health.hp
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
	if Combat.is_dead(id):
		return  # morto nao anda; o renascimento reposiciona
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


@rpc("any_peer", "call_remote", "reliable")
func _request_travel(exit_name: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not _online.has(id) or Combat.is_dead(id) or not exit_name.is_valid_identifier():
		return
	var c: Dictionary = _online[id]
	var data: Dictionary = c.data
	var exit := (_zones[data.zone].map as Node).get_node_or_null("Exits/" + exit_name) as ZoneExit
	if exit == null or not _zones.has(exit.target_zone):
		_travel_denied.rpc_id(id)
		return
	# O servidor confere se o jogador esta mesmo na passagem (com folga)
	if not exit.rect().grow(24.0).has_point(Vector2(data.x, data.y)):
		_travel_denied.rpc_id(id)
		return
	var target: Dictionary = _zones[exit.target_zone]
	var entrance := (target.map as Node).get_node_or_null("Entrances/" + exit.target_entrance) as Node2D
	var pos: Vector2 = entrance.position if entrance else target.spawn
	move_to_zone(id, exit.target_zone, pos)


## Zona inicial (onde se renasce) e o ponto de partida dela (local).
func home_zone() -> String:
	return _default_zone


func home_position() -> Vector2:
	return _zones[_default_zone].spawn


## Servidor: leva o jogador para `zone` em `pos` (viagem ou renascimento):
## recria o avatar na zona nova e avisa o cliente para trocar o mapa.
func move_to_zone(id: int, zone: String, pos: Vector2) -> void:
	if not _online.has(id) or not _zones.has(zone):
		return
	var c: Dictionary = _online[id]
	var data: Dictionary = c.data
	var old: RemotePlayer = c.avatar
	data.zone = zone
	data.x = pos.x
	data.y = pos.y
	c.ready = false
	c.budget = MAX_BUDGET
	c.last_ms = Time.get_ticks_msec()
	c.dirty = true
	# Avatar novo na zona nova (o spawner tira da zona antiga e poe na nova)
	var avatar := _spawn_avatar(id, data)
	if is_instance_valid(old):
		avatar.health.max_hp = old.health.max_hp
		avatar.health.hp = old.health.hp
		avatar.level = old.level
		old.queue_free()
	c.avatar = avatar
	avatar_replaced.emit(id)
	_log("%s foi para %s" % [data.name, data.zone])
	_zone_changed.rpc_id(id, data.zone, pos)


@rpc("authority", "call_remote", "reliable")
func _zone_changed(zone: String, pos: Vector2) -> void:
	_travel_pending = false
	spawn.zone = zone
	spawn.position = pos
	zone_changed.emit(zone, pos)


@rpc("authority", "call_remote", "reliable")
func _travel_denied() -> void:
	_travel_pending = false


## Servidor -> cliente: volta para a ultima posicao valida.
@rpc("authority", "call_remote", "reliable")
func _correct_position(pos: Vector2) -> void:
	position_corrected.emit(pos)


func _log(text: String) -> void:
	print("[%s] [Personagem] %s" % [Time.get_time_string_from_system(), text])
