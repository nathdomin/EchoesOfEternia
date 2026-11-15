class_name Player
extends CharacterBody2D
## Player local (E2): movimento em 8 direcoes, animacao em 4 direcoes e camera.
## Na E9 este no passa a ter authority = peer id do dono; apenas o dono le
## input e move. `anim_state` e `facing` ja existem para serem sincronizados.

enum AnimState { IDLE, WALK, ATTACK, DEAD }

const DIR_NAMES := {
	Vector2i.DOWN: "down",
	Vector2i.UP: "up",
	Vector2i.LEFT: "left",
	Vector2i.RIGHT: "right",
}

## Velocidade maxima (px/s, tile = 16 px). O servidor usa este valor para
## recusar movimento rapido demais (Characters).
const SPEED := 80.0

## Aparencias disponiveis (sorteada por conta e salva no personagem).
const SKINS := {
	"knight": preload("res://resources/characters/knight_frames.tres"),
	"hunter": preload("res://resources/characters/hunter_frames.tres"),
	"sorcerer": preload("res://resources/characters/sorcerer_black_frames.tres"),
	"noble": preload("res://resources/characters/noble_frames.tres"),
}
const OWN_NAME_COLOR := Color(1.0, 0.85, 0.4)
## Retrato de cada aparencia (quadro do jogador na HUD).
const FACESETS := {
	"knight": preload("res://assets/characters/ninja/Knight/Faceset.png"),
	"hunter": preload("res://assets/characters/ninja/Hunter/Faceset.png"),
	"sorcerer": preload("res://assets/characters/ninja/SorcererBlack/Faceset.png"),
	"noble": preload("res://assets/characters/ninja/Noble/Faceset.png"),
}
const SLASH := preload("res://scenes/effects/slash.tscn")
const ATTACK_TIME := 0.22  ## segundos parado na pose de ataque

@export var speed := SPEED
@export var acceleration := 900.0
@export var friction := 1100.0

var anim_state: AnimState = AnimState.IDLE
var facing := Vector2i.DOWN        ## direcao cardinal para onde o player olha
var skin := "knight"
var is_dead := false
## Chat/dialogo abertos: o teclado nao move o personagem.
var input_locked := false
var _attack_left := 0.0
var _next_attack_ms := 0

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _camera: Camera2D = $Camera2D
@onready var _name_label: Label = $NameLabel


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


static func frames_for(skin: String) -> SpriteFrames:
	return SKINS.get(skin, SKINS.knight)


## Aparencia e nome sobre a cabeca (o proprio nome em dourado).
func setup_look(p_skin: String, display_name: String) -> void:
	skin = p_skin if SKINS.has(p_skin) else "knight"
	_sprite.sprite_frames = frames_for(skin)
	_name_label.text = display_name
	var ls := _name_label.label_settings.duplicate() as LabelSettings
	ls.font_color = OWN_NAME_COLOR
	_name_label.label_settings = ls
	_update_animation()


## Coloca o player num ponto (spawn salvo ou correcao do servidor).
func place(pos: Vector2, dir: Vector2i) -> void:
	global_position = pos
	velocity = Vector2.ZERO
	if DIR_NAMES.has(dir):
		facing = dir
	anim_state = AnimState.DEAD if is_dead else AnimState.IDLE
	_update_animation()
	_camera.reset_smoothing()


## Golpe (E12): pose de ataque + efeito. Retorna false se ainda em recarga
## ou morto. Quem decide se acertou e o servidor (Combat.request_attack).
func try_attack(cooldown: float) -> bool:
	var now := Time.get_ticks_msec()
	if is_dead or now < _next_attack_ms:
		return false
	_next_attack_ms = now + int(cooldown * 1000.0)
	_attack_left = ATTACK_TIME
	anim_state = AnimState.ATTACK
	velocity = Vector2.ZERO
	_update_animation()
	spawn_slash(get_parent(), global_position, facing)
	GameAudio.play("swing")
	return true


## Pose de lancar habilidade (sem o efeito de golpe; o servidor manda o efeito).
func play_cast() -> void:
	if is_dead:
		return
	_attack_left = ATTACK_TIME
	anim_state = AnimState.ATTACK
	velocity = Vector2.ZERO
	_update_animation()


## Efeito de golpe a frente de quem bate (usado tambem pelos RemotePlayer).
static func spawn_slash(parent: Node, pos: Vector2, dir: Vector2i) -> void:
	var fx := SLASH.instantiate() as Node2D
	fx.position = pos + Vector2(0, -7) + Vector2(dir) * 10.0
	fx.rotation = Vector2(dir).angle()
	parent.add_child(fx)


## Tremor de camera (dano, pisao do chefe). `strength` em px.
func shake(strength: float, duration := 0.25) -> void:
	var t := create_tween()
	var steps := maxi(int(duration / 0.03), 2)
	for i in steps:
		var k := 1.0 - float(i) / steps
		t.tween_property(_camera, "offset", Vector2(randf_range(-1, 1), randf_range(-1, 1)) * strength * k, 0.03)
	t.tween_property(_camera, "offset", Vector2.ZERO, 0.03)


func set_dead(value: bool) -> void:
	is_dead = value
	velocity = Vector2.ZERO
	anim_state = AnimState.DEAD if value else AnimState.IDLE
	_update_animation()


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if _attack_left > 0.0:
		_attack_left -= delta
		if _attack_left <= 0.0:
			anim_state = AnimState.IDLE
		return
	var input := Vector2.ZERO
	if not input_locked:
		input = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	if input != Vector2.ZERO:
		velocity = velocity.move_toward(input * speed, acceleration * delta)
		facing = _cardinal(input)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	move_and_slide()
	anim_state = AnimState.WALK if velocity.length() > 5.0 else AnimState.IDLE
	_update_animation()
	_footsteps(delta)


## Passos (Gate 5): um a cada STEP_EVERY s andando, sorteados entre 5.
const STEP_EVERY := 0.32
var _step_left := 0.0


func _footsteps(delta: float) -> void:
	if anim_state != AnimState.WALK:
		_step_left = 0.08  # o primeiro passo sai logo ao comecar a andar
		return
	_step_left -= delta
	if _step_left <= 0.0:
		_step_left = STEP_EVERY
		GameAudio.play("step%d" % (randi() % 5), 0.08)


## Converte a direcao do input na direcao cardinal dominante.
## Em diagonal exata, mantem o eixo horizontal (sprite de lado le melhor).
func _cardinal(dir: Vector2) -> Vector2i:
	if absf(dir.x) >= absf(dir.y):
		return Vector2i.RIGHT if dir.x > 0.0 else Vector2i.LEFT
	return Vector2i.DOWN if dir.y > 0.0 else Vector2i.UP


func _update_animation() -> void:
	if anim_state == AnimState.DEAD:
		_sprite.play("dead")
		return
	var prefix := "idle_"
	match anim_state:
		AnimState.WALK:
			prefix = "walk_"
		AnimState.ATTACK:
			prefix = "attack_"
	var anim: String = prefix + DIR_NAMES[facing]
	if _sprite.animation != anim:
		_sprite.play(anim)
