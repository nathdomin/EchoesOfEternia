extends Node2D
## Cena do cliente: so abre depois do login aceito no menu (E7). Coloca o
## player onde o personagem parou (E8, enviado pelo servidor) e avisa o
## servidor da posicao enquanto anda. Na E9 o spawn dos jogadores passa a
## ser feito pelo servidor (MultiplayerSpawner).
##
## Esc sai do mundo e volta ao menu. Se a conexao cair, volta ao menu
## mostrando o motivo.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const REPORT_INTERVAL := 0.1  ## segundos entre avisos de posicao ao servidor

var _last_sent_pos := Vector2.INF
var _last_sent_facing := Vector2i.ZERO
var _report_timer := 0.0

@onready var _village: Village = $World/Village
@onready var _player: Player = $World/Player


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

	NetworkManager.connection_ended.connect(_back_to_menu)
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
