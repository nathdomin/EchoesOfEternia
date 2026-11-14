class_name AccountStore
extends RefCounted
## Contas de jogador (E7). So existe no servidor.
##
## Cada conta e um JSON em <dados>/accounts/<conta>.json:
##   { "username", "display_name", "salt", "hash", "iterations",
##     "created_at", "last_login" }
## A senha nunca e gravada: so o hash PBKDF2-HMAC-SHA256 com salt aleatorio
## de 16 bytes. "iterations" fica salvo para poder aumentar no futuro sem
## invalidar as contas antigas.

const FORMAT_VERSION := 1
## ~60 ms por login neste notebook. Mais iteracoes = mais seguro, porem o
## servidor fica parado esse tempo a cada login (roda na thread principal).
const ITERATIONS := 30000
const SALT_BYTES := 16
const USERNAME_MIN := 3
const USERNAME_MAX := 16
const PASSWORD_MIN := 6
const PASSWORD_MAX := 64
const MAX_ACCOUNTS := 2000
const RESERVED := ["admin", "administrador", "servidor", "server", "sistema", "system", "moderador", "gm"]

var _dir: String
var _crypto := Crypto.new()


func _init(data_dir: String) -> void:
	_dir = data_dir.path_join("accounts")
	JsonStore.ensure_dir(_dir)


# ---------- validacao (tambem usada pelo menu do cliente) ----------

## Retorna "" se o nome de conta for valido, ou a mensagem de erro.
static func check_username(username: String) -> String:
	if username.length() < USERNAME_MIN or username.length() > USERNAME_MAX:
		return "A conta precisa ter de %d a %d caracteres." % [USERNAME_MIN, USERNAME_MAX]
	if RegEx.create_from_string("^[A-Za-z0-9_]+$").search(username) == null:
		return "Use só letras sem acento, números e _ na conta."
	return ""


static func check_password(password: String) -> String:
	if password.length() < PASSWORD_MIN:
		return "A senha precisa ter pelo menos %d caracteres." % PASSWORD_MIN
	if password.length() > PASSWORD_MAX:
		return "A senha pode ter no máximo %d caracteres." % PASSWORD_MAX
	return ""


## Chave da conta: sem diferenca de maiusculas ("Ana" e "ana" sao a mesma).
static func key_of(username: String) -> String:
	return username.to_lower()


# ---------- contas ----------

func exists(username: String) -> bool:
	return FileAccess.file_exists(_path(key_of(username)))


func count() -> int:
	var d := DirAccess.open(_dir)
	if d == null:
		return 0
	return Array(d.get_files()).filter(func(f: String) -> bool: return f.ends_with(".json")).size()


## Cria a conta. Retorna { ok, error, key, name }.
func create(username: String, password: String) -> Dictionary:
	var err := check_username(username)
	if err.is_empty():
		err = check_password(password)
	if err.is_empty() and key_of(username) in RESERVED:
		err = "Este nome de conta é reservado."
	if err.is_empty() and exists(username):
		err = "Esta conta já existe. Escolha outro nome ou entre com ela."
	if err.is_empty() and count() >= MAX_ACCOUNTS:
		err = "O servidor não aceita novas contas no momento."
	if not err.is_empty():
		return {"ok": false, "error": err}

	var salt := _crypto.generate_random_bytes(SALT_BYTES)
	var now := int(Time.get_unix_time_from_system())
	var account := {
		"format": FORMAT_VERSION,
		"username": key_of(username),
		"display_name": username,
		"salt": salt.hex_encode(),
		"hash": hash_password(password, salt, ITERATIONS).hex_encode(),
		"iterations": ITERATIONS,
		"created_at": now,
		"last_login": now,
	}
	if JsonStore.save_json(_path(account.username), account) != OK:
		return {"ok": false, "error": "Erro do servidor ao salvar a conta. Tente de novo."}
	return {"ok": true, "key": account.username, "name": account.display_name}


## Confere conta e senha. Retorna { ok, error, key, name }.
## A mensagem de erro e a mesma para conta inexistente e senha errada, para
## nao revelar quais contas existem.
func verify(username: String, password: String) -> Dictionary:
	var wrong := {"ok": false, "error": "Conta ou senha incorretas."}
	var account: Variant = null
	if check_username(username).is_empty():
		account = JsonStore.load_json(_path(key_of(username)))
	if not account is Dictionary or not account.has("hash") or not account.has("salt"):
		# Gasta o mesmo tempo de um login real (nao da para descobrir pelo
		# tempo de resposta se a conta existe).
		hash_password(password, _crypto.generate_random_bytes(SALT_BYTES), ITERATIONS)
		return wrong
	var expected: PackedByteArray = String(account.hash).hex_decode()
	var got := hash_password(password, String(account.salt).hex_decode(), int(account.get("iterations", ITERATIONS)))
	if not _constant_time_equals(expected, got):
		return wrong
	account.last_login = int(Time.get_unix_time_from_system())
	JsonStore.save_json(_path(account.username), account)
	return {"ok": true, "key": account.username, "name": account.display_name}


# ---------- hash ----------

## PBKDF2-HMAC-SHA256 com 32 bytes de saida (conferido com os vetores da RFC 7914).
func hash_password(password: String, salt: PackedByteArray, iterations: int) -> PackedByteArray:
	var pw := password.to_utf8_buffer()
	var u := _crypto.hmac_digest(HashingContext.HASH_SHA256, pw, salt + PackedByteArray([0, 0, 0, 1]))
	var t := u.to_int64_array()
	for i in iterations - 1:
		u = _crypto.hmac_digest(HashingContext.HASH_SHA256, pw, u)
		var w := u.to_int64_array()
		t[0] ^= w[0]
		t[1] ^= w[1]
		t[2] ^= w[2]
		t[3] ^= w[3]
	return t.to_byte_array()


func _constant_time_equals(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size():
		return false
	var diff := 0
	for i in a.size():
		diff |= a[i] ^ b[i]
	return diff == 0


func _path(key: String) -> String:
	return _dir.path_join(key + ".json")
