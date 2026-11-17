class_name CharacterStore
extends RefCounted
## Personagens salvos (E8). So existe no servidor.
##
## Um personagem por conta, em <dados>/characters/<conta>.json:
##   { "format", "account", "name", "skin", "zone", "x", "y", "facing",
##     "level", "xp", "hp", "created_at", "last_seen", "play_time" }
## hp = -1 significa vida cheia.
## level/xp ja existem para a E16; inventario, classe etc. entram como
## campos novos (os que faltarem num arquivo antigo recebem o padrao).

const FORMAT_VERSION := 1
const FACINGS := ["down", "up", "left", "right"]

var _dir: String


func _init(data_dir: String) -> void:
	_dir = data_dir.path_join("characters")
	JsonStore.ensure_dir(_dir)


## Carrega o personagem da conta ou cria um novo na zona/posicao inicial.
## Retorna { "data": Dictionary, "is_new": bool }.
func load_or_create(account_key: String, display_name: String, zone: String, pos: Vector2) -> Dictionary:
	var path := _path(account_key)
	var defaults := _defaults(account_key, display_name, zone, pos)
	if not FileAccess.file_exists(path):
		return {"data": defaults, "is_new": true}

	var loaded: Variant = JsonStore.load_json(path)
	if not loaded is Dictionary:
		# Arquivo corrompido: guarda uma copia para analise e recomeca, em vez
		# de travar o login ou apagar o arquivo.
		var bad := "%s.corrompido-%d" % [path, int(Time.get_unix_time_from_system())]
		DirAccess.copy_absolute(path, bad)
		push_error("Personagem de '%s' corrompido; copia em %s" % [account_key, bad])
		return {"data": defaults, "is_new": true}

	var data: Dictionary = loaded
	for k in defaults:  # campos novos de versoes futuras
		if not data.has(k):
			data[k] = defaults[k]
	data.name = display_name
	data.x = float(data.x)
	data.y = float(data.y)
	for k in ["level", "xp", "hp", "created_at", "last_seen", "play_time"]:
		data[k] = int(data[k])
	if not data.facing in FACINGS:
		data.facing = "down"
	if not Player.SKINS.has(data.skin):
		data.skin = defaults.skin
	return {"data": data, "is_new": false}


func save(data: Dictionary) -> Error:
	data.format = FORMAT_VERSION
	data.last_seen = int(Time.get_unix_time_from_system())
	return JsonStore.save_json(_path(data.account), data)


func exists(account_key: String) -> bool:
	return FileAccess.file_exists(_path(account_key))


func _defaults(account_key: String, display_name: String, zone: String, pos: Vector2) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	return {
		"format": FORMAT_VERSION,
		"account": account_key,
		"name": display_name,
		"skin": skin_for(account_key),
		"zone": zone,
		"x": pos.x,
		"y": pos.y,
		"facing": "down",
		"level": 1,
		"xp": 0,
		"hp": -1,
		"created_at": now,
		"last_seen": now,
		"play_time": 0,
		"chests": {},  # bau -> hora (unix) em que enche de novo
		"gold": 0,  # pacote C
		"tutorial_seen": false,  # pacote F: ajuda do 1o jogo, por conta
	}


## Aparencia inicial sorteada pela conta (sempre a mesma para a mesma conta).
static func skin_for(account_key: String) -> String:
	var skins := Player.SKINS.keys()
	return skins[absi(account_key.hash()) % skins.size()]


func _path(key: String) -> String:
	return _dir.path_join(key + ".json")
