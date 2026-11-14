extends Node
## Servidor dedicado (E6). Roda sem jogador proprio, sem camera, som ou HUD.
## Carrega o mundo (zonas), abre a porta e registra no console quem entra e sai.
##
## Rodar:  EchoesOfEternia --headless --server [--port=7777] [--max-players=16] [--data=PASTA]
##
## Dados (contas, personagens) e a chave do DTLS ficam em --data
## (padrao user://data). Na VM o servico usa /var/lib/echoes.
##
## Desligar sem perder nada: crie o arquivo <dados>/stop.request (o
## "systemctl stop" faz isso). O servidor salva todos os personagens, avisa os
## jogadores e fecha. Fechar a janela/Ctrl+C tambem salva quando o sistema
## avisa o Godot; para quedas sem aviso existe o salvamento automatico.

const STATUS_INTERVAL := 600.0  ## segundos entre linhas de status no console
## Sem janela o Godot roda sem limite de quadros e gasta CPU a toa na VM.
## 60 = mesma frequencia da fisica (medido: ~7% de um nucleo ocioso).
const SERVER_FPS := 60
const STOP_FILE := "stop.request"

var _data_dir := ""
var _stopping := false

@onready var _world: Node = $World


func _ready() -> void:
	Engine.max_fps = SERVER_FPS
	var port := Session.server_port()
	var max_players := Session.server_max_players()
	var data_dir := Session.server_data_dir()
	_data_dir = data_dir
	get_tree().auto_accept_quit = false  # fechar passa por _shutdown (salva antes)
	if JsonStore.ensure_dir(data_dir) != OK:
		printerr("ERRO: nao foi possivel criar a pasta de dados %s" % data_dir)
		get_tree().quit(1)
		return
	DirAccess.remove_absolute(data_dir.path_join(STOP_FILE))  # pedido antigo
	var accounts := AccountStore.new(data_dir)
	Characters.start_server(CharacterStore.new(data_dir))
	for zone: Node in _world.get_children():
		if zone.has_method("get_bounds"):
			Characters.register_zone(zone.name.to_snake_case(), zone)
	var tls := NetSecurity.server_options(data_dir)
	_print_banner(port, max_players, data_dir, accounts.count())

	var err := NetworkManager.start_server(port, max_players, accounts, SessionTokens.new(data_dir), tls)
	if err != OK:
		printerr("ERRO: nao foi possivel abrir a porta UDP %d com DTLS (%s). Ela ja esta em uso?" % [port, error_string(err)])
		get_tree().quit(1)
		return
	_log("Servidor pronto. Aguardando jogadores na porta UDP %d." % port)

	var timer := Timer.new()
	timer.wait_time = STATUS_INTERVAL
	timer.autostart = true
	timer.timeout.connect(_print_status)
	add_child(timer)

	var stop_check := Timer.new()
	stop_check.wait_time = 1.0
	stop_check.autostart = true
	stop_check.timeout.connect(_check_stop_request)
	add_child(stop_check)


func _notification(what: int) -> void:
	# Fechar a janela / Ctrl+C (quando o sistema avisa o Godot)
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_shutdown("pedido do sistema")


func _check_stop_request() -> void:
	var path := _data_dir.path_join(STOP_FILE)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		_shutdown("pedido de parada (%s)" % STOP_FILE)


## Salva todos os personagens, avisa os jogadores e fecha.
func _shutdown(why: String) -> void:
	if _stopping:
		return
	_stopping = true
	_log("Encerrando: %s" % why)
	if NetworkManager.is_server():
		var n := Characters.save_all()
		_log("%d personagem(ns) salvo(s)." % n)
		await NetworkManager.shutdown_server("O servidor foi desligado para manutenção. Seu personagem foi salvo.")
	_log("Servidor encerrado.")
	get_tree().quit(0)


func _print_banner(port: int, max_players: int, data_dir: String, account_count: int) -> void:
	print("==============================================")
	print(" Echoes of Eternia - servidor dedicado v%s" % GameVersion.VERSION)
	print(" Godot %s | porta UDP %d (DTLS) | ate %d jogadores" % [Engine.get_version_info().string, port, max_players])
	print(" Zonas carregadas: %s" % ", ".join(_world.get_children().map(func(n: Node) -> String: return n.name)))
	print(" Dados: %s (%d contas)" % [ProjectSettings.globalize_path(data_dir), account_count])
	print(" Salvamento automatico a cada %d s; parada segura: crie %s na pasta de dados" % [Characters.AUTOSAVE_SEC, STOP_FILE])
	print(" Certificado: %s" % NetSecurity.server_cert_path(data_dir))
	print("==============================================")


func _print_status() -> void:
	var names: Array = NetworkManager.players.values().map(func(p: Dictionary) -> String: return p.name)
	_log("Online: %d/%d %s" % [names.size(), NetworkManager.max_players, ("- " + ", ".join(names)) if not names.is_empty() else ""])


func _log(text: String) -> void:
	print("[%s] [Servidor] %s" % [Time.get_time_string_from_system(), text])
