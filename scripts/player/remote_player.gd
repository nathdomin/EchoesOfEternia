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
@export var skin := "knight"
@export var net_position := Vector2.ZERO
@export var facing := Vector2i.DOWN

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _name_label: Label = $NameLabel


func _ready() -> void:
	_sprite.sprite_frames = Player.frames_for(skin)
	_name_label.text = display_name
	position = net_position
	if multiplayer.is_server():
		set_process(false)  # no servidor quem move e o Characters
	_update_animation(false)


func _process(delta: float) -> void:
	var dist := position.distance_to(net_position)
	if dist > SNAP_DISTANCE:
		position = net_position
	else:
		position = position.lerp(net_position, 1.0 - exp(-FOLLOW_RATE * delta))
	_update_animation(dist > WALK_THRESHOLD)


func _update_animation(walking: bool) -> void:
	var anim: String = ("walk_" if walking else "idle_") + Player.DIR_NAMES.get(facing, "down")
	if _sprite.animation != anim:
		_sprite.play(anim)
