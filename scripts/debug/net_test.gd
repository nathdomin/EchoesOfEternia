extends Control
## Teste de rede bruto (Gate 0).
## Hospeda ou entra numa partida ENet e troca ping/pong via @rpc,
## mostrando peer id e RTT. Nao faz parte do jogo final.
##
## Atalhos por linha de comando (editor: Debug > Customize Run Instances;
## .exe: EchoesOfEternia.exe -- --host  |  EchoesOfEternia.exe -- --join=192.168.0.10):
##   --host          hospeda na porta 7777
##   --join=IP       conecta no IP informado

const PORT := 7777
const MAX_CLIENTS := 3 # o host ja e o jogador 4

var _ip_edit: LineEdit
var _status: Label
var _log: TextEdit
var _ping_timer: Timer


func _ready() -> void:
	_build_ui()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_handle_cmdline()


# ---------- conexao ----------

func host() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		_write("ERRO ao hospedar (codigo %d). A porta %d ja esta em uso?" % [err, PORT])
		return
	multiplayer.multiplayer_peer = peer
	_write("Hospedando na porta UDP %d. Meu peer id = 1" % PORT)
	_set_status("HOST")


func join(ip: String) -> void:
	ip = ip.strip_edges()
	if ip.is_empty():
		_write("Informe o IP do host.")
		return
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		_write("ERRO ao criar cliente (codigo %d)." % err)
		return
	multiplayer.multiplayer_peer = peer
	_write("Conectando em %s:%d ..." % [ip, PORT])
	_set_status("CONECTANDO")


func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_ping_timer.stop()
	_write("Desconectado.")
	_set_status("OFFLINE")


# ---------- sinais ----------

func _on_peer_connected(id: int) -> void:
	_write("Peer conectado: %d" % id)
	if _ping_timer.is_stopped():
		_ping_timer.start()


func _on_peer_disconnected(id: int) -> void:
	_write("Peer desconectado: %d" % id)


func _on_connected_to_server() -> void:
	_write("Conectado! Meu peer id = %d" % multiplayer.get_unique_id())
	_set_status("CLIENTE")
	_check_version.rpc_id(1, GameVersion.VERSION)


func _on_connection_failed() -> void:
	_write("Falha na conexao. Confira IP, firewall (UDP %d) e se o host esta aberto." % PORT)
	leave()


func _on_server_disconnected() -> void:
	_write("O host caiu ou recusou a conexao.")
	leave()


# ---------- RPCs ----------

@rpc("any_peer", "call_remote", "reliable")
func _check_version(client_version: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if client_version != GameVersion.VERSION:
		_write("Peer %d recusado: versao %s (host = %s)" % [sender, client_version, GameVersion.VERSION])
		multiplayer.multiplayer_peer.disconnect_peer(sender)
	else:
		_write("Peer %d com versao OK (%s)" % [sender, client_version])


@rpc("any_peer", "call_remote", "unreliable")
func _ping(sent_msec: int) -> void:
	_pong.rpc_id(multiplayer.get_remote_sender_id(), sent_msec)


@rpc("any_peer", "call_remote", "unreliable")
func _pong(sent_msec: int) -> void:
	var rtt := Time.get_ticks_msec() - sent_msec
	_write("pong de %d: %d ms" % [multiplayer.get_remote_sender_id(), rtt])


func _send_ping() -> void:
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	if multiplayer.get_peers().is_empty():
		return
	_ping.rpc(Time.get_ticks_msec())


# ---------- utilitarios ----------

func _handle_cmdline() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for arg in args:
		if arg == "--host":
			host()
			return
		if arg.begins_with("--join="):
			var ip := arg.trim_prefix("--join=")
			_ip_edit.text = ip
			join(ip)
			return


func _local_ipv4() -> PackedStringArray:
	var out := PackedStringArray()
	for addr in IP.get_local_addresses():
		if addr.count(".") == 3 and not addr.begins_with("127.") and not addr.begins_with("169.254."):
			out.append(addr)
	return out


func _write(msg: String) -> void:
	var line := "[%s] %s" % [Time.get_time_string_from_system(), msg]
	print(line)
	_log.text += line + "\n"
	_log.scroll_vertical = _log.get_line_count()


func _set_status(role: String) -> void:
	_status.text = "Papel: %s   |   Versao: %s" % [role, GameVersion.VERSION]


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)

	var box := VBoxContainer.new()
	margin.add_child(box)

	var title := Label.new()
	title.text = "Echoes of Eternia - Teste de rede (Gate 0)"
	box.add_child(title)

	var ips := Label.new()
	var list := _local_ipv4()
	ips.text = "Meus IPv4: " + (", ".join(list) if not list.is_empty() else "(nenhum encontrado)")
	ips.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(ips)

	var row := HBoxContainer.new()
	box.add_child(row)
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.placeholder_text = "IP do host"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_ip_edit)
	_add_button(row, "Hospedar", host)
	_add_button(row, "Entrar", func() -> void: join(_ip_edit.text))
	_add_button(row, "Ping", _send_ping)
	_add_button(row, "Sair", leave)

	_status = Label.new()
	box.add_child(_status)
	_set_status("OFFLINE")

	_log = TextEdit.new()
	_log.editable = false
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_log)

	_ping_timer = Timer.new()
	_ping_timer.wait_time = 1.0
	_ping_timer.timeout.connect(_send_ping)
	add_child(_ping_timer)


func _add_button(parent: Node, text: String, callback: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(callback)
	parent.add_child(b)
