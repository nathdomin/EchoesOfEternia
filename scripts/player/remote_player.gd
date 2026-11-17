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
## Nivel: reenviado a cada 1 s (replication_interval do Sync), alem do
## nascimento. Se uma atualizacao se perder, a placa se corrige sozinha.
@export var level := 1:
	set = _set_level
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
var _weapon := Sprite2D.new()


func _ready() -> void:
	_weapon.visible = false
	add_child(_weapon)
	_sprite.sprite_frames = Player.frames_for(skin)
	_refresh_name()
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
		_weapon.visible = false
		return
	var kind := "walk_" if walking else "idle_"
	var attacking := Time.get_ticks_msec() < _attack_until_ms
	if attacking:
		kind = "attack_"
		Player.weapon_pose(_weapon, skin, facing)
	else:
		_weapon.visible = false
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
	Player.spawn_slash(get_parent().get_parent(), position, Vector2(facing))  # no mapa, nao em Players
	GameAudio.play_at("swing", position)


## Pose de lancar habilidade (o efeito vem do Combat._ability_fx).
func play_cast() -> void:
	if dead:
		return
	_attack_until_ms = Time.get_ticks_msec() + 250
	_update_animation(false)


func _set_skin(value: String) -> void:
	skin = value
	if is_node_ready():
		_sprite.sprite_frames = Player.frames_for(skin)


func _set_level(value: int) -> void:
	if value == level:
		return  # reenvio periodico sem mudanca
	level = value
	if is_node_ready():
		_refresh_name()


## Nome com o nivel ao lado, como nos MMOs ("Lia Nv5").
func _refresh_name() -> void:
	_name_label.text = "%s Nv%d" % [display_name, level] if display_name != "" else ""
