extends Node2D
## Cena do cliente: so abre depois do login aceito no menu (E7). Posiciona o
## player no SpawnPoint da vila e limita a camera ao mapa. Na E9 o spawn dos
## jogadores passa a ser feito pelo servidor (MultiplayerSpawner).
##
## Esc sai do mundo e volta ao menu. Se a conexao cair, volta ao menu
## mostrando o motivo.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

@onready var _village: Village = $World/Village
@onready var _player: Player = $World/Player


func _ready() -> void:
	_player.global_position = _village.get_spawn_position()
	_player.set_camera_limits(_village.get_bounds())

	NetworkManager.connection_ended.connect(_back_to_menu)
	if not NetworkManager.is_logged_in():
		# Aberta sem login (F6 nesta cena, ou a conexao caiu no fade do menu)
		_back_to_menu.call_deferred("Faça login para entrar no mundo.")


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
