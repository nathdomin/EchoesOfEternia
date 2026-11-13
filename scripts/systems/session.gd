extends Node
## Autoload "Session": guarda o que o jogador escolheu no menu
## (hospedar/entrar, IP, porta, nome). Na E5 o NetworkManager le estes
## dados para criar o servidor ou o cliente ENet.

enum Mode { NONE, HOST, JOIN }

var mode: Mode = Mode.NONE
var host_ip := "127.0.0.1"
var port := NetUtils.DEFAULT_PORT
var player_name := "Jogador"
## Motivo da ultima saida da partida (mostrado no menu e depois limpo).
var last_error := ""

var _cmdline_used := false


func setup_host(p_port: int, p_name: String) -> void:
	mode = Mode.HOST
	port = p_port
	player_name = _clean_name(p_name)


func setup_join(p_ip: String, p_port: int, p_name: String) -> void:
	mode = Mode.JOIN
	host_ip = p_ip.strip_edges()
	port = p_port
	player_name = _clean_name(p_name)


func reset() -> void:
	mode = Mode.NONE


## Le --host, --join=IP, --port=N e --name=X da linha de comando.
## Retorna true se algum modo foi pedido (o menu entao abre o jogo direto).
func apply_cmdline() -> bool:
	if _cmdline_used:
		return false
	_cmdline_used = true
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	var p := port
	var n := player_name
	var want := Mode.NONE
	var ip := host_ip
	for a in args:
		if a == "--host":
			want = Mode.HOST
		elif a.begins_with("--join="):
			want = Mode.JOIN
			ip = a.trim_prefix("--join=")
		elif a.begins_with("--port=") and NetUtils.is_valid_port(a.trim_prefix("--port=")):
			p = int(a.trim_prefix("--port="))
		elif a.begins_with("--name="):
			n = a.trim_prefix("--name=")
	if want == Mode.HOST:
		setup_host(p, n)
	elif want == Mode.JOIN:
		setup_join(ip, p, n)
	return want != Mode.NONE


func _clean_name(n: String) -> String:
	n = n.strip_edges().left(16)
	return n if not n.is_empty() else "Jogador"
