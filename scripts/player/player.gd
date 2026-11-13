class_name Player
extends CharacterBody2D
## Player local (E2): movimento em 8 direcoes, animacao procedural e camera.
## Na E6 este no passa a ter authority = peer id do dono; apenas o dono le
## input e move. `anim_state` e `facing` ja existem para serem sincronizados.

enum AnimState { IDLE, WALK }

@export var speed := 80.0          ## pixels por segundo (tile = 16 px)
@export var acceleration := 900.0
@export var friction := 1100.0

var anim_state: AnimState = AnimState.IDLE
var facing := Vector2.DOWN         ## ultima direcao em que o player andou

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _camera: Camera2D = $Camera2D

var _anim_time := 0.0
var _sprite_base_y := 0.0


func _ready() -> void:
	_sprite_base_y = _sprite.position.y
	_camera.make_current()


## Impede a camera de mostrar a area fora do mapa.
func set_camera_limits(bounds: Rect2) -> void:
	_camera.limit_left = int(bounds.position.x)
	_camera.limit_top = int(bounds.position.y)
	_camera.limit_right = int(bounds.end.x)
	_camera.limit_bottom = int(bounds.end.y)
	_camera.reset_smoothing()


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")

	if input != Vector2.ZERO:
		velocity = velocity.move_toward(input * speed, acceleration * delta)
		facing = input
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	move_and_slide()
	anim_state = AnimState.WALK if velocity.length() > 5.0 else AnimState.IDLE


func _process(delta: float) -> void:
	_update_animation(delta)


func _update_animation(delta: float) -> void:
	# Os sprites Kenney tem 1 frame: a animacao e feita com "bob" e flip.
	_anim_time += delta
	if facing.x != 0.0:
		_sprite.flip_h = facing.x < 0.0

	match anim_state:
		AnimState.WALK:
			var step := absf(sin(_anim_time * 12.0))
			_sprite.position.y = _sprite_base_y - roundf(step * 2.0)
			_sprite.rotation = sin(_anim_time * 12.0) * 0.06
		AnimState.IDLE:
			_sprite.position.y = _sprite_base_y
			_sprite.rotation = 0.0
			_sprite.scale.y = 1.0 + sin(_anim_time * 3.0) * 0.03
