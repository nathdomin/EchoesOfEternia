class_name Monster
extends CharacterBody2D
## Monstro (E13). Criado pelo servidor (MonsterSpawner da zona) e
## sincronizado so com quem esta na mesma zona.
##
## Servidor: IA (passear perto de casa -> perseguir quem chega perto ->
## avisar e atacar -> desistir se for longe demais de casa e voltar curado),
## vida (HealthComponent), morte e respawn no mesmo lugar.
## Combate dinamico: antes de cada golpe o monstro para e pisca (WINDUP,
## `MonsterData.windup`); o dano so sai se o alvo ainda estiver no alcance e
## nao estiver esquivando. O chefe marca o pisao no chao antes de dar.
## Cliente: so desenha. Interpola a posicao, mostra a barra de vida, pisca
## ao levar dano e ao preparar o golpe, faz fumaca ao morrer e um "bote" ao
## atacar.
## Revisao das classes: efeitos das habilidades (lentidao, congelado,
## provocacao), decididos no servidor; `status` sincronizado so pinta o monstro.

enum State { IDLE, CHASE, RETURN, DEAD, WINDUP }
enum Status { NONE, SLOW, FROZEN }

const FOLLOW_RATE := 12.0
const SNAP_DISTANCE := 64.0
const SMOKE := preload("res://scenes/effects/smoke.tscn")
## Para trocar de alvo, o outro precisa passar a ameaca atual em 10%.
const THREAT_SWITCH := 1.1
## Distancia minima ate o jogador para continuar na lista de ameaca.
const THREAT_KEEP_RANGE := 140.0
## No fim do aviso, o golpe ainda acerta ate attack_range + isto (o bote).
const LUNGE_REACH := 8.0
## Monstros mais perto que isto se afastam um do outro (nao se empilham).
const SEPARATION := 12.0
const WINDUP_TINT := Color(1.7, 0.55, 0.45)
const STATUS_TINT := {Status.NONE: Color.WHITE, Status.SLOW: Color(0.7, 0.85, 1.35), Status.FROZEN: Color(0.55, 0.8, 1.9)}

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
@export var status := Status.NONE:
	set = _set_status

var data: MonsterData
# So no servidor:
var zone := ""
var home := Vector2.ZERO
var wander_radius := 32.0
var _target := 0
## Revisao MMO: dano causado por jogador (credito do abate) e ameaca
## (quem o monstro persegue). Zeram quando ele volta para casa ou morre.
var _damage_by: Dictionary = {}  ## peer -> int
var _threat: Dictionary = {}     ## peer -> float
var _next_attack_ms := 0
var _wander_to := Vector2.ZERO
var _wander_wait := 0.0
var _respawn_at_ms := 0
var _next_slam_ms := 0
## Golpe em preparo (WINDUP): "attack" ou "slam", e quando ele sai.
var _pending := ""
var _strike_at_ms := 0
var _windup_tween: Tween
## Efeitos das habilidades (so no servidor): ate quando e quanto.
var _slow_until_ms := 0
var _slow_mult := 1.0
var _stun_until_ms := 0
## Pacote B: chamado pelo chefe (some ao morrer, nao renasce).
var temporary := false
## Chefe: cuspes marcados no chao ({pos, at}), reforcos ja chamados e os
## monstros chamados (somem quando o chefe morre ou volta para casa).
var _spits: Array[Dictionary] = []
var _next_spit_ms := 0
var _summons_done := 0
var _summoned: Array[Monster] = []
var _next_scale_ms := 0

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
	_sprite.modulate = data.tint
	# Sprite e barra de vida conforme o tamanho do quadro (chefe e maior)
	var tex := data.frames.get_frame_texture("idle_down", 0)
	var h := tex.get_height() if tex else 16
	_sprite.position = Vector2(0, -h / 2.0 + (4 if h > 16 else 0))
	_bar.position = Vector2(-9, -h - 3)
	if data.is_boss:
		_bar.scale = Vector2(2, 1)
		_bar.position.x = -18
		$Shadow.scale = Vector2(3, 2)
	# Hitbox no meio do desenho, do tamanho do corpo (o chefe e grande)
	hitbox.radius = data.hitbox_radius
	hitbox.position = Vector2(0, _sprite.position.y)
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


