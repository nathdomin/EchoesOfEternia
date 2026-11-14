class_name Player
extends CharacterBody2D
## Player local (E2): movimento em 8 direcoes, animacao em 4 direcoes e camera.
## Na E9 este no passa a ter authority = peer id do dono; apenas o dono le
## input e move. `anim_state` e `facing` ja existem para serem sincronizados.

enum AnimState { IDLE, WALK }

const DIR_NAMES := {
	Vector2i.DOWN: "down",
	Vector2i.UP: "up",
	Vector2i.LEFT: "left",
	Vector2i.RIGHT: "right",
}

## Velocidade maxima (px/s, tile = 16 px). O servidor usa este valor para
## recusar movimento rapido demais (Characters).
const SPEED := 80.0

@export var speed := SPEED
@export var acceleration := 900.0
@export var friction := 1100.0

var anim_state: AnimState = AnimState.IDLE
var facing := Vector2i.DOWN        ## direcao cardinal para onde o player olha

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _camera: Camera2D = $Camera2D


func _ready() -> void:
	_camera.make_current()
	_update_animation()


## Impede a camera de mostrar a area fora do mapa.
func set_camera_limits(bounds: Rect2) -> void:
	_camera.limit_left = int(bounds.position.x)
	_camera.limit_top = int(bounds.position.y)
	_camera.limit_right = int(bounds.end.x)
	_camera.limit_bottom = int(bounds.end.y)
	_camera.reset_smoothing()


## Coloca o player num ponto (spawn salvo ou correcao do servidor).
func place(pos: Vector2, dir: Vector2i) -> void:
	global_position = pos
	velocity = Vector2.ZERO
	if DIR_NAMES.has(dir):
		facing = dir
	anim_state = AnimState.IDLE
	_update_animation()
	_camera.reset_smoothing()


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")

	if input != Vector2.ZERO:
		velocity = velocity.move_toward(input * speed, acceleration * delta)
		facing = _cardinal(input)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	move_and_slide()
	anim_state = AnimState.WALK if velocity.length() > 5.0 else AnimState.IDLE
	_update_animation()


## Converte a direcao do input na direcao cardinal dominante.
## Em diagonal exata, mantem o eixo horizontal (sprite de lado le melhor).
func _cardinal(dir: Vector2) -> Vector2i:
	if absf(dir.x) >= absf(dir.y):
		return Vector2i.RIGHT if dir.x > 0.0 else Vector2i.LEFT
	return Vector2i.DOWN if dir.y > 0.0 else Vector2i.UP


func _update_animation() -> void:
	var prefix := "walk_" if anim_state == AnimState.WALK else "idle_"
	var anim: String = prefix + DIR_NAMES[facing]
	if _sprite.animation != anim:
		_sprite.play(anim)
