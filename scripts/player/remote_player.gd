class_name RemotePlayer
extends Node2D
## Outro jogador, visto por este cliente (E9).
##
## O servidor cria um RemotePlayer por jogador online (MultiplayerSpawner da
## zona) e atualiza `net_position`/`facing` com a posicao validada. O
## MultiplayerSynchronizer manda isso so para quem esta na mesma zona e ja
## carregou o jogo (filtro em Characters), nunca para o proprio dono, que
## controla o seu Player local.
##
## No cliente, a posicao e interpolada: os avisos chegam ~10x/s e o
## personagem anda suave entre eles.

const FOLLOW_RATE := 12.0    ## quanto maior, mais rapido alcanca a posicao recebida
const SNAP_DISTANCE := 64.0  ## longe demais (teleporte/correcao): pula direto
const WALK_THRESHOLD := 0.75 ## px de distancia para considerar andando

## Sincronizados (os dois primeiros so no spawn).
@export var display_name := ""
@export var skin := "knight":
	set = _set_skin
@export var level := 1
@export var net_position := Vector2.ZERO
@export var facing := Vector2i.DOWN
## Combate (E11-E14): vida, morto e contador de golpes (cada +1 = um golpe).
@export var max_hp := 100
@export var hp := 100:
	set = _set_hp
@export var dead := false:
	set = _set_dead
@export var attack_seq := 0:
	set = _set_attack_seq

const SLASH := preload("res://scenes/effects/slash.tscn")

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _name_label: Label = $NameLabel
## So o servidor usa (a vida oficial do jogador).
@onready var health: HealthComponent = $Health
@onready var hitbox: HitboxComponent = $Hitbox
var _attack_until_ms := 0


func _ready() -> void:
	_sprite.sprite_frames = Player.frames_for(skin)
	_name_label.text = display_name
	position = net_position
	if multiplayer.is_server():
		set_process(false)  # no servidor quem move e o Characters
	_update_animation(false)


## Servidor: copia a vida do HealthComponent para as propriedades sincronizadas.
func sync_health() -> void:
	max_hp = health.max_hp
	hp = health.hp


func _process(delta: float) -> void:
	if dead:
		return
	var dist := position.distance_to(net_position)
	if dist > SNAP_DISTANCE:
		position = net_position
	else:
		position = position.lerp(net_position, 1.0 - exp(-FOLLOW_RATE * delta))
	_update_animation(dist > WALK_THRESHOLD)


func _update_animation(walking: bool) -> void:
	if dead:
		_sprite.play("dead")
		return
	var kind := "walk_" if walking else "idle_"
	if Time.get_ticks_msec() < _attack_until_ms:
		kind = "attack_"
	var anim: String = kind + Player.DIR_NAMES.get(facing, "down")
	if _sprite.animation != anim:
		_sprite.play(anim)


func _set_hp(value: int) -> void:
	var lost := hp - value
	hp = value
	if lost > 0 and is_node_ready() and not multiplayer.is_server() and not dead:
		_sprite.modulate = Color(3, 3, 3)
		create_tween().tween_property(_sprite, "modulate", Color.WHITE, 0.18)
		FloatingText.spawn(get_parent().get_parent(), position, str(lost), FloatingText.HURT)


func _set_dead(value: bool) -> void:
	dead = value
	if is_node_ready() and not multiplayer.is_server():
		_update_animation(false)


func _set_attack_seq(value: int) -> void:
	var changed := value != attack_seq
	attack_seq = value
	if not changed or not is_node_ready() or multiplayer.is_server():
		return
	_attack_until_ms = Time.get_ticks_msec() + 250
	Player.spawn_slash(get_parent().get_parent(), position, facing)  # no mapa, nao em Players
	GameAudio.play_at("swing", position)


func _set_skin(value: String) -> void:
	skin = value
	if is_node_ready():
		_sprite.sprite_frames = Player.frames_for(skin)