## Servidor: golpes acertam? Voltando para casa ele se esquiva (senao dava
## para bater de graca num monstro que desistiu e levar o abate inteiro).
func can_be_hit() -> bool:
	return state != State.DEAD and state != State.RETURN


# ---------- servidor: IA ----------

func _physics_process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	if state == State.DEAD:
		if now >= _respawn_at_ms:
			_respawn()
		return

	_update_status(now)
	if now < _stun_until_ms and state != State.RETURN:
		# Congelado: parado, sem atacar (o golpe em preparo e perdido)
		if state == State.WINDUP:
			_pending = ""
			state = State.CHASE
		velocity = Vector2.ZERO
		return

	if data.is_boss:
		_boss_tick(now)

	if state == State.WINDUP:
		# Parado preparando o golpe, virado para o alvo
		velocity = Vector2.ZERO
		if _target != 0 and Combat.can_be_attacked(_target, zone):
			_face(Characters.position_of(_target) - position)
		if now >= _strike_at_ms:
			_strike()
		return

	if state == State.RETURN:
		_move_towards(home, data.speed)
		if position.distance_to(home) < 4.0:
			health.reset()
			hp = health.hp
			state = State.IDLE
			_reset_boss()
	else:
		_pick_target()
		if _target != 0:
			state = State.CHASE
			var tpos := Characters.position_of(_target)
			var dist := position.distance_to(tpos)
			if dist > data.attack_range:
				_move_towards(tpos, data.speed * _speed_mult())
			else:
				velocity = _separation() * data.speed * 0.6
				_face(tpos - position)
				if now >= _next_attack_ms:
					_next_attack_ms = now + int((data.windup + data.attack_cooldown) * 1000.0)
					_start_windup("attack", data.windup)
			if data.is_boss and state != State.WINDUP and now >= _next_slam_ms and dist < data.slam_radius * 1.5:
				_next_slam_ms = now + int((data.slam_every + data.slam_telegraph) * 1000.0)
				_start_windup("slam", data.slam_telegraph)
				Combat.warn_area(zone, position, data.slam_radius, data.slam_telegraph)
			if position.distance_to(home) > data.leash_range:
				_target = 0
				_forget()
				state = State.RETURN
		else:
			state = State.IDLE
			_wander(delta)
	move_and_slide()
	net_position = position


func _pick_target() -> void:
	var keep := maxf(data.aggro_range * 2.0, THREAT_KEEP_RANGE)
	for id: int in _threat.keys():
		if not Combat.can_be_attacked(id, zone) or position.distance_to(Characters.position_of(id)) > keep:
			_threat.erase(id)
	if not _threat.is_empty():
		# Maior ameaca; so troca de alvo se passar a atual com folga
		var best_id := 0
		var best := -1.0
		for id: int in _threat:
			if _threat[id] > best:
				best = _threat[id]
				best_id = id
		if _target == 0 or not _threat.has(_target) or best > float(_threat[_target]) * THREAT_SWITCH:
			_target = best_id
		return
	_target = 0
	var near := data.aggro_range
	for id in Characters.players_in_zone(zone):
		if not Combat.can_be_attacked(id, zone):
			continue
		var d := position.distance_to(Characters.position_of(id))
		if d < near:
			near = d
			_target = id
	if _target != 0:
		_threat[_target] = 1.0  # quem chegou perto primeiro


## Servidor: comeca a preparar um golpe ("attack" ou "slam") que sai em `secs`.
func _start_windup(kind: String, secs: float) -> void:
	_pending = kind
	_strike_at_ms = Time.get_ticks_msec() + int(secs * 1000.0)
	velocity = Vector2.ZERO
	state = State.WINDUP


