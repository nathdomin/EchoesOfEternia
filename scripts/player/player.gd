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
## O desenho do corte nao e centrado no quadro: este deslocamento poe o meio
## do arco no ponto do golpe (medido no SpriteSheet do SlashCurved).
const SLASH_OFFSET := Vector2(-6, -3)
const ATTACK_TIME := 0.22  ## segundos parado na pose de ataque
const BASE_STATS := preload("res://resources/combat/player_base.tres")
const LEAP_TIME := 0.2

@export var speed := SPEED
@export var acceleration := 900.0
@export var friction := 1100.0

var anim_state: AnimState = AnimState.IDLE
var facing := Vector2i.DOWN        ## direcao cardinal para onde o player olha
## Direcao (8 sentidos) em que andou por ultimo: mira dos golpes quando nao
## ha alvo (revisao das classes). `facing` e so o desenho (4 sentidos).
var aim_dir := Vector2.DOWN
var skin := "knight"
var is_dead := false
## Chat/dialogo abertos: o teclado nao move o personagem.
var input_locked := false
var _attack_left := 0.0
var _next_attack_ms := 0
## Combo (so o visual: o servidor conta o dele)
var _combo := 0
var _combo_until_ms := 0
## Esquiva
var _dodge_left := 0.0
var _dodge_dir := Vector2.ZERO
var _next_dodge_ms := 0
var _dash_speed := 0.0

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
		aim_dir = Vector2(dir)
	anim_state = AnimState.DEAD if is_dead else AnimState.IDLE
	_update_animation()
	_camera.reset_smoothing()


## Golpe (E12): pose de ataque + efeito na direcao `aim` (normalizada).
## Retorna o passo do combo (1-3) ou 0 se em recarga, morto ou esquivando.
## Quem decide se acertou e o servidor (Combat.request_attack).
## `melee` false (Arqueiro, Mago): so a pose; o projetil vem do servidor.
func try_attack(cooldown: float, aim: Vector2, reach := 20.0, melee := true) -> int:
	var now := Time.get_ticks_msec()
	if is_dead or now < _next_attack_ms or _dodge_left > 0.0:
		return 0
	_next_attack_ms = now + int(cooldown * 1000.0)
	_combo = (_combo % 3) + 1 if now <= _combo_until_ms else 1
	_combo_until_ms = now + int((cooldown + BASE_STATS.combo_window) * 1000.0)
	facing = _cardinal(aim)
	_attack_left = ATTACK_TIME
	anim_state = AnimState.ATTACK
	velocity = Vector2.ZERO
	_update_animation()
	if not melee:
		return 1
	spawn_slash(get_parent(), global_position, aim, reach, _combo == 3)
	GameAudio.play("swing", 0.06 if _combo < 3 else 0.0, 1.0)
	if _combo == 3:
		# o golpe final "anda" um pouco para frente
		var t := create_tween()
		t.tween_property(_sprite, "offset", aim * 3.0, 0.05)
		t.tween_property(_sprite, "offset", Vector2.ZERO, 0.12)
	return _combo


## Esquiva (Shift): corrida curta na direcao do input (ou para onde olha).
## Retorna false se em recarga, morto ou travado.
func try_dodge() -> bool:
	var now := Time.get_ticks_msec()
	if is_dead or input_locked or now < _next_dodge_ms or _dodge_left > 0.0:
		return false
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_dodge_dir = dir.normalized() if dir != Vector2.ZERO else Vector2(facing)
	_next_dodge_ms = now + int(BASE_STATS.dodge_cooldown * 1000.0)
	_dodge_left = BASE_STATS.dodge_time
	_dash_speed = BASE_STATS.dodge_distance / BASE_STATS.dodge_time
	_attack_left = 0.0
	anim_state = AnimState.WALK
	facing = _cardinal(_dodge_dir)
	_update_animation()
	_sprite.modulate.a = 0.55
	GameAudio.play("dodge")
	return true


## Salto para Tras (Arqueiro): corrida curta na direcao `dir`, olhando para
## o lado contrario. O servidor libera o movimento (Characters.grant_dash).
func leap(dir: Vector2, distance: float) -> void:
	if is_dead or dir == Vector2.ZERO:
		return
	_dodge_dir = dir.normalized()
	_dodge_left = LEAP_TIME
	_dash_speed = distance / LEAP_TIME
	_attack_left = 0.0
	facing = _cardinal(-_dodge_dir)
	anim_state = AnimState.WALK
	_update_animation()


## Segundos que faltam para poder esquivar de novo (0 = pronta).
func dodge_seconds_left() -> float:
	return maxf((_next_dodge_ms - Time.get_ticks_msec()) / 1000.0, 0.0)


## Rastro da esquiva: copia do sprite que some.
func _ghost() -> void:
	var g := Sprite2D.new()
	g.texture = _sprite.sprite_frames.get_frame_texture(_sprite.animation, _sprite.frame)
	g.global_position = _sprite.global_position
	g.modulate = Color(0.7, 0.85, 1.0, 0.5)
	g.z_index = -1
	get_parent().add_child(g)
	var t := g.create_tween()
	t.tween_property(g, "modulate:a", 0.0, 0.2)
	t.tween_callback(g.queue_free)


## Pose de lancar habilidade (sem o efeito de golpe; o servidor manda o efeito).
func play_cast() -> void:
	if is_dead:
		return
	_attack_left = ATTACK_TIME
	anim_state = AnimState.ATTACK
	velocity = Vector2.ZERO
	_update_animation()


## Efeito de golpe a frente de quem bate (usado tambem pelos RemotePlayer),
## centrado no circulo que o servidor usa para acertar
## (HitboxComponent.arc_center). `big` = 3o golpe do combo.
static func spawn_slash(parent: Node, feet: Vector2, aim: Vector2, reach := 20.0, big := false) -> void:
	var fx := SLASH.instantiate() as AnimatedSprite2D
	fx.position = HitboxComponent.arc_center(feet + Combat.BODY, aim, reach)
	fx.rotation = aim.angle()
	fx.offset = SLASH_OFFSET
	if big:
		fx.scale = Vector2(1.35, 1.35)
		fx.modulate = Color(1.4, 1.2, 0.8)
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
	_dodge_left = 0.0
	_sprite.modulate.a = 1.0
	anim_state = AnimState.DEAD if value else AnimState.IDLE
	_update_animation()


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if _dodge_left > 0.0:
		_dodge_left -= delta
		velocity = _dodge_dir * _dash_speed
		move_and_slide()
		_ghost()
		if _dodge_left <= 0.0:
			velocity = _dodge_dir * speed * 0.5
			_sprite.modulate.a = 1.0
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
		facing = _facing_for(input)
		aim_dir = input.normalized()
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


## Direcao para onde olhar andando. Na diagonal mantem a direcao atual se
## ela for uma das duas teclas apertadas (andar para cima e apertar a
## esquerda continua olhando para cima); ao soltar uma, vale a que ficou.
func _facing_for(input: Vector2) -> Vector2i:
	if absf(input.x) > 0.3 and absf(input.y) > 0.3:
		var fx := Vector2i.RIGHT if input.x > 0.0 else Vector2i.LEFT
		var fy := Vector2i.DOWN if input.y > 0.0 else Vector2i.UP
		if facing == fx or facing == fy:
			return facing
	return _cardinal(input)


## Converte uma direcao na direcao cardinal dominante (horizontal no empate).
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
