extends Node
## Autoload "Social" (E19 chat, E20 grupo).
##
## Chat: o cliente manda o texto; o servidor limpa (sem caracteres de
## controle, ate MAX_CHAT), limita a frequencia e repassa:
##   texto normal  -> todos (canal "global")
##   /g texto      -> so o grupo (canal "grupo")
##   /z texto      -> so quem esta na mesma zona (canal "zona")
##   /w Nome texto -> sussurro para um jogador (canais "de"/"para"); /r responde
##   /quem         -> lista de quem esta online (nome, nivel, zona)
##   /convidar Nome, /aceitar, /recusar, /sair, /ajuda -> comandos de grupo
## Grupo: ate MAX_PARTY jogadores, existe enquanto estao online. O servidor
## manda a cada membro a lista do grupo (nome, nivel, vida, zona) quando muda.

signal chat_received(channel: String, author: String, text: String)
signal party_changed(members: Array)  ## cliente: [{id, name, level, hp, max_hp, zone, leader}]
signal invite_received(from_name: String)

const MAX_CHAT := 120
const RATE_COUNT := 5        ## mensagens...
const RATE_WINDOW_MS := 5000 ## ...a cada 5 s
const MAX_PARTY := 4
const INVITE_SECONDS := 60
const PARTY_PUSH_INTERVAL := 0.5

## Cliente: membros do proprio grupo (vazio = sem grupo).
var party: Array = []

# ---------- so no servidor ----------
var _chat_times: Dictionary = {}     ## peer -> Array[int] (ms)
var _party_of: Dictionary = {}       ## peer -> party_id
var _parties: Dictionary = {}        ## party_id -> {"leader": int, "members": Array[int]}
var _invites: Dictionary = {}        ## convidado -> {"from": int, "until": int}
var _next_party := 1
var _push_timer := 0.0
var _last_party_state: Dictionary = {}  ## party_id -> ultima lista enviada
var _last_whisper: Dictionary = {}   ## peer -> quem sussurrou por ultimo (para /r)


func _ready() -> void:
	NetworkManager.account_logged_out.connect(func(id: int, _k: String) -> void:
		_chat_times.erase(id)
		_last_whisper.erase(id)
		_invites.erase(id)
		_leave_party(id, false, false))  # desconectou: nao manda nada para ele
	NetworkManager.connection_ended.connect(func(_r: String) -> void:
		party = []
		party_changed.emit(party))
	NetworkManager.system_message.connect(func(t: String) -> void: chat_received.emit("sistema", "", t))


# ---------- API do servidor ----------

## Membros do grupo do jogador (vazio se nao tem grupo).
func party_members(id: int) -> Array[int]:
	var out: Array[int] = []
	if _party_of.has(id):
		for m: int in _parties[_party_of[id]].members:
			out.append(m)
	return out


# ---------- API do cliente ----------

func send_chat(text: String) -> void:
	text = text.strip_edges()
	if not text.is_empty() and NetworkManager.is_logged_in():
		_chat.rpc_id(1, text)


func invite(player_name: String) -> void:
	send_chat("/convidar " + player_name)


# ---------- servidor ----------

func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server() or _parties.is_empty():
		return
	_push_timer += delta
	if _push_timer < PARTY_PUSH_INTERVAL:
		return
	_push_timer = 0.0
	# Vida/zona dos membros mudam o tempo todo: reenvia os grupos que mudaram
	for pid in _parties.keys():
		_push_party(pid)


func _clean(text: String) -> String:
	var out := ""
	for ch in text.left(MAX_CHAT * 2):
		out += ch if ch.unicode_at(0) >= 32 and ch.unicode_at(0) != 127 else " "
	return out.strip_edges().left(MAX_CHAT)


func _rate_ok(id: int) -> bool:
	var now := Time.get_ticks_msec()
	var times: Array = _chat_times.get(id, []).filter(func(t: int) -> bool: return now - t < RATE_WINDOW_MS)
	if times.size() >= RATE_COUNT:
		_chat_times[id] = times
		return false
	times.append(now)
	_chat_times[id] = times
	return true


