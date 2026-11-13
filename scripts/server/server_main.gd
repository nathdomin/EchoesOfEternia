extends Node
## Servidor dedicado (E6). Roda sem jogador proprio, sem camera, som ou HUD.
## Carrega o mundo (zonas), abre a porta e registra no console quem entra e sai.
##
## Rodar:  EchoesOfEternia --headless --server [--port=7777] [--max-players=16]

const STATUS_INTERVAL := 60.0   ## segundos entre linhas de status no console

@onready var _world: Node = $World


func _ready() -> void:
	var port := Session.server_port()
	var max_players := Session.server_max_players()
	_print_banner(port, max_players)

	var err := NetworkManager.start_server(port, max_players)
	if err != OK:
		printerr("ERRO: nao foi possivel abrir a porta UDP %d (%s). Ela ja esta em uso?" % [port, error_string(err)])
		get_tree().quit(1)
		return
	_log("Servidor pronto. Aguardando jogadores na porta UDP %d." % port)

	var timer := Timer.new()
	timer.wait_time = STATUS_INTERVAL
	timer.autostart = true
	timer.timeout.connect(_print_status)
	add_child(timer)


func _notification(what: int) -> void:
	# Ctrl+C no terminal ou "systemctl stop" no Linux
	if what == NOTIFICATION_WM_CLOSE_REQUEST and NetworkManager.is_server():
		_log("Servidor encerrando.")
		NetworkManager.leave()


func _print_banner(port: int, max_players: int) -> void:
	print("==============================================")
	print(" Echoes of Eternia - servidor dedicado v%s" % GameVersion.VERSION)
	print(" Godot %s | porta UDP %d | ate %d jogadores" % [Engine.get_version_info().string, port, max_players])
	print(" Zonas carregadas: %s" % ", ".join(_world.get_children().map(func(n: Node) -> String: return n.name)))
	print("==============================================")


func _print_status() -> void:
	var names: Array = NetworkManager.players.values().map(func(p: Dictionary) -> String: return p.name)
	_log("Online: %d/%d %s" % [names.size(), NetworkManager.max_players, ("- " + ", ".join(names)) if not names.is_empty() else ""])


func _log(text: String) -> void:
	print("[%s] [Servidor] %s" % [Time.get_time_string_from_system(), text])
