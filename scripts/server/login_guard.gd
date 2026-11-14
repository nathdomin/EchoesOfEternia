class_name LoginGuard
extends RefCounted
## Limita tentativas de login e criacao de contas (E7). So no servidor.
##
## Cada tentativa de login abre uma conexao nova, entao os limites sao por
## IP e por conta, nao por conexao. Fica so na memoria: reiniciar o servidor
## zera os contadores.

const ACCOUNT_MAX_FAILS := 5     ## erros seguidos na mesma conta...
const ACCOUNT_LOCK_SEC := 60     ## ...bloqueiam a conta por 1 minuto
const IP_MAX_FAILS := 15         ## erros do mesmo IP...
const IP_WINDOW_SEC := 600       ## ...dentro de 10 minutos bloqueiam o IP
const IP_MAX_NEW_ACCOUNTS := 5   ## contas novas por IP...
const NEW_ACCOUNT_WINDOW_SEC := 3600  ## ...por hora

## chave -> Array[float] com o horario de cada evento
var _ip_fails: Dictionary = {}
var _ip_creates: Dictionary = {}
## conta -> { "fails": int, "until": float }
var _account_fails: Dictionary = {}


## "" se pode tentar; senao, a mensagem para o jogador.
func check_login(ip: String, account_key: String) -> String:
	var now := _now()
	if _recent(_ip_fails, ip, IP_WINDOW_SEC, now) >= IP_MAX_FAILS:
		return "Muitas tentativas erradas. Espere alguns minutos."
	var a: Dictionary = _account_fails.get(account_key, {})
	if a.get("until", 0.0) > now:
		return "Conta bloqueada por excesso de tentativas. Espere %d segundos." % ceili(a.until - now)
	return ""


func check_create(ip: String) -> String:
	# O proprio PC do servidor (testes locais, teste de carga) nao tem limite
	# de contas novas. Senha errada continua limitada.
	if not is_loopback(ip) and _recent(_ip_creates, ip, NEW_ACCOUNT_WINDOW_SEC, _now()) >= IP_MAX_NEW_ACCOUNTS:
		return "Muitas contas criadas deste endereço. Tente mais tarde."
	return check_login(ip, "")


func login_failed(ip: String, account_key: String) -> void:
	_push(_ip_fails, ip)
	if account_key.is_empty():
		return
	var a: Dictionary = _account_fails.get(account_key, {"fails": 0, "until": 0.0})
	a.fails += 1
	if a.fails >= ACCOUNT_MAX_FAILS:
		a.fails = 0
		a.until = _now() + ACCOUNT_LOCK_SEC
	_account_fails[account_key] = a


func login_succeeded(account_key: String) -> void:
	_account_fails.erase(account_key)


func account_created(ip: String) -> void:
	_push(_ip_creates, ip)


static func is_loopback(ip: String) -> bool:
	return ip.begins_with("127.") or ip == "::1" or ip == "::ffff:127.0.0.1"


func _push(table: Dictionary, key: String) -> void:
	if not table.has(key):
		table[key] = []
	table[key].append(_now())


## Quantos eventos da chave aconteceram na janela (e descarta os antigos).
func _recent(table: Dictionary, key: String, window: float, now: float) -> int:
	if not table.has(key):
		return 0
	var kept: Array = table[key].filter(func(t: float) -> bool: return now - t < window)
	if kept.is_empty():
		table.erase(key)
	else:
		table[key] = kept
	return kept.size()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