@rpc("any_peer", "call_remote", "reliable")
func _chat(raw: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not NetworkManager.players.has(id):
		return
	var text := _clean(raw)
	if text.is_empty():
		return
	if not _rate_ok(id):
		NetworkManager.send_system_message(id, "Calma! Espere um pouco antes de mandar outra mensagem.")
		return
	var author := NetworkManager.player_name(id)
	if text.begins_with("/"):
		_command(id, text)
		return
	for pid: int in NetworkManager.players:
		_chat_line.rpc_id(pid, "global", author, text)


func _command(id: int, text: String) -> void:
	var parts := text.split(" ", false, 1)
	var cmd := parts[0].to_lower()
	var arg := parts[1].strip_edges() if parts.size() > 1 else ""
	match cmd:
		"/g", "/grupo":
			if not _party_of.has(id):
				NetworkManager.send_system_message(id, "Você não está em um grupo.")
			elif not arg.is_empty():
				for m in party_members(id):
					_chat_line.rpc_id(m, "grupo", NetworkManager.player_name(id), arg)
		"/z", "/zona":
			if not arg.is_empty():
				var author := NetworkManager.player_name(id)
				for pid in Characters.players_in_zone(Characters.zone_of(id)):
					_chat_line.rpc_id(pid, "zona", author, arg)
		"/w", "/s", "/sussurrar":
			var wp := arg.split(" ", false, 1)
			if wp.size() < 2:
				NetworkManager.send_system_message(id, "Use: /w Nome mensagem")
			else:
				_whisper(id, _find_player(wp[0]), wp[0], wp[1])
		"/r", "/responder":
			if arg.is_empty():
				pass
			elif not _last_whisper.has(id) or not NetworkManager.players.has(_last_whisper[id]):
				NetworkManager.send_system_message(id, "Ninguém para responder.")
			else:
				_whisper(id, _last_whisper[id], "", arg)
		"/quem", "/who":
			_who(id)
		"/convidar", "/invite":
			_invite(id, arg)
		"/aceitar":
			_accept(id)
		"/recusar":
			if _invites.has(id):
				NetworkManager.send_system_message(_invites[id].from, "%s recusou o convite." % NetworkManager.player_name(id))
				_invites.erase(id)
		"/sair":
			_leave_party(id, true)
		_:
			NetworkManager.send_system_message(id, "Comandos: /g grupo, /z zona, /w Nome (sussurro), /r responder, /quem, /convidar Nome, /aceitar, /recusar, /sair")


func _whisper(id: int, target: int, typed_name: String, text: String) -> void:
	if target == 0:
		NetworkManager.send_system_message(id, "Jogador \"%s\" não está online." % typed_name.left(16))
		return
	if target == id:
		return
	_last_whisper[target] = id
	_chat_line.rpc_id(target, "de", NetworkManager.player_name(id), text)
	_chat_line.rpc_id(id, "para", NetworkManager.player_name(target), text)


func _who(id: int) -> void:
	var names: Array[String] = []
	for pid: int in NetworkManager.players:
		var data := Characters.data_of(pid)
		if data.is_empty():
			continue
		names.append("%s (Nv %d, %s)" % [NetworkManager.player_name(pid), int(data.level), Zones.display_name(String(data.zone))])
	names.sort()
	NetworkManager.send_system_message(id, "Online (%d): %s" % [names.size(), ", ".join(names)])


func _find_player(p_name: String) -> int:
	for pid: int in NetworkManager.players:
		if NetworkManager.player_name(pid).to_lower() == p_name.to_lower():
			return pid
	return 0


func _invite(id: int, p_name: String) -> void:
	var target := _find_player(p_name)
	if target == 0:
		NetworkManager.send_system_message(id, "Jogador \"%s\" não está online." % p_name.left(16))
		return
	if target == id:
		return
	if _party_of.has(target):
		NetworkManager.send_system_message(id, "%s já está em um grupo." % NetworkManager.player_name(target))
		return
	if _party_of.has(id):
		var p: Dictionary = _parties[_party_of[id]]
		if p.leader != id:
			NetworkManager.send_system_message(id, "Só o líder pode convidar.")
			return
		if p.members.size() >= MAX_PARTY:
			NetworkManager.send_system_message(id, "O grupo está cheio (%d)." % MAX_PARTY)
			return
	_invites[target] = {"from": id, "until": Time.get_ticks_msec() + INVITE_SECONDS * 1000}
	_invite_line.rpc_id(target, NetworkManager.player_name(id))
	NetworkManager.send_system_message(id, "Convite enviado para %s." % NetworkManager.player_name(target))


func _accept(id: int) -> void:
	var inv: Dictionary = _invites.get(id, {})
	_invites.erase(id)
	if inv.is_empty() or Time.get_ticks_msec() > int(inv.until) or not NetworkManager.players.has(inv.from):
		NetworkManager.send_system_message(id, "Nenhum convite válido.")
		return
	if _party_of.has(id):
		_leave_party(id, false)
	var leader: int = inv.from
	var pid: int
	if _party_of.has(leader):
		pid = _party_of[leader]
	else:
		pid = _next_party
		_next_party += 1
		_parties[pid] = {"leader": leader, "members": [leader]}
		_party_of[leader] = pid
	var p: Dictionary = _parties[pid]
	if p.members.size() >= MAX_PARTY:
		NetworkManager.send_system_message(id, "O grupo está cheio.")
		return
	p.members.append(id)
	_party_of[id] = pid
	for m in p.members:
		NetworkManager.send_system_message(m, "%s entrou no grupo." % NetworkManager.player_name(id))
	_push_party(pid)


func _leave_party(id: int, announce: bool, notify_self := true) -> void:
	if not _party_of.has(id):
		return
	var pid: int = _party_of[id]
	_party_of.erase(id)
	var p: Dictionary = _parties[pid]
	p.members.erase(id)
	if notify_self and NetworkManager.players.has(id):
		_party_state.rpc_id(id, [])
	for m in p.members:
		NetworkManager.send_system_message(m, "%s saiu do grupo." % NetworkManager.player_name(id))
	if announce and notify_self:
		NetworkManager.send_system_message(id, "Você saiu do grupo.")
	if p.members.size() <= 1:
		for m in p.members:
			_party_of.erase(m)
			_party_state.rpc_id(m, [])
		_parties.erase(pid)
		_last_party_state.erase(pid)
		return
	if p.leader == id:
		p.leader = p.members[0]
	_push_party(pid)


func _push_party(pid: int) -> void:
	if not _parties.has(pid):
		return
	var p: Dictionary = _parties[pid]
	var list := []
	for m: int in p.members:
		var avatar := Characters.avatar_of(m)
		list.append({"id": m, "name": NetworkManager.player_name(m), "leader": m == p.leader,
				"level": avatar.level if avatar else 1, "hp": avatar.hp if avatar else 0,
				"max_hp": avatar.max_hp if avatar else 1, "zone": Characters.zone_of(m)})
	if list == _last_party_state.get(pid, []):
		return  # nada mudou desde o ultimo envio
	_last_party_state[pid] = list
	for m: int in p.members:
		_party_state.rpc_id(m, list)


# ---------- RPCs para o cliente ----------

@rpc("authority", "call_remote", "reliable")
func _chat_line(channel: String, author: String, text: String) -> void:
	chat_received.emit(channel, author, text)


@rpc("authority", "call_remote", "reliable")
func _invite_line(from_name: String) -> void:
	invite_received.emit(from_name)
	chat_received.emit("sistema", "", "%s convidou você para um grupo. Digite /aceitar ou /recusar." % from_name)


@rpc("authority", "call_remote", "reliable")
func _party_state(members: Array) -> void:
	party = members
	party_changed.emit(members)
