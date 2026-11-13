extends Node
## Autoload "Session": guarda o que o jogador escolheu no menu
## (hospedar/entrar, IP, porta, nome). Na E5 o NetworkManager le estes
## dados para criar o servidor ou o cliente ENet.

enum Mode { NONE, HOST, JOIN }

var mode: Mode = Mode.NONE
var host_ip := "127.0.0.1"
var port := NetUtils.DEFAULT_PORT
var player_name := "Jogador"


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


func _clean_name(n: String) -> String:
	n = n.strip_edges().left(16)
	return n if not n.is_empty() else "Jogador"
