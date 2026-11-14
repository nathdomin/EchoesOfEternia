class_name SessionTokens
extends RefCounted
## Tokens de reconexao (E10). So no servidor.
##
## A cada login o jogador recebe um token aleatorio (pelo DTLS). Se a conexao
## cair, o cliente volta com o token em vez da senha (que ele nao guarda).
## - Um token por conta: um login novo invalida o anterior.
## - Uso unico: ao reconectar, o token e trocado por um novo.
## - Vale TOKEN_HOURS horas.
## - Fica salvo (so o hash SHA-256) em <dados>/sessions.json: a reconexao
##   funciona mesmo se o servidor reiniciar depois de uma queda.

const TOKEN_BYTES := 32
const TOKEN_HOURS := 24

var _path: String
var _crypto := Crypto.new()
## hash do token -> { "account": String, "expires": int (unix) }
var _tokens: Dictionary = {}


func _init(data_dir: String) -> void:
	_path = data_dir.path_join("sessions.json")
	var loaded: Variant = JsonStore.load_json(_path)
	if loaded is Dictionary:
		_tokens = loaded
	_prune()


## Gera o token da conta (o anterior deixa de valer). Retorna o token em hex.
func issue(account_key: String) -> String:
	for h: String in _tokens.keys():
		if _tokens[h].account == account_key:
			_tokens.erase(h)
	var token := _crypto.generate_random_bytes(TOKEN_BYTES).hex_encode()
	_tokens[_hash(token)] = {"account": account_key, "expires": _now() + TOKEN_HOURS * 3600}
	_save()
	return token


## Confere e gasta o token. Retorna a conta, ou "" se invalido/expirado.
func consume(token: String) -> String:
	if token.length() != TOKEN_BYTES * 2:
		return ""
	var h := _hash(token)
	var entry: Variant = _tokens.get(h)
	if entry == null:
		return ""
	_tokens.erase(h)
	_save()
	if int(entry.expires) < _now():
		return ""
	return String(entry.account)


func _prune() -> void:
	var now := _now()
	for h: String in _tokens.keys():
		if not _tokens[h] is Dictionary or int(_tokens[h].get("expires", 0)) < now:
			_tokens.erase(h)


func _save() -> void:
	_prune()
	JsonStore.save_json(_path, _tokens)


func _hash(token: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(token.to_utf8_buffer())
	return ctx.finish().hex_encode()


func _now() -> int:
	return int(Time.get_unix_time_from_system())