## Servidor: fim do aviso. O golpe so acerta se o alvo ainda estiver perto
## (o Combat ainda confere a esquiva); o pisao acerta quem ficou no circulo.
func _strike() -> void:
	var kind := _pending
	_pending = ""
	state = State.CHASE
	if kind == "slam":
		Combat.boss_slam(self, data.slam_radius, roundi(data.damage * data.slam_damage_mult))
		return
	attack_seq += 1  # o bote aparece mesmo quando erra
	if _target != 0 and Combat.can_be_attacked(_target, zone) 			and position.distance_to(Characters.position_of(_target)) <= data.attack_range + LUNGE_REACH:
		Combat.monster_attack(self, _target, data.damage)


## Servidor: o 3o golpe do combo empurra o monstro e interrompe o golpe que
## ele preparava (o chefe nao e empurrado nem interrompido).
func push_back(dir: Vector2, px: float) -> void:
	if data.is_boss or state == State.DEAD or state == State.RETURN:
		return
	move_and_collide(dir * px)
	net_position = position
	if state == State.WINDUP and _pending == "attack":
		_pending = ""
		state = State.CHASE
		_next_attack_ms = maxi(_next_attack_ms, Time.get_ticks_msec() + 500)


## Empurrao para longe dos monstros vizinhos (0..1 por vizinho).
func _separation() -> Vector2:
	var push := Vector2.ZERO
	for other in get_parent().get_children():
		if other == self or not other is Monster or (other as Monster).state == State.DEAD:
			continue
		var d: Vector2 = position - (other as Monster).position
		var l := d.length()
		if l < SEPARATION:
			var away := d / l if l > 0.01 else Vector2.from_angle(randf() * TAU)
			push += away * (SEPARATION - l) / SEPARATION
	return push


## Servidor: lentidao (velocidade x `mult`) por `secs`. Fica a mais forte.
func apply_slow(mult: float, secs: float) -> void:
	if state == State.DEAD or data.slow_immune or mult <= 0.0 or mult >= 1.0 or secs <= 0.0:
		return
	var now := Time.get_ticks_msec()
	_slow_mult = minf(_slow_mult, mult) if now < _slow_until_ms else mult
	_slow_until_ms = maxi(_slow_until_ms, now + int(secs * 1000.0))
	_update_status(now)


## Servidor: congela por `secs` (para e nao ataca). O chefe e imune.
func apply_stun(secs: float) -> void:
	if state == State.DEAD or data.is_boss or secs <= 0.0:
		return
	var now := Time.get_ticks_msec()
	_stun_until_ms = maxi(_stun_until_ms, now + int(secs * 1000.0))
	_update_status(now)


## Servidor: provocacao (Grito de Guerra). Passa a perseguir `id`: a ameaca
## dele fica bem acima da maior da lista.
func taunt(id: int) -> void:
	if id == 0 or state == State.DEAD or state == State.RETURN:
		return
	var top := 0.0
	for v: float in _threat.values():
		top = maxf(top, v)
	_threat[id] = top * 1.5 + 50.0
	_target = id
	if state == State.IDLE:
		state = State.CHASE


func _speed_mult() -> float:
	return _slow_mult if Time.get_ticks_msec() < _slow_until_ms else 1.0


func _update_status(now: int) -> void:
	var s := Status.NONE
	if now < _stun_until_ms:
		s = Status.FROZEN
	elif now < _slow_until_ms:
		s = Status.SLOW
	if s != status:
		status = s


## Servidor: ameaca extra (habilidade de guerreiro, cura de quem ele ataca).
func add_threat(id: int, amount: float) -> void:
	if id != 0 and state != State.DEAD and state != State.RETURN and amount > 0.0:
		_threat[id] = float(_threat.get(id, 0.0)) + amount


## Servidor: este jogador esta na lista de ameaca do monstro?
func is_fighting(id: int) -> bool:
	return _threat.has(id)


func _forget() -> void:
	_pending = ""
	_damage_by.clear()
	_threat.clear()


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
	velocity += _separation() * speed * 0.6


