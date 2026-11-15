extends Node2D
## Cena do cliente: so abre depois do login aceito no menu (E7). Coloca o
## player onde o personagem parou (E8, enviado pelo servidor) e avisa o
## servidor da posicao enquanto anda. Na E9 o spawn dos jogadores passa a
## ser feito pelo servidor (MultiplayerSpawner).
##
## Combate (E12-E14): Espaco/J ataca na direcao do personagem; clique ou
## Tab escolhe o alvo (quadro no topo); Esc limpa o alvo. Ao morrer, conta
## o tempo ate renascer no ponto inicial da zona.
##
## Esc (sem alvo) sai do mundo e volta ao menu.
##
## Queda de conexao (E10): o jogo fica na tela com "Reconectando..." e tenta
## voltar com o token de sessao (sem pedir a senha), esperando cada vez mais
## entre as tentativas (~40 s no total com o tempo de cada conexao; cobre o
## servidor reiniciando sozinho na VM, que leva ~6 s).
## Se o servidor recusar (sessao expirada, manutencao, conta em outro lugar)
## ou as tentativas acabarem, volta ao menu com o motivo.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const REPORT_INTERVAL := 0.1  ## segundos entre avisos de posicao ao servidor
const BASE_STATS := preload("res://resources/combat/player_base.tres")
const TARGET_PICK_RADIUS := 12.0  ## px em volta do clique
const TARGET_TAB_RANGE := 160.0
## Espera antes de cada tentativa de reconexao (segundos).
const RECONNECT_DELAYS := [1.0, 2.0, 3.0, 4.0, 5.0]

var _last_sent_pos := Vector2.INF
var _last_sent_facing := Vector2i.ZERO
var _report_timer := 0.0
## -1 = conectado; 0+ = tentativas de reconexao ja feitas
var _reconnect_attempt := -1
var _respawn_left := 0.0

@onready var _village: Village = $World/Village
@onready var _player: Player = $World/Player
@onready var _hud: NetHud = $NetHud
@onready var _game_hud: GameHud = $GameHud


func _ready() -> void:
	_player.set_camera_limits(_village.get_bounds())
	var s := Characters.spawn
	if s.get("zone", "") == "village":
		_player.place(s.position, s.facing)
	else:
		_player.place(_village.get_spawn_position(), Vector2i.DOWN)
	_last_sent_pos = _player.global_position
	_last_sent_facing = _player.facing
	Characters.position_corrected.connect(func(pos: Vector2) -> void: _player.place(pos, _player.facing))
	_player.setup_look(s.get("skin", "knight"), NetworkManager.player_name(multiplayer.get_unique_id()))
	_game_hud.setup_player(_player.skin, NetworkManager.player_name(multiplayer.get_unique_id()))
	_game_hud.set_health(Combat.my_hp, Combat.my_max_hp)
	Combat.own_health_changed.connect(_game_hud.set_health)
	Combat.own_died.connect(_on_died)
	Combat.own_respawned.connect(_on_respawned)
	Combat.own_hit.connect(_on_own_hit)
	# Agora os spawners existem: o servidor pode mandar os outros jogadores
	Characters.notify_ready()

	NetworkManager.connection_ended.connect(_on_connection_ended)
	NetworkManager.connection_lost.connect(_on_connection_lost)
	NetworkManager.connection_ready.connect(_on_reconnected)
	if not NetworkManager.is_logged_in():
		# Aberta sem login (F6 nesta cena, ou a conexao caiu no fade do menu)
		_back_to_menu.call_deferred("Faça login para entrar no mundo.")


func _process(delta: float) -> void:
	if _respawn_left > 0.0:
		_respawn_left -= delta
		_hud.show_banner("Você morreu. Renascendo em %d s..." % ceili(maxf(_respawn_left, 0.0)))


func _physics_process(delta: float) -> void:
	_report_timer += delta
	if _report_timer < REPORT_INTERVAL:
		return
	_report_timer = 0.0
	var pos := _player.global_position
	if pos.distance_to(_last_sent_pos) > 0.5 or _player.facing != _last_sent_facing:
		_last_sent_pos = pos
		_last_sent_facing = _player.facing
		Characters.report_position(pos, _player.facing)


# ---------- reconexao ----------

