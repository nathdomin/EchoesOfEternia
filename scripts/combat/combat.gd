extends Node
## Autoload "Combat" (E11-E14): ataque validado no servidor, vida dos
## jogadores, monstros por zona, morte e renascimento.
##
## Fluxo do ataque: o cliente toca a animacao e chama request_attack(dir)
## -> o servidor confere (vivo, recarga, posicao validada) -> acerta os
## monstros no cone a frente (HitboxComponent) -> aplica o dano
## (HealthComponent) -> a vida chega aos clientes pelo Sync do monstro.
##
## Vida do jogador: fica no RemotePlayer do servidor (HealthComponent). Os
## outros veem pelo Sync do avatar; o dono recebe por _own_health.

signal own_health_changed(hp: int, max_hp: int)
signal own_died(respawn_seconds: float)
signal own_respawned(pos: Vector2)
## Servidor: um jogador derrotou um monstro (a E16 da XP aqui).
signal monster_defeated(killer_id: int, monster: Monster)
## Cliente: o proprio ataque acertou este monstro (para o quadro do alvo).
signal own_hit(monster_path: NodePath)

const BASE_STATS := preload("res://resources/combat/player_base.tres")
const MONSTER_SCENE := preload("res://scenes/combat/monster.tscn")
const RESPAWN_SECONDS := 5.0
## Folga na recarga do ataque (lag/quadros irregulares).
const COOLDOWN_SLACK := 0.85

# Cliente: vida do proprio personagem
var my_hp := 0
var my_max_hp := 0
var my_dead := false

# ---------- so no servidor ----------
## peer -> { "next_attack_ms": int, "dead": bool, "respawn_at_ms": int }
var _players: Dictionary = {}
## zona -> Node2D "Monsters"
var _monster_roots: Dictionary = {}
var _regen_timer := 0.0


func _ready() -> void:
	NetworkManager.account_logged_in.connect(_on_logged_in)
	NetworkManager.account_logged_out.connect(func(id: int, _k: String) -> void: _players.erase(id))
	NetworkManager.connection_ended.connect(func(_r: String) -> void: my_dead = false)


# ---------- API do servidor ----------

## Cria os monstros dos MonsterSpawnPoint da zona (no "Monsters" dela).
func register_zone(zone: String, map: Node) -> void:
	var root: Node2D = map.get_node("Monsters")
	_monster_roots[zone] = root
	var spawns := map.get_node_or_null("MonsterSpawns")
	if spawns == null:
		return
	var n := 0
	for node in spawns.get_children():
		var point := node as MonsterSpawnPoint
		if point == null or point.monster == null:
			continue
		for i in point.count:
			var m := MONSTER_SCENE.instantiate() as Monster
			m.monster_id = point.monster.id
			m.zone = zone
			m.wander_radius = point.radius
			var angle := TAU * i / point.count
			m.position = point.position + Vector2.from_angle(angle) * point.radius * 0.5
			m.name = "%s_%d" % [point.monster.id, n]
			(m.get_node("Sync") as MultiplayerSynchronizer).add_visibility_filter(
					func(peer: int) -> bool: return Characters.zone_of(peer) == zone)
			root.add_child(m, true)
			n += 1
	_log("%d monstros na zona %s" % [n, zone])


func is_dead(id: int) -> bool:
	return _players.has(id) and _players[id].dead


## Monstros podem atacar este jogador?
func can_be_attacked(id: int, zone: String) -> bool:
	return _players.has(id) and not _players[id].dead and Characters.zone_of(id) == zone


func monster_attack(monster: Monster, target_id: int, damage: int) -> void:
	if not can_be_attacked(target_id, monster.zone):
		return
	var avatar := Characters.avatar_of(target_id)
	if avatar == null:
		return
	avatar.health.take_damage(damage, 0)


func monster_killed(monster: Monster, killer_id: int) -> void:
	if killer_id != 0 and _players.has(killer_id):
		NetworkManager.send_system_message(killer_id, "Você derrotou %s." % monster.display_name())
	monster_defeated.emit(killer_id, monster)


# ---------- API do cliente ----------

## O cliente atacou na direcao `dir` (o servidor decide se acertou).
func request_attack(dir: Vector2i) -> void:
	if NetworkManager.is_logged_in() and not my_dead:
		_request_attack.rpc_id(1, dir)


# ---------- servidor: login, vida, morte ----------

