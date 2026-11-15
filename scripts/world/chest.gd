class_name Chest
extends StaticBody2D
## Bau (revisao do cenario). Fica em "Chests" na cena da zona; E perto dele
## abre. Cada jogador tem o seu: depois de aberto fica vazio para ele ate
## passar `loot.respawn_seconds` (gravado no personagem, vale mesmo depois
## de sair e entrar). Quem sorteia e entrega os itens e o servidor
## (PlayerData._open_chest); aqui so o desenho e a dica "E".

const OPEN_RANGE := 26.0
const TEXTURE := preload("res://assets/environments/custom/chest.png")

@export var loot: LootTable

@onready var _sprite: Sprite2D = $Sprite
@onready var _hint: Label = $Hint
var _t := 0.0


## Chave do bau no personagem: "<zona>/<nome do no>".
static func key_of(zone: String, chest_name: String) -> String:
	return "%s/%s" % [zone, chest_name]


func _ready() -> void:
	_sprite.texture = TEXTURE
	_sprite.hframes = 2
	_hint.visible = false
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		set_process(false)
		return
	PlayerData.changed.connect(_refresh)
	_refresh()


## Zona do bau (o mapa e o avo: <Zona>/Chests/<bau>).
func zone() -> String:
	var map := get_parent().get_parent()
	return String(map.name).to_snake_case() if map else ""


func is_open_for_me() -> bool:
	return PlayerData.chest_seconds_left(zone(), name) > 0.0


func _refresh() -> void:
	_sprite.frame = 1 if is_open_for_me() else 0


func _process(delta: float) -> void:
	_t += delta
	var scene := get_tree().current_scene
	var player := scene.get_node_or_null("World/Player") as Node2D if scene else null
	var near := player != null and player.global_position.distance_to(global_position) <= OPEN_RANGE
	var closed := not is_open_for_me()
	_hint.visible = near and closed
	_hint.position.y = -30.0 + sin(_t * 5.0) * 1.5
	# Brilho leve no bau fechado (chama a atencao de longe)
	_sprite.modulate = Color(1, 1, 1) * (1.0 + 0.12 * (0.5 + 0.5 * sin(_t * 3.0))) if closed else Color(0.8, 0.8, 0.8)
	if int(_t * 2.0) != int((_t - delta) * 2.0):
		_refresh()  # o tempo de espera passou: fecha de novo
