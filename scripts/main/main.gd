extends Node2D
## Cena do cliente: so abre depois do login aceito no menu (E7). Coloca o
## player onde o personagem parou (E8, enviado pelo servidor) e avisa o
## servidor da posicao enquanto anda. Na E9 o spawn dos jogadores passa a
## ser feito pelo servidor (MultiplayerSpawner).
##
## Esc sai do mundo e volta ao menu.
##
## Queda de conexao (E10): o jogo fica na tela com "Reconectando..." e tenta
## voltar com o token de sessao (sem pedir a senha), esperando cada vez mais
## entre as tentativas (~40 s no total com o tempo de cada conexao; cobre o
## servidor reiniciando sozinho na VM, que leva ~6 s).
## Se o servidor recusar (sessao expirada, manutencao, conta em outro lugar)
## ou as tentativas acabarem, volta ao menu com o motivo.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const REPORT_INTERVAL := 0.1  ## segundos entre avisos de posicao ao servidor
## Espera antes de cada tentativa de reconexao (segundos).
const RECONNECT_DELAYS := [1.0, 2.0, 3.0, 4.0, 5.0]

var _last_sent_pos := Vector2.INF
var _last_sent_facing := Vector2i.ZERO
var _report_timer := 0.0
## -1 = conectado; 0+ = tentativas de reconexao ja feitas
var _reconnect_attempt := -1

@onready var _village: Village = $World/Village
@onready var _player: Player = $World/Player
@onready var _hud: NetHud = $NetHud


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
	# Agora os spawners existem: o servidor pode mandar os outros jogadores
	Characters.notify_ready()

	NetworkManager.connection_ended.connect(_on_connection_ended)
	NetworkManager.connection_lost.connect(_on_connection_lost)
	NetworkManager.connection_ready.connect(_on_reconnected)
	if not NetworkManager.is_logged_in():
		# Aberta sem login (F6 nesta cena, ou a conexao caiu no fade do menu)
		_back_to_menu.call_deferred("Faça login para entrar no mundo.")


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


## Os outros jogadores voltam pelo spawner depois de reconectar.
func _clear_remote_players() -> void:
	var players := _village.get_node("Players")
	for c in players.get_children():
		players.remove_child(c)
		c.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		NetworkManager.leave()
		_back_to_menu("")


func _back_to_menu(reason: String) -> void:
	if not reason.is_empty():
		print("[Rede] Voltando ao menu: ", reason)
	Session.last_error = reason
	Session.reset()
	get_tree().change_scene_to_file(MENU_SCENE)