func _on_logged_in(id: int, _account: String, _name: String) -> void:
	var avatar := Characters.avatar_of(id)
	if avatar == null:
		return
	var saved := Characters.saved_hp(id)
	avatar.health.max_hp = BASE_STATS.max_hp
	avatar.health.reset(saved)
	avatar.sync_health()
	_players[id] = {"next_attack_ms": 0, "dead": false, "respawn_at_ms": 0}
	avatar.health.damaged.connect(func(_a: int, _s: int) -> void: _on_player_health(id))
	avatar.health.healed.connect(func(_a: int) -> void: _on_player_health(id))
	avatar.health.died.connect(func(_s: int) -> void: _on_player_died(id))
	_own_health.rpc_id(id, avatar.health.hp, avatar.health.max_hp)


func _on_player_health(id: int) -> void:
	var avatar := Characters.avatar_of(id)
	if avatar == null:
		return
	avatar.sync_health()
	_own_health.rpc_id(id, avatar.health.hp, avatar.health.max_hp)


func _on_player_died(id: int) -> void:
	if not _players.has(id):
		return
	_players[id].dead = true
	_players[id].respawn_at_ms = Time.get_ticks_msec() + int(RESPAWN_SECONDS * 1000.0)
	Characters.avatar_of(id).dead = true
	_own_died.rpc_id(id, RESPAWN_SECONDS)
	_log("%s morreu" % NetworkManager.player_name(id))


func _respawn(id: int) -> void:
	var p: Dictionary = _players[id]
	p.dead = false
	var avatar := Characters.avatar_of(id)
	if avatar == null:
		return
	var pos := Characters.respawn_position(id)
	Characters.teleport(id, pos)
	avatar.health.reset()
	avatar.dead = false
	avatar.sync_health()
	_own_health.rpc_id(id, avatar.health.hp, avatar.health.max_hp)
	_own_respawned.rpc_id(id, pos)


func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server() or _players.is_empty():
		return
	var now := Time.get_ticks_msec()
	for id: int in _players.keys():
		if _players[id].dead and now >= _players[id].respawn_at_ms:
			_respawn(id)
	# Regeneracao fora de combate, 1x por segundo
	_regen_timer += delta
	if _regen_timer < 1.0:
		return
	_regen_timer = 0.0
	for id: int in _players:
		var avatar := Characters.avatar_of(id)
		if avatar == null or _players[id].dead:
			continue
		var h: HealthComponent = avatar.health
		if h.hp < h.max_hp and h.seconds_since_damage() >= BASE_STATS.regen_delay:
			h.heal(maxi(1, roundi(h.max_hp * BASE_STATS.regen_per_sec)))


# ---------- RPCs ----------

@rpc("any_peer", "call_remote", "reliable")
func _request_attack(dir: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not _players.has(id) or _players[id].dead:
		return
	if not dir in [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]:
		return
	var now := Time.get_ticks_msec()
	if now < _players[id].next_attack_ms:
		return  # rapido demais: ignora
	_players[id].next_attack_ms = now + int(BASE_STATS.attack_cooldown * 1000.0 * COOLDOWN_SLACK)
	var zone := Characters.zone_of(id)
	var avatar := Characters.avatar_of(id)
	if zone.is_empty() or avatar == null or not _monster_roots.has(zone):
		return
	avatar.attack_seq += 1  # os outros veem o golpe
	# O golpe sai do centro do corpo (8 px acima dos pes)
	var origin := Characters.position_of(id) + Vector2(0, -6)
	for m: Monster in _monster_roots[zone].get_children():
		if m.is_dead() or not m.hitbox.is_hit_by(origin, Vector2(dir), BASE_STATS.reach):
			continue
		m.health.take_damage(BASE_STATS.damage, id)
		_hit_confirmed.rpc_id(id, get_path_to(m))


@rpc("authority", "call_remote", "reliable")
func _own_health(hp: int, max_hp: int) -> void:
	my_hp = hp
	my_max_hp = max_hp
	own_health_changed.emit(hp, max_hp)


@rpc("authority", "call_remote", "reliable")
func _own_died(respawn_seconds: float) -> void:
	my_dead = true
	own_died.emit(respawn_seconds)


@rpc("authority", "call_remote", "reliable")
func _own_respawned(pos: Vector2) -> void:
	my_dead = false
	own_respawned.emit(pos)


@rpc("authority", "call_remote", "reliable")
func _hit_confirmed(monster_path: NodePath) -> void:
	own_hit.emit(monster_path)


func _log(text: String) -> void:
	print("[%s] [Combate] %s" % [Time.get_time_string_from_system(), text])