func _face(dir: Vector2) -> void:
	if absf(dir.x) >= absf(dir.y):
		facing = Vector2i.RIGHT if dir.x > 0.0 else Vector2i.LEFT
	else:
		facing = Vector2i.DOWN if dir.y > 0.0 else Vector2i.UP


func _on_damaged(amount: int, source_id: int) -> void:
	hp = health.hp
	if data.summon_count > 0 and _summons_done < data.summon_at.size() and health.hp > 0 \
			and float(health.hp) / health.max_hp <= data.summon_at[_summons_done]:
		_summons_done += 1
		_summon()
	if source_id != 0 and state != State.RETURN:
		_damage_by[source_id] = int(_damage_by.get(source_id, 0)) + amount
		add_threat(source_id, float(amount))


func _on_died(killer_id: int) -> void:
	_slow_until_ms = 0
	_stun_until_ms = 0
	status = Status.NONE
	hp = 0
	state = State.DEAD
	velocity = Vector2.ZERO
	_target = 0
	_respawn_at_ms = Time.get_ticks_msec() + int(data.respawn_time * 1000.0)
	var damage_by := _damage_by.duplicate()
	_forget()
	Combat.monster_killed(self, killer_id, damage_by)
	if data.is_boss:
		_reset_boss()
	if temporary:
		# Chamado pelo chefe: a fumaca aparece e ele some (o spawner tira dos clientes)
		get_tree().create_timer(1.5).timeout.connect(queue_free)


func _respawn() -> void:
	position = home
	net_position = home
	if data.hp_per_extra_player > 0.0:
		health.max_hp = data.max_hp
		max_hp = data.max_hp
	health.reset()
	hp = health.hp
	_forget()
	state = State.IDLE


# ---------- servidor: chefe (pacote B) ----------

## Vida conforme quantos jogadores estao na luta, cuspe em quem fica longe e
## os cuspes marcados que ja devem cair.
func _boss_tick(now: int) -> void:
	for i in range(_spits.size() - 1, -1, -1):
		if now >= int(_spits[i].at):
			var pos: Vector2 = _spits[i].pos
			_spits.remove_at(i)
			Combat.play_effect_in_zone(zone, "smoke", pos)
			Combat.area_damage(zone, pos, data.spit_radius, roundi(data.damage * data.spit_damage_mult))
	if state == State.DEAD or state == State.RETURN:
		return
	if data.hp_per_extra_player > 0.0 and now >= _next_scale_ms:
		_next_scale_ms = now + 1000
		_scale_health()
	if data.spit_every > 0.0 and state == State.CHASE and now >= _next_spit_ms:
		var far := _spit_target()
		if far != 0:
			_next_spit_ms = now + int(data.spit_every * 1000.0)
			var pos := Characters.position_of(far)
			_spits.append({"pos": pos, "at": now + int(data.spit_telegraph * 1000.0)})
			Combat.warn_area(zone, pos, data.spit_radius, data.spit_telegraph)
			attack_seq += 1  # o "bote" do cuspe


## Quem esta mais longe (fora do pisao, dentro do alcance do cuspe).
func _spit_target() -> int:
	var best := 0
	var best_d := data.slam_radius
	for id: int in _threat:
		if not Combat.can_be_attacked(id, zone):
			continue
		var d := position.distance_to(Characters.position_of(id))
		if d > best_d and d <= data.spit_range:
			best_d = d
			best = id
	return best


## Vida maxima = base x (1 + extra x (jogadores - 1)), mantendo a fracao.
func _scale_health() -> void:
	var n := 0
	for id in Characters.players_in_zone(zone):
		if Combat.can_be_attacked(id, zone) and Characters.position_of(id).distance_to(home) <= data.leash_range + 60.0:
			n += 1
	var target := roundi(data.max_hp * (1.0 + data.hp_per_extra_player * maxi(n - 1, 0)))
	if target == health.max_hp or health.hp <= 0:
		return
	var frac := float(health.hp) / health.max_hp
	health.max_hp = target
	health.hp = clampi(roundi(frac * target), 1, target)
	max_hp = target
	hp = health.hp


