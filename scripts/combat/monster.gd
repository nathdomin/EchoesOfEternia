class_name Monster
extends CharacterBody2D
## Monstro (E13). Criado pelo servidor (MonsterSpawner da zona) e
## sincronizado so com quem esta na mesma zona.
##
## Servidor: IA (passear perto de casa -> perseguir quem chega perto ->
## atacar -> desistir se for longe demais de casa e voltar curado), vida
## (HealthComponent), morte e respawn no mesmo lugar.
## Cliente: so desenha. Interpola a posicao, mostra a barra de vida, pisca
## ao levar dano, faz fumaca ao morrer e um "bote" ao atacar.

enum State { IDLE, CHASE, RETURN, DEAD }

const FOLLOW_RATE := 12.0
const SNAP_DISTANCE := 64.0
const SMOKE := preload("res://scenes/effects/smoke.tscn")

## Sincronizados (MultiplayerSynchronizer "Sync").
@export var monster_id := "slime"
@export var net_position := Vector2.ZERO
@export var facing := Vector2i.DOWN
@export var max_hp := 1
@export var hp := 1:
	set = _set_hp
@export var state := State.IDLE:
	set = _set_state
@export var attack_seq := 0:
	set = _set_attack_seq

var data: MonsterData
# So no servidor:
var zone := ""
var home := Vector2.ZERO
var wander_radius := 32.0
var _target := 0
var _next_attack_ms := 0
var _wander_to := Vector2.ZERO
var _wander_wait := 0.0
var _respawn_at_ms := 0

@onready var health: HealthComponent = $Health
@onready var hitbox: HitboxComponent = $Hitbox
@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _bar: TextureProgressBar = $HealthBar


static func data_for(id: String) -> MonsterData:
	var path := "res://resources/monsters/%s.tres" % id
	if not id.is_valid_identifier() or not ResourceLoader.exists(path):
		return null
	return load(path) as MonsterData


func _ready() -> void:
	data = data_for(monster_id)
	if data == null:
		push_error("Monstro desconhecido: %s" % monster_id)
		queue_free()
		return
	_sprite.sprite_frames = data.frames
	_sprite.play("idle_down")
	hitbox.radius = data.hitbox_radius
	if multiplayer.is_server():
		health.max_hp = data.max_hp
		health.reset()
		max_hp = data.max_hp
		hp = health.hp
		health.damaged.connect(_on_damaged)
		health.died.connect(_on_died)
		home = position
		net_position = position
		_wander_to = position
	else:
		position = net_position
		set_physics_process(false)
	_refresh_visuals()


func display_name() -> String:
	return data.display_name if data else "?"


func is_dead() -> bool:
	return state == State.DEAD


# ---------- servidor: IA ----------

func _physics_process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	if state == State.DEAD:
		if now >= _respawn_at_ms:
			_respawn()
		return

	if state == State.RETURN:
		_move_towards(home, data.speed)
		if position.distance_to(home) < 4.0:
			health.reset()
			hp = health.hp
			state = State.IDLE
	else:
		_pick_target()
		if _target != 0:
			state = State.CHASE
			var tpos := Characters.position_of(_target)
			var dist := position.distance_to(tpos)
			if dist > data.attack_range:
				_move_towards(tpos, data.speed)
			else:
				velocity = Vector2.ZERO
				_face(tpos - position)
				if now >= _next_attack_ms:
					_next_attack_ms = now + int(data.attack_cooldown * 1000.0)
					attack_seq += 1
					Combat.monster_attack(self, _target, data.damage)
			if position.distance_to(home) > data.leash_range:
				_target = 0
				state = State.RETURN
		else:
			state = State.IDLE
			_wander(delta)
	move_and_slide()
	net_position = position


