extends Node
## Autoload "Session": guarda o que o jogador escolheu no menu (servidor,
## porta, conta) e le a linha de comando. O NetworkManager le estes dados.
##
## Linha de comando:
##   --server              abre como servidor dedicado (sem janela: use --headless)
##   --port=N              porta do servidor (padrao 7777)
##   --max-players=N       vagas do servidor (padrao 16)
##   --data=PASTA          servidor: onde ficam contas e chave (padrao user://data)
##   --join=IP             cliente: conecta direto, pulando o menu
##   --user=X --pass=Y     cliente: conta e senha (so em build de debug)
##   --create              cliente: cria a conta em vez de entrar (debug)

enum Mode { NONE, JOIN }

const PREFS_PATH := "user://client.cfg"

var mode: Mode = Mode.NONE
var host_ip := "127.0.0.1"
var port := NetUtils.DEFAULT_PORT
var account := ""
## Senha so fica na memoria ate ser enviada ao servidor (nunca e gravada).
var password := ""
var create_account := false
## Motivo da ultima saida do servidor (mostrado no menu e depois limpo).
var last_error := ""

var _cmdline_used := false


func _ready() -> void:
	if not is_server_mode():
		_load_prefs()


func setup_join(p_ip: String, p_port: int, p_account: String, p_password: String, p_create: bool) -> void:
	mode = Mode.JOIN
	host_ip = p_ip.strip_edges()
	port = p_port
	account = p_account.strip_edges()
	password = p_password
	create_account = p_create


## Le e apaga a senha (chamado logo antes de enviar ao servidor).
func take_password() -> String:
	var p := password
	password = ""
	return p


func reset() -> void:
	mode = Mode.NONE
	password = ""


## Lembra servidor e conta para a proxima vez (nunca a senha).
func save_prefs() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("login", "host", host_ip)
	cfg.set_value("login", "port", port)
	cfg.set_value("login", "account", account)
	cfg.save(PREFS_PATH)


func _load_prefs() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PREFS_PATH) != OK:
		return
	host_ip = str(cfg.get_value("login", "host", host_ip))
	var p := str(cfg.get_value("login", "port", port))
	port = int(p) if NetUtils.is_valid_port(p) else port
	account = str(cfg.get_value("login", "account", account))


## True quando o jogo deve rodar como servidor dedicado: exportacao de
## servidor (feature "dedicated_server") ou argumento --server.
func is_server_mode() -> bool:
	return OS.has_feature("dedicated_server") or "--server" in _args()


## Porta e vagas do servidor vindas da linha de comando.
func server_port() -> int:
	var p := _arg_value("--port=", str(NetUtils.DEFAULT_PORT))
	if not NetUtils.is_valid_port(p):
		push_warning("--port=%s invalida; usando %d" % [p, NetUtils.DEFAULT_PORT])
		return NetUtils.DEFAULT_PORT
	return int(p)


func server_max_players() -> int:
	var n := _arg_value("--max-players=", "16")
	if not n.is_valid_int():
		push_warning("--max-players=%s invalido; usando 16" % n)
		return 16
	return clampi(int(n), 1, 64)


## Pasta de dados do servidor (contas, chave do DTLS; personagens na E8).
func server_data_dir() -> String:
	return _arg_value("--data=", "user://data")


## Le --join=IP, --port=N, --user=X, --pass=Y e --create (apenas na primeira vez).
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
	if not OS.is_debug_build():
		push_warning("--join so funciona em build de debug (a senha nao deve ir pela linha de comando)")
		return false
	var p := _arg_value("--port=", str(port))
	setup_join(ip, int(p) if NetUtils.is_valid_port(p) else port,
			_arg_value("--user=", account), _arg_value("--pass=", ""), "--create" in _args())
	return true


func _args() -> PackedStringArray:
	return OS.get_cmdline_args() + OS.get_cmdline_user_args()


func _arg_value(prefix: String, default: String) -> String:
	for a in _args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return default