func _on_connection_lost() -> void:
	_reconnect_attempt = 0
	_player.set_physics_process(false)
	_player.place(_player.global_position, _player.facing)
	_clear_remote_players()
	_try_reconnect()


func _try_reconnect() -> void:
	if _reconnect_attempt >= RECONNECT_DELAYS.size():
		_back_to_menu("Não foi possível reconectar ao servidor. Verifique a internet e entre de novo.")
		return
	var delay: float = RECONNECT_DELAYS[_reconnect_attempt]
	_reconnect_attempt += 1
	_hud.show_banner("Conexão perdida. Reconectando... (%d/%d)" % [_reconnect_attempt, RECONNECT_DELAYS.size()])
	await get_tree().create_timer(delay).timeout
	if not is_inside_tree() or _reconnect_attempt < 0:
		return
	Session.setup_resume()
	if NetworkManager.start_from_session() != OK:
		_try_reconnect()


func _on_connection_ended(reason: String) -> void:
	# Tentativa de reconexao que nao conectou (servidor ainda fora): tenta de novo
	if _reconnect_attempt >= 0 and not NetworkManager.last_end_was_rejection:
		_try_reconnect()
		return
	_back_to_menu(reason)


func _on_reconnected() -> void:
	if _reconnect_attempt < 0:
		return
	_reconnect_attempt = -1
	_hud.show_banner("")
	var s := Characters.spawn
	if s.get("zone", "") == "village":
		_player.place(s.position, s.facing)
	_last_sent_pos = _player.global_position
	_last_sent_facing = _player.facing
	_player.set_physics_process(true)
	Characters.notify_ready()


## Os outros jogadores e os monstros voltam pelo spawner depois de reconectar.
func _clear_remote_players() -> void:
	_game_hud.set_target(null)
	for container in [_village.get_node("Players"), _village.get_node("Monsters")]:
		for c in container.get_children():
			container.remove_child(c)
			c.queue_free()


# ---------- combate ----------

func _on_died(respawn_seconds: float) -> void:
	_player.set_dead(true)
	_respawn_left = respawn_seconds


func _on_respawned(pos: Vector2) -> void:
	_respawn_left = 0.0
	_hud.show_banner("")
	_player.set_dead(false)
	_player.place(pos, Vector2i.DOWN)
	_last_sent_pos = pos


## O servidor confirmou um acerto: sem alvo, o monstro atingido vira o alvo.
func _on_own_hit(monster_path: NodePath) -> void:
	var m := Combat.get_node_or_null(monster_path) as Node2D
	if m and (_game_hud.target == null or not is_instance_valid(_game_hud.target)):
		_game_hud.set_target(m)


func _targets() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for m: Monster in _village.get_node("Monsters").get_children():
		if not m.is_dead():
			out.append(m)
	for p: RemotePlayer in _village.get_node("Players").get_children():
		out.append(p)
	return out


func _select_at(world_pos: Vector2) -> void:
	var best: Node2D = null
	var best_d := TARGET_PICK_RADIUS
	for t in _targets():
		var d := t.global_position.distance_to(world_pos + Vector2(0, 7))
		if d < best_d:
			best_d = d
			best = t
	if best:
		_game_hud.set_target(best)


## Tab: proximo monstro vivo mais perto (em volta).
func _cycle_target() -> void:
	var near: Array[Node2D] = []
	for t in _targets():
		if t is Monster and t.global_position.distance_to(_player.global_position) <= TARGET_TAB_RANGE:
			near.append(t)
	if near.is_empty():
		return
	near.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return a.global_position.distance_to(_player.global_position) < b.global_position.distance_to(_player.global_position))
	var i := near.find(_game_hud.target)
	_game_hud.set_target(near[(i + 1) % near.size()])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack") and _reconnect_attempt < 0:
		if _player.try_attack(BASE_STATS.attack_cooldown):
			Combat.request_attack(_player.facing)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("target_next"):
		_cycle_target()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_at(get_global_mouse_position())
		return
	if event.is_action_pressed("ui_cancel") and _game_hud.target != null:
		_game_hud.set_target(null)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		NetworkManager.leave()
		_back_to_menu("")


func _back_to_menu(reason: String) -> void:
	if not reason.is_empty():
		print("[Rede] Voltando ao menu: ", reason)
	Session.last_error = reason
	Session.reset()
	get_tree().change_scene_to_file(MENU_SCENE)
