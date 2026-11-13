extends Node
## Autoload "NetworkManager" (E5): cria o servidor ou o cliente ENet a partir
## do Session, faz o aperto de mao (versao + nome) e mantem a lista de
## jogadores igual em todas as maquinas.
##
## Fluxo do cliente: conecta -> envia _register(versao, nome) -> o servidor
## valida -> todos recebem _sync_players e _notify_join.
## O servidor e a autoridade: so ele altera `players`.

signal connection_ready                 ## host iniciou / cliente foi aceito
signal connection_ended(reason: String) ## caiu, foi recusado ou saiu
signal player_joined(id: int, player_name: String)
signal player_left(id: int, player_name: String)
signal players_changed
signal system_message(text: String)

const MAX_CLIENTS := 3          ## o host ja e o jogador 4
const REGISTER_TIMEOUT := 5.0   ## segundos para o cliente se apresentar
const MAX_PLAYERS := MAX_CLIENTS + 1
## Tempo (ms) para considerar uma conexao perdida: min e max do ENet.
const TIMEOUT_MIN_MS := 3000
const TIMEOUT_MAX_MS := 6000

## peer_id -> { "name": String }
var players: Dictionary = {}
var is_online := false

var _accepted := false
var _end_reason := ""
## Versao enviada no aperto de mao. Em builds de debug pode ser trocada com
## --fake-version=X para testar a recusa por versao diferente.
var _version := GameVersion.VERSION


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	if OS.is_debug_build():
		for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
			if arg.begins_with("--fake-version="):
				_version = arg.trim_prefix("--fake-version=")


# ---------- API publica ----------

## Inicia a rede conforme o que foi escolhido no menu.
func start_from_session() -> Error:
	match Session.mode:
		Session.Mode.HOST:
			return host(Session.port)
		Session.Mode.JOIN:
			return join(Session.host_ip, Session.port)
	return OK


func host(port: int) -> Error:
	_reset()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_online = true
	_accepted = true
	players = {1: {"name": Session.player_name}}
	players_changed.emit()
	_log("Partida hospedada na porta %d" % port)
	connection_ready.emit()
	return OK


func join(ip: String, port: int) -> Error:
	_reset()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_set_timeout(peer, 1)
	is_online = true
	_log("Conectando em %s:%d..." % [ip, port])
	return OK


## Sai da partida (host encerra para todos; cliente so se desconecta).
func leave() -> void:
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_reset()


func is_host() -> bool:
	return is_online and multiplayer.is_server()


func player_name(id: int) -> String:
	return players.get(id, {}).get("name", "???")


# ---------- sinais do Godot ----------

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	_set_timeout(multiplayer.multiplayer_peer as ENetMultiplayerPeer, id)
	# Quem nao se apresentar a tempo e desconectado
	get_tree().create_timer(REGISTER_TIMEOUT).timeout.connect(func() -> void:
		if is_online and multiplayer.is_server() and not players.has(id) \
				and id in multiplayer.get_peers():
			multiplayer.multiplayer_peer.disconnect_peer(id))


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server() or not players.has(id):
		return
	var n := player_name(id)
	players.erase(id)
	_broadcast(_sync_players, [players])
	_broadcast(_notify_leave, [id, n], true)


func _on_connected_to_server() -> void:
	_register.rpc_id(1, _version, Session.player_name)


func _on_connection_failed() -> void:
	_finish("Não foi possível conectar em %s:%d. O host está aberto? A partida pode estar cheia." % [Session.host_ip, Session.port])


func _on_server_disconnected() -> void:
	if _end_reason.is_empty():
		_end_reason = "O host encerrou a partida" if _accepted else "O host recusou a conexão (partida cheia?)"
	_finish(_end_reason)


# ---------- RPCs ----------

## Cliente -> servidor: apresenta versao e nome.
@rpc("any_peer", "call_remote", "reliable")
func _register(version: String, wanted_name: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if version != GameVersion.VERSION:
		_rejected.rpc_id(id, "Versão diferente: o host usa %s e você %s. Atualize o jogo." % [GameVersion.VERSION, version])
		_kick_later(id)
		return
	if players.size() >= MAX_PLAYERS:
		_rejected.rpc_id(id, "A partida está cheia (%d jogadores)." % MAX_PLAYERS)
		_kick_later(id)
		return
	players[id] = {"name": _unique_name(wanted_name)}
	_broadcast(_sync_players, [players])
	_broadcast(_notify_join, [id, players[id].name], true)


## Servidor -> cliente: conexao recusada, com o motivo.
@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String) -> void:
	_end_reason = reason


## Servidor -> todos: lista oficial de jogadores.
@rpc("authority", "call_remote", "reliable")
func _sync_players(list: Dictionary) -> void:
	players = list
	players_changed.emit()
	if not _accepted and players.has(multiplayer.get_unique_id()):
		_accepted = true
		_log("Conectado como %s" % player_name(multiplayer.get_unique_id()))
		connection_ready.emit()


@rpc("authority", "call_remote", "reliable")
func _notify_join(id: int, n: String) -> void:
	if multiplayer.is_server():
		players_changed.emit()
	if id != multiplayer.get_unique_id():
		_log("%s entrou na partida" % n)
	player_joined.emit(id, n)


@rpc("authority", "call_remote", "reliable")
func _notify_leave(id: int, n: String) -> void:
	if multiplayer.is_server():
		players_changed.emit()
	_log("%s saiu da partida" % n)
	player_left.emit(id, n)


# ---------- auxiliares ----------

## Envia um RPC so para os jogadores ja aceitos (quem ainda esta no aperto de
## mao, ou foi recusado, nao recebe nada). Com `local`, executa tambem no host.
func _broadcast(method: Callable, args: Array, local := false) -> void:
	for id: int in players:
		if id != 1:
			method.rpc_id.callv([id] + args)
	if local:
		method.callv(args)


func _set_timeout(peer: ENetMultiplayerPeer, id: int) -> void:
	var p := peer.get_peer(id)
	if p:
		p.set_timeout(0, TIMEOUT_MIN_MS, TIMEOUT_MAX_MS)


func _kick_later(id: int) -> void:
	# Pequena espera para a mensagem de recusa chegar antes de desconectar
	await get_tree().create_timer(0.3).timeout
	if is_online and id in multiplayer.get_peers():
		multiplayer.multiplayer_peer.disconnect_peer(id)


func _unique_name(wanted: String) -> String:
	var base := wanted.strip_edges()
	if base.is_empty():
		base = "Jogador"
	var taken: Array = players.values().map(func(p: Dictionary) -> String: return p.name)
	var n := base
	var k := 2
	while n in taken:
		n = "%s %d" % [base, k]
		k += 1
	return n


func _finish(reason: String) -> void:
	var was_online := is_online
	leave()
	if was_online:
		connection_ended.emit(reason)


func _reset() -> void:
	players.clear()
	is_online = false
	_accepted = false
	_end_reason = ""


func _log(text: String) -> void:
	print("[Rede] ", text)
	system_message.emit(text)