func _pick_target() -> void:
	if _target != 0 and Combat.can_be_attacked(_target, zone) \
			and position.distance_to(Characters.position_of(_target)) < data.aggro_range * 2.0:
		return
	_target = 0
	var best := data.aggro_range
	for id in Characters.players_in_zone(zone):
		if not Combat.can_be_attacked(id, zone):
			continue
		var d := position.distance_to(Characters.position_of(id))
		if d < best:
			best = d
			_target = id


func _wander(delta: float) -> void:
	_wander_wait -= delta
	if position.distance_to(_wander_to) < 2.0 or _wander_wait <= 0.0:
		velocity = Vector2.ZERO
		if _wander_wait <= 0.0:
			_wander_wait = randf_range(2.0, 4.5)
			_wander_to = home + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * wander_radius
		return
	_move_towards(_wander_to, data.wander_speed)


func _move_towards(target: Vector2, speed: float) -> void:
	var dir := target - position
	velocity = dir.normalized() * speed if dir.length() > 1.0 else Vector2.ZERO
	if velocity != Vector2.ZERO:
		_face(velocity)


func _face(dir: Vector2) -> void:
	if absf(dir.x) >= absf(dir.y):
		facing = Vector2i.RIGHT if dir.x > 0.0 else Vector2i.LEFT
	else:
		facing = Vector2i.DOWN if dir.y > 0.0 else Vector2i.UP


func _on_damaged(_amount: int, source_id: int) -> void:
	hp = health.hp
	# Quem bate vira o alvo (se ainda nao estiver voltando para casa)
	if source_id != 0 and state != State.RETURN:
		_target = source_id


func _on_died(killer_id: int) -> void:
	hp = 0
	state = State.DEAD
	velocity = Vector2.ZERO
	_target = 0
	_respawn_at_ms = Time.get_ticks_msec() + int(data.respawn_time * 1000.0)
	Combat.monster_killed(self, killer_id)


func _respawn() -> void:
	position = home
	net_position = home
	health.reset()
	hp = health.hp
	state = State.IDLE


# ---------- cliente: visual ----------

func _process(delta: float) -> void:
	if multiplayer.is_server() or state == State.DEAD:
		return
	var dist := position.distance_to(net_position)
	if dist > SNAP_DISTANCE:
		position = net_position
	else:
		position = position.lerp(net_position, 1.0 - exp(-FOLLOW_RATE * delta))
	var anim: String = ("walk_" if dist > 0.5 else "idle_") + Player.DIR_NAMES.get(facing, "down")
	if _sprite.animation != anim:
		_sprite.play(anim)


func _set_hp(value: int) -> void:
	var took_damage := value < hp
	hp = value
	if not is_node_ready():
		return
	_refresh_visuals()
	if took_damage and not multiplayer.is_server():
		_sprite.modulate = Color(3, 3, 3)
		create_tween().tween_property(_sprite, "modulate", Color.WHITE, 0.18)


func _set_state(value: State) -> void:
	var was_dead := state == State.DEAD
	state = value
	if not is_node_ready() or multiplayer.is_server():
		return
	if value == State.DEAD and not was_dead:
		var fx := SMOKE.instantiate()
		fx.position = position + Vector2(0, -6)
		get_parent().add_child(fx)
	elif was_dead and value != State.DEAD:
		position = net_position
	_refresh_visuals()


func _set_attack_seq(value: int) -> void:
	var changed := value != attack_seq
	attack_seq = value
	if not changed or not is_node_ready() or multiplayer.is_server():
		return
	# "Bote" curto na direcao do alvo
	var lunge := Vector2(facing) * 4.0
	var t := create_tween()
	t.tween_property(_sprite, "offset", lunge, 0.06)
	t.tween_property(_sprite, "offset", Vector2.ZERO, 0.12)


func _refresh_visuals() -> void:
	var dead := state == State.DEAD
	_sprite.visible = not dead
	$Shadow.visible = not dead
	_bar.max_value = max_hp
	_bar.value = hp
	_bar.visible = not dead and hp < max_hp
