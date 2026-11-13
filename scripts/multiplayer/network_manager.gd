extends Node
## Autoload "NetworkManager" (E5/E6): servidor dedicado ou cliente ENet,
## aperto de mao (versao + nome) e lista de jogadores igual em todas as maquinas.
##
## O servidor e dedicado (E6): nao e um jogador. Ele so existe no peer 1 e
## nunca aparece em `players`.
##
## Fluxo do cliente: conecta -> envia _register(versao, nome) -> o servidor
## valida -> todos recebem _sync_players e _notify_join.
## O servidor e a autoridade: so ele altera `players`.

signal connection_ready                 ## servidor iniciou / cliente foi aceito
signal connection_ended(reason: String) ## caiu, foi recusado ou saiu
signal player_joined(id: int, player_name: String)
signal player_left(id: int, player_name: String)
signal players_changed
signal system_message(text: String)

const DEFAULT_MAX_PLAYERS := 16
const MAX_NAME_LENGTH := 16
const REGISTER_TIMEOUT := 5.0   ## segundos para o cliente se apresentar
## Tempo (ms) para considerar uma conexao perdida: min e max do ENet.
const TIMEOUT_MIN_MS := 3000
const TIMEOUT_MAX_MS := 6000

## peer_id -> { "name": String }
var players: Dictionary = {}
var is_online := false
## Vagas do servidor (configuravel com --max-players=N).
var max_players := DEFAULT_MAX_PLAYERS

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

## Conecta ao servidor escolhido no menu.
func start_from_session() -> Error:
	if Session.mode == Session.Mode.JOIN:
		return join(Session.host_ip, Session.port)
	return OK


## Inicia o servidor dedicado (sem jogador proprio).
func start_server(port: int, p_max_players: int) -> Error:
	_reset()
	max_players = p_max_players
	var peer := ENetMultiplayerPeer.new()
	# Uma vaga a mais no ENet: quem chega com o servidor cheio recebe a
	# mensagem "servidor cheio" em vez de um erro generico de conexao.
	var err := peer.create_server(port, max_players + 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_online = true
	_accepted = true
	players_changed.emit()
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


## Sai do servidor (no servidor, encerra para todos).
func leave() -> void:
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_reset()


func is_server() -> bool:
	return is_online and multiplayer != null and multiplayer.is_server()


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
	_finish("Não foi possível conectar em %s:%d. O servidor está ligado e o endereço está certo?" % [Session.host_ip, Session.port])


func _on_server_disconnected() -> void:
	if _end_reason.is_empty():
		_end_reason = "O servidor foi desligado ou a conexão caiu" if _accepted else "O servidor recusou a conexão"
	_finish(_end_reason)


# ---------- RPCs ----------

## Cliente -> servidor: apresenta versao e nome.
@rpc("any_peer", "call_remote", "reliable")
func _register(version: String, wanted_name: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		return  # ja registrado: ignora tentativa de trocar de nome
	if version != GameVersion.VERSION:
		_rejected.rpc_id(id, "Versão diferente: o servidor usa %s e você %s. Atualize o jogo." % [GameVersion.VERSION, version])
		_kick_later(id)
		return
	if players.size() >= max_players:
		_rejected.rpc_id(id, "O servidor está cheio (%d jogadores). Tente mais tarde." % max_players)
		_kick_later(id)
		return
	players[id] = {"name": _unique_name(_sanitize_name(wanted_name))}
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
		_log("%s entrou no mundo" % n)
	player_joined.emit(id, n)


@rpc("authority", "call_remote", "reliable")
func _notify_leave(id: int, n: String) -> void:
	if multiplayer.is_server():
		players_changed.emit()
	_log("%s saiu do mundo" % n)
	player_left.emit(id, n)


# ---------- auxiliares ----------

## Envia um RPC so para os jogadores ja aceitos (quem ainda esta no aperto de
## mao, ou foi recusado, nao recebe nada). Com `local`, executa tambem no servidor.
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


## O servidor nunca confia no nome vindo do cliente: remove caracteres de
## controle, junta espacos repetidos e corta no tamanho maximo.
func _sanitize_name(raw: String) -> String:
	var out := ""
	for ch in raw.left(64):
		out += ch if ch.unicode_at(0) >= 32 and ch.unicode_at(0) != 127 else " "
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out.strip_edges().left(MAX_NAME_LENGTH).strip_edges()


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
	print("[%s] [Rede] %s" % [Time.get_time_string_from_system(), text])
	system_message.emit(text)
