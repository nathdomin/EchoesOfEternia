extends Node
## Autoload "Session": guarda o que o jogador escolheu no menu (servidor,
## porta, nome) e le a linha de comando. O NetworkManager le estes dados.
##
## Linha de comando:
##   --server              abre como servidor dedicado (sem janela: use --headless)
##   --port=N              porta do servidor (padrao 7777)
##   --max-players=N       vagas do servidor (padrao 16)
##   --join=IP             cliente: conecta direto, pulando o menu
##   --name=X              cliente: nome do personagem

enum Mode { NONE, JOIN }

var mode: Mode = Mode.NONE
var host_ip := "127.0.0.1"
var port := NetUtils.DEFAULT_PORT
var player_name := "Jogador"
## Motivo da ultima saida do servidor (mostrado no menu e depois limpo).
var last_error := ""

var _cmdline_used := false


func setup_join(p_ip: String, p_port: int, p_name: String) -> void:
	mode = Mode.JOIN
	host_ip = p_ip.strip_edges()
	port = p_port
	player_name = _clean_name(p_name)


func reset() -> void:
	mode = Mode.NONE


## True quando o jogo deve rodar como servidor dedicado: exportacao de
## servidor (feature "dedicated_server") ou argumento --server.
func is_server_mode() -> bool:
	return OS.has_feature("dedicated_server") or "--server" in _args()


## Porta e vagas do servidor vindas da linha de comando.
func server_port() -> int:
	return int(_arg_value("--port=", str(NetUtils.DEFAULT_PORT)))


func server_max_players() -> int:
	return clampi(int(_arg_value("--max-players=", "16")), 1, 64)


## Le --join=IP, --port=N e --name=X (apenas na primeira vez).
## Retorna true se foi pedido para conectar direto (o menu pula para o jogo).
func apply_cmdline() -> bool:
	if _cmdline_used:
		return false
	_cmdline_used = true
	if "--host" in _args():
		push_warning("--host nao existe mais: rode um servidor com --server e entre com --join=127.0.0.1")
	var ip := _arg_value("--join=", "")
	if ip.is_empty():
		return false
	var p := int(_arg_value("--port=", str(port)))
	setup_join(ip, p if NetUtils.is_valid_port(str(p)) else port, _arg_value("--name=", player_name))
	return true


func _args() -> PackedStringArray:
	return OS.get_cmdline_args() + OS.get_cmdline_user_args()


func _arg_value(prefix: String, default: String) -> String:
	for a in _args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return default


func _clean_name(n: String) -> String:
	n = n.strip_edges().left(16)
	return n if not n.is_empty() else "Jogador"