func _summon() -> void:
	var m_data := data_for(data.summon_id)
	if m_data == null:
		return
	for i in data.summon_count:
		var pos := position + Vector2.from_angle(TAU * i / data.summon_count) * (data.hitbox_radius + 14.0)
		var m := Combat.spawn_monster(zone, data.summon_id, pos, 20.0, "", true)
		if m:
			_summoned.append(m)
			m.taunt(_target)  # ja vem lutando
	for pid in Characters.players_in_zone(zone):
		NetworkManager.send_system_message(pid, "%s chama reforços!" % data.display_name)


## Chefe voltou para casa ou morreu: limpa cuspes, reforcos e a vida extra.
func _reset_boss() -> void:
	_spits.clear()
	_summons_done = 0
	for m in _summoned:
		if is_instance_valid(m) and not m.is_queued_for_deletion():
			m.queue_free()
	_summoned.clear()
	if data.hp_per_extra_player > 0.0 and state != State.DEAD:
		health.max_hp = data.max_hp
		health.reset()
		max_hp = data.max_hp
		hp = health.hp


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
	var lost := hp - value
	hp = value
	if not is_node_ready():
		return
	_refresh_visuals()
	if lost > 0 and not multiplayer.is_server() and state != State.DEAD:
		_sprite.modulate = Color(3, 3, 3)
		create_tween().tween_property(_sprite, "modulate", _tint(), 0.18)
		FloatingText.spawn(get_parent().get_parent(), position + Vector2(0, _sprite.position.y * 2.0 + 18.0), str(lost), FloatingText.DAMAGE, data.is_boss)
		GameAudio.play_at("hit", position)


func _set_state(value: State) -> void:
	var was_dead := state == State.DEAD
	state = value
	if not is_node_ready() or multiplayer.is_server():
		return
	_windup_visual(value == State.WINDUP)
	if value == State.DEAD and not was_dead:
		# No mapa da zona, nao no container de rede (Monsters so tem monstros)
		var fx := SMOKE.instantiate()
		fx.position = position + Vector2(0, -6)
		get_parent().get_parent().add_child(fx)
		GameAudio.play_at("monster_die", position)
	elif was_dead and value != State.DEAD:
		position = net_position
	_refresh_visuals()


## Cliente: azulado (lento) ou gelo (congelado, animacao parada).
func _set_status(value: Status) -> void:
	status = value
	if not is_node_ready() or multiplayer.is_server():
		return
	_sprite.modulate = _tint()
	if value == Status.FROZEN:
		_sprite.pause()
	else:
		_sprite.play()


## Cliente: pisca avermelhado e recua um pouco enquanto prepara o golpe.
func _windup_visual(on: bool) -> void:
	if _windup_tween:
		_windup_tween.kill()
		_windup_tween = null
	if not on:
		_sprite.self_modulate = Color.WHITE
		return
	_windup_tween = create_tween().set_loops()
	_windup_tween.tween_property(_sprite, "self_modulate", WINDUP_TINT, 0.09)
	_windup_tween.tween_property(_sprite, "self_modulate", Color.WHITE, 0.09)
	var back := create_tween()
	back.tween_property(_sprite, "offset", -Vector2(facing) * 2.0, 0.12)


## Cor do desenho: variante do monstro x efeito (lento/congelado).
func _tint() -> Color:
	return (data.tint if data else Color.WHITE) * STATUS_TINT[status]


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


## Cliente: recuo curto do sprite para longe de quem acertou (so visual).
func knockback(from: Vector2) -> void:
	if state == State.DEAD:
		return
	var push := (global_position - from).normalized() * 3.0
	var t := create_tween()
	t.tween_property(_sprite, "offset", push, 0.05)
	t.tween_property(_sprite, "offset", Vector2.ZERO, 0.12)


func _refresh_visuals() -> void:
	var dead := state == State.DEAD
	_sprite.visible = not dead
	$Shadow.visible = not dead
	_bar.max_value = max_hp
	_bar.value = hp
	_bar.visible = not dead and hp < max_hp
