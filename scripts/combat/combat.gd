extends Node
## Autoload "Combat" (E11-E14, E17): ataque e habilidades validados no
## servidor, vida dos jogadores, monstros por zona, morte e renascimento.
## Atributos (vida, dano, alcance) vem de PlayerData.stats_of (classe +
## nivel + equipamento).
##
## Fluxo do ataque: o cliente toca a animacao e chama request_attack(mira,
## posicao) -> o servidor confere (vivo, recarga, posicao perto da validada)
## -> acerta os monstros no circulo do corte (HitboxComponent.is_hit_by) ->
## aplica o dano (HealthComponent) -> a vida chega pelo Sync do monstro.
## Combo: 3 golpes seguidos (CombatStats.combo_window); o 3o bate mais forte
## e empurra. Esquiva (Shift): corrida curta com alguns instantes sem dano.
## Revisao das classes: Arqueiro e Mago tem golpe basico de longe (projetil,
## ClassData.basic_range). A mira (alvo selecionado ou direcao) segue
## Targeting; habilidades saem em qualquer angulo e podem deixar lento,
## congelar, empurrar, provocar e proteger (AbilityData).
##
## Vida do jogador: fica no RemotePlayer do servidor (HealthComponent). Os
## outros veem pelo Sync do avatar; o dono recebe por _own_health.

signal own_health_changed(hp: int, max_hp: int)
signal own_died(respawn_seconds: float)
signal own_respawned(pos: Vector2)
## Servidor: um jogador derrotou um monstro (a E16 da XP aqui).
signal monster_defeated(killer_id: int, monster: Monster)
## Cliente: o proprio ataque acertou este monstro (para o quadro do alvo).
## Tambem chega das habilidades.
## `heavy` = 3o golpe do combo.
signal own_hit(monster_path: NodePath, heavy: bool)
## Cliente: a esquiva evitou um golpe.
signal own_dodged
## Cliente: um chefe deu o pisao em `pos` (tremor de tela se perto).
signal boss_slam_seen(pos: Vector2)
## Cliente: efeitos no proprio personagem { "poison": s, "guard": s } (pacote B).
signal own_status_changed(statuses: Dictionary)
## Cliente: XP perdida ao morrer (pacote B).
signal own_death_penalty(xp_lost: int)

const BASE_STATS := preload("res://resources/combat/player_base.tres")
const MONSTER_SCENE := preload("res://scenes/combat/monster.tscn")
const RESPAWN_SECONDS := 5.0
## Morrer custa esta fracao da XP que o nivel atual pede (nunca desce de nivel).
const DEATH_XP_PENALTY := 0.05
## Recarga com orcamento (pacote A): o pedido vale ate esta folga antes da
## hora (variacao da rede), mas a proxima hora conta da hora marcada, nao da
## chegada. Na media ninguem passa da recarga real (antes: 15% a menos sempre).
const COOLDOWN_TOLERANCE_MS := 150
## Linha de visao: golpes e projeteis param na colisao do mapa (camada 1:
## paredes, troncos, casas, baus).
const WALL_MASK := 1
## Centro do corpo do personagem em relacao aos pes (de onde saem os golpes).
const BODY := Vector2(0, -7)
## O cliente manda onde estava ao bater; vale se estiver ate aqui da posicao
## validada (que chega ~10x/s e pode estar um pouco atras).
const ATTACK_POS_TOLERANCE := 16.0
const GROUND_WARNING := preload("res://scripts/effects/ground_warning.gd")

# Cliente: vida do proprio personagem
var my_hp := 0
var my_max_hp := 0
var my_dead := false
## Cliente: efeitos ativos no proprio personagem (nome -> segundos que faltam).
var my_status: Dictionary = {}

# ---------- so no servidor ----------
## peer -> { "next_attack_ms": int, "dead": bool, "respawn_at_ms": int }
var _players: Dictionary = {}
## zona -> Node2D "Monsters"
var _monster_roots: Dictionary = {}
var _regen_timer := 0.0


func _ready() -> void:
	NetworkManager.account_logged_in.connect(_on_logged_in)
	Characters.avatar_replaced.connect(func(id: int) -> void:
		var avatar := Characters.avatar_of(id)
		if avatar and _players.has(id):
			_hook_avatar(id, avatar)
			avatar.sync_health()
			avatar.dead = false)
	NetworkManager.account_logged_out.connect(func(id: int, _k: String) -> void: _players.erase(id))
	NetworkManager.connection_ended.connect(func(_r: String) -> void: my_dead = false)
	# Reconexao (E10) depois de cair morto: a sessao nova comeca viva
	NetworkManager.connection_ready.connect(func() -> void: my_dead = false)


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
			var angle := TAU * i / point.count
			spawn_monster(zone, point.monster.id, point.position + Vector2.from_angle(angle) * point.radius * 0.5,
					point.radius, "%s_%d" % [point.monster.id, n])
			n += 1
	_log("%d monstros na zona %s" % [n, zone])


## Servidor: cria um monstro na zona (visivel so para quem esta nela).
## `temporary` = chamado pelo chefe: some ao morrer, sem renascer.
func spawn_monster(zone: String, monster_id: String, pos: Vector2, wander := 24.0,
		node_name := "", temporary := false) -> Monster:
	if not _monster_roots.has(zone):
		return null
	var m := MONSTER_SCENE.instantiate() as Monster
	m.monster_id = monster_id
	m.zone = zone
	m.wander_radius = wander
	m.temporary = temporary
	m.position = pos
	if not node_name.is_empty():
		m.name = node_name
	(m.get_node("Sync") as MultiplayerSynchronizer).add_visibility_filter(
			func(peer: int) -> bool: return Characters.zone_of(peer) == zone)
	(_monster_roots[zone] as Node).add_child(m, true)
	return m


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
	if _dodging(target_id):
		_dodged.rpc_id(target_id)
		return
	avatar.health.take_damage(_guarded(target_id, damage), 0)
	if monster.data.poison_dps > 0 and can_be_attacked(target_id, monster.zone):
		apply_poison(target_id, monster.data.poison_dps, monster.data.poison_seconds)


## Servidor: veneno (pacote B): `dps` de dano por segundo por `secs`. Fica o
## mais forte e renova a duracao.
func apply_poison(id: int, dps: int, secs: float) -> void:
	if not _players.has(id) or _players[id].dead or dps <= 0 or secs <= 0.0:
		return
	var p: Dictionary = _players[id]
	var now := Time.get_ticks_msec()
	p.poison_dps = maxi(int(p.get("poison_dps", 0)), dps) if now < int(p.get("poison_until", 0)) else dps
	p.poison_until = maxi(int(p.get("poison_until", 0)), now + int(secs * 1000.0))
	_push_status(id)


## Servidor: dano em area em `pos` (cuspe do chefe), com esquiva e Grito.
func area_damage(zone: String, pos: Vector2, radius: float, damage: int) -> void:
	for pid in Characters.players_in_zone(zone):
		if can_be_attacked(pid, zone) and Characters.position_of(pid).distance_to(pos) <= radius:
			var avatar := Characters.avatar_of(pid)
			if avatar and _dodging(pid):
				_dodged.rpc_id(pid)
			elif avatar:
				avatar.health.take_damage(_guarded(pid, damage), 0)


## Servidor: manda ao dono os efeitos ativos nele (barra de efeitos da HUD).
func _push_status(id: int) -> void:
	if not _players.has(id):
		return
	var p: Dictionary = _players[id]
	var now := Time.get_ticks_msec()
	var out := {}
	if now < int(p.get("poison_until", 0)):
		out["poison"] = (int(p.poison_until) - now) / 1000.0
	if now < int(p.get("guard_until", 0)):
		out["guard"] = (int(p.guard_until) - now) / 1000.0
	_own_status.rpc_id(id, out)


## Servidor: dano reduzido pelo Grito de Guerra (AbilityData.guard).
func _guarded(id: int, damage: int) -> int:
	if _players.has(id) and Time.get_ticks_msec() < int(_players[id].get("guard_until", 0)):
		return maxi(1, roundi(damage * float(_players[id].get("guard_mult", 1.0))))
	return damage


## Servidor: o jogador esta no meio da esquiva (sem levar dano)?
func _dodging(id: int) -> bool:
	return _players.has(id) and Time.get_ticks_msec() < int(_players[id].get("invuln_until", 0))


## Servidor: circulo de aviso no chao (pisao do chefe) para quem esta na zona.
func warn_area(zone: String, pos: Vector2, radius: float, seconds: float) -> void:
	for pid in Characters.players_in_zone(zone):
		_warning.rpc_id(pid, pos, radius, seconds)


## `damage_by` = dano de cada jogador (o credito vai para quem mais bateu).
func monster_killed(monster: Monster, killer_id: int, damage_by: Dictionary = {}) -> void:
	if monster.data.is_boss:
		var who := NetworkManager.player_name(killer_id) if killer_id != 0 else "Alguém"
		NetworkManager.broadcast_system_message("%s derrotou %s!" % [who, monster.display_name()])
	elif killer_id != 0 and _players.has(killer_id):
		NetworkManager.send_system_message(killer_id, "Você derrotou %s." % monster.display_name())
	monster_defeated.emit(killer_id, monster)
	PlayerData.award_kill(killer_id, monster, damage_by)


## Chefe: pisao que acerta todos os jogadores no raio.
func boss_slam(monster: Monster, radius: float, damage: int) -> void:
	play_effect_in_zone(monster.zone, "explosion", monster.position + Vector2(0, -8))
	for pid in Characters.players_in_zone(monster.zone):
		if can_be_attacked(pid, monster.zone) and Characters.position_of(pid).distance_to(monster.position) <= radius:
			var avatar := Characters.avatar_of(pid)
			if avatar and _dodging(pid):
				_dodged.rpc_id(pid)
			elif avatar:
				avatar.health.take_damage(_guarded(pid, damage), 0)


## Servidor: manda a vida atual para o dono.
func push_health(id: int) -> void:
	var avatar := Characters.avatar_of(id)
	if avatar and _players.has(id):
		_own_health.rpc_id(id, avatar.health.hp, avatar.health.max_hp)


## Servidor: efeito visual (scenes/effects/<id>.tscn) para quem esta na zona.
func play_effect_in_zone(zone: String, effect_id: String, pos: Vector2) -> void:
	for pid in Characters.players_in_zone(zone):
		_effect.rpc_id(pid, effect_id, pos)


## Servidor: efeito visual so para um jogador (ex.: brilho do bau dele).
func play_effect_for(id: int, effect_id: String, pos: Vector2) -> void:
	if _players.has(id):
		_effect.rpc_id(id, effect_id, pos)


# ---------- API do cliente ----------

## O cliente atacou mirando `aim` (normalizada) estando em `pos` (o
## servidor decide se acertou). `target`: alvo do golpe de longe (ou null).
func request_attack(aim: Vector2, pos: Vector2, target: Node = null) -> void:
	if NetworkManager.is_logged_in() and not my_dead:
		_request_attack.rpc_id(1, aim, pos, get_path_to(target) if target else NodePath())


## O cliente comecou uma esquiva (o servidor libera o movimento extra e
## alguns instantes sem dano).
func request_dodge() -> void:
	if NetworkManager.is_logged_in() and not my_dead:
		_request_dodge.rpc_id(1)


## Habilidade `index` (0-2) da classe na direcao `aim` (normalizada), com o
## alvo `target` (pode ser null).
func request_ability(index: int, aim: Vector2, target: Node) -> void:
	if NetworkManager.is_logged_in() and not my_dead:
		_request_ability.rpc_id(1, index, aim, get_path_to(target) if target else NodePath())


# ---------- servidor: login, vida, morte ----------

func _on_logged_in(id: int, _account: String, _name: String) -> void:
	var avatar := Characters.avatar_of(id)
	if avatar == null:
		return
	var saved := Characters.saved_hp(id)
	avatar.health.max_hp = PlayerData.stats_of(id).max_hp
	avatar.health.reset(saved)
	avatar.sync_health()
	_players[id] = {"next_attack_ms": 0, "dead": false, "respawn_at_ms": 0, "cooldowns": {},
			"combo": 0, "combo_until": 0, "next_dodge_ms": 0, "invuln_until": 0}
	_hook_avatar(id, avatar)
	_own_health.rpc_id(id, avatar.health.hp, avatar.health.max_hp)


## Liga a vida do avatar ao jogador (login e troca de zona).
func _hook_avatar(id: int, avatar: RemotePlayer) -> void:
	avatar.health.damaged.connect(func(_a: int, _s: int) -> void: _on_player_health(id))
	avatar.health.healed.connect(func(_a: int) -> void: _on_player_health(id))
	avatar.health.died.connect(func(_s: int) -> void: _on_player_died(id))


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
	_players[id].guard_until = 0  # o Grito e o veneno acabam com a morte
	_players[id].poison_until = 0
	_push_status(id)
	var lost := PlayerData.death_penalty(id, DEATH_XP_PENALTY)
	if lost > 0:
		_death_penalty.rpc_id(id, lost)
	_players[id].respawn_at_ms = Time.get_ticks_msec() + int(RESPAWN_SECONDS * 1000.0)
	Characters.avatar_of(id).dead = true
	_own_died.rpc_id(id, RESPAWN_SECONDS)
	_log("%s morreu" % NetworkManager.player_name(id))


func _respawn(id: int) -> void:
	var p: Dictionary = _players[id]
	p.dead = false
	if Characters.avatar_of(id) == null:
		return
	# Pacote B: renasce na entrada da zona onde morreu (na vila, a praca);
	# antes era sempre a vila, e da caverna a volta era longa demais.
	var zone := Characters.zone_of(id)
	if zone.is_empty():
		zone = Characters.home_zone()
	var pos := Characters.spawn_of(zone)
	if String(Characters.data_of(id).get("zone", "")) != zone:
		Characters.move_to_zone(id, zone, pos)
	else:
		Characters.teleport(id, pos)
	var avatar := Characters.avatar_of(id)
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
		# Envenenado: leva o dano 1x por segundo e nao regenera ate passar
		var p: Dictionary = _players[id]
		if int(p.get("poison_until", 0)) > 0:
			if now < int(p.poison_until):
				h.take_damage(int(p.poison_dps), 0)
				if _players[id].dead:
					continue
			else:
				p.poison_until = 0
				_push_status(id)
			continue
		if h.hp < h.max_hp and h.seconds_since_damage() >= BASE_STATS.regen_delay:
			h.heal(maxi(1, roundi(h.max_hp * BASE_STATS.regen_per_sec)))


# ---------- RPCs ----------

@rpc("any_peer", "call_remote", "reliable")
func _request_attack(aim: Vector2, at: Vector2, target_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not _players.has(id) or _players[id].dead:
		return
	if not aim.is_finite() or absf(aim.length() - 1.0) > 0.05:
		return
	aim = aim.normalized()
	var p: Dictionary = _players[id]
	var now := Time.get_ticks_msec()
	if not cooldown_ready(int(p.next_attack_ms), now):
		return  # rapido demais: ignora
	var zone := Characters.zone_of(id)
	var avatar := Characters.avatar_of(id)
	if zone.is_empty() or avatar == null or not _monster_roots.has(zone):
		return
	var st := PlayerData.stats_of(id)
	p.next_attack_ms = cooldown_next(int(p.next_attack_ms), now, st.attack_cooldown)
	avatar.facing = cardinal(aim)
	# Posicao do cliente se estiver perto da validada (a validada chega atrasada)
	var feet := Characters.position_of(id)
	if at.is_finite() and at.distance_to(feet) <= ATTACK_POS_TOLERANCE:
		feet = at
	var origin := feet + BODY
	var cls: ClassData = st["class"]
	if cls.is_ranged():
		# Golpe basico de longe: projetil no alvo ou no 1o monstro na linha
		var reach := _reach_until_wall(zone, origin, aim, cls.basic_range)
		var hit := _projectile_target(zone, origin, aim, reach, _valid_target(target_path, zone))
		var to := origin + aim * reach
		if hit:
			to = hit.hitbox.center()
			hit.health.take_damage(roundi(st.damage * cls.basic_power), id)
			_hit_confirmed.rpc_id(id, get_path_to(hit), false)
		for pid in Characters.players_in_zone(zone):
			_shot_fx.rpc_id(pid, cls.id, origin, to, id)
		return
	# Combo (so corpo a corpo): golpes seguidos dentro da janela contam 1, 2, 3, 1...
	var step := (int(p.combo) % 3) + 1 if now <= int(p.combo_until) else 1
	p.combo = step
	p.combo_until = now + int((st.attack_cooldown + BASE_STATS.combo_window) * 1000.0)
	var heavy := step == 3
	avatar.attack_seq += 1  # os outros veem o golpe
	var damage := roundi(st.damage * (BASE_STATS.combo_finisher_mult if heavy else 1.0))
	for m: Monster in _monster_roots[zone].get_children():
		if not m.can_be_hit() or not m.hitbox.is_hit_by(origin, aim, st.reach) \
				or not _clear_line(zone, origin, m.hitbox.center(), m.hitbox.radius):
			continue
		m.health.take_damage(damage, id)
		if heavy and m.can_be_hit():
			m.push_back((m.hitbox.center() - origin).normalized(), BASE_STATS.combo_knockback)
		_hit_confirmed.rpc_id(id, get_path_to(m), heavy)


@rpc("any_peer", "call_remote", "reliable")
func _request_dodge() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not _players.has(id) or _players[id].dead:
		return
	var now := Time.get_ticks_msec()
	if not cooldown_ready(int(_players[id].next_dodge_ms), now):
		return
	_players[id].next_dodge_ms = cooldown_next(int(_players[id].next_dodge_ms), now, BASE_STATS.dodge_cooldown)
	_players[id].invuln_until = now + int(BASE_STATS.dodge_invuln * 1000.0)
	Characters.grant_dash(id, BASE_STATS.dodge_distance + 8.0)


## Direcao cardinal mais proxima (horizontal no empate).
static func cardinal(v: Vector2) -> Vector2i:
	if absf(v.x) >= absf(v.y):
		return Vector2i.RIGHT if v.x > 0.0 else Vector2i.LEFT
	return Vector2i.DOWN if v.y > 0.0 else Vector2i.UP


@rpc("any_peer", "call_remote", "reliable")
func _request_ability(index: int, aim: Vector2, target_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not _players.has(id) or _players[id].dead:
		return
	if not aim.is_finite() or absf(aim.length() - 1.0) > 0.05:
		return
	aim = aim.normalized()
	var st := PlayerData.stats_of(id)
	var cls: ClassData = st["class"]
	if String(Characters.data_of(id).get("class", "")) == "" or index < 0 or index >= cls.abilities.size():
		return
	var ab: AbilityData = cls.abilities[index]
	var now := Time.get_ticks_msec()
	var cds: Dictionary = _players[id].cooldowns
	if not cooldown_ready(int(cds.get(ab.id, 0)), now):
		return
	var zone := Characters.zone_of(id)
	var avatar := Characters.avatar_of(id)
	if zone.is_empty() or avatar == null or not _monster_roots.has(zone):
		return  # sem gastar a recarga
	cds[ab.id] = cooldown_next(int(cds.get(ab.id, 0)), now, ab.cooldown)
	avatar.facing = cardinal(aim)  # os outros veem o lancamento pelo _ability_fx
	var origin := Characters.position_of(id) + BODY
	var damage := roundi(st.damage * ab.power)
	var target := _valid_target(target_path, zone)
	var hits: Array[Monster] = []
	var fx_at := origin
	match ab.kind:
		AbilityData.Kind.MELEE_AROUND, AbilityData.Kind.WARCRY, AbilityData.Kind.LEAP:
			for m in _alive_monsters(zone):
				if m.hitbox.overlaps(origin, ab.radius) and _clear_line(zone, origin, m.hitbox.center(), m.hitbox.radius):
					hits.append(m)
		AbilityData.Kind.MELEE_CONE:
			for m in _alive_monsters(zone):
				if m.hitbox.is_hit_by(origin, aim, ab.range) and _clear_line(zone, origin, m.hitbox.center(), m.hitbox.radius):
					hits.append(m)
			fx_at = HitboxComponent.arc_center(origin, aim, ab.range)
		AbilityData.Kind.RANGED:
			var reach := _reach_until_wall(zone, origin, aim, ab.range)
			fx_at = origin + aim * reach
			if ab.pierce:
				var alive := _alive_monsters(zone)
				for i in Targeting.ray_hits(origin, aim, reach, _hitboxes(alive)):
					hits.append(alive[i])
			else:
				var hit := _projectile_target(zone, origin, aim, reach, target)
				if hit:
					fx_at = hit.hitbox.center()
					hits.append(hit)
			if ab.splash > 0.0 and (not hits.is_empty() or not ab.pierce):
				for m in _alive_monsters(zone):
					if not m in hits and m.hitbox.overlaps(fx_at, ab.splash) \
						and _clear_line(zone, fx_at, m.hitbox.center(), m.hitbox.radius):
						hits.append(m)
		AbilityData.Kind.AREA_TARGET:
			fx_at = origin + aim * ab.range * 0.6
			if target and target.hitbox.center().distance_to(origin) <= ab.range + target.hitbox.radius:
				fx_at = target.hitbox.center()
			# A area cai do lado de ca da parede
			var to_area := fx_at - origin
			if to_area.length() > 0.5:
				fx_at = origin + to_area.normalized() * _reach_until_wall(zone, origin, to_area.normalized(), to_area.length())
			for m in _alive_monsters(zone):
				if m.hitbox.overlaps(fx_at, ab.radius) and _clear_line(zone, fx_at, m.hitbox.center(), m.hitbox.radius):
					hits.append(m)
		AbilityData.Kind.HEAL:
			var healed: Array[int] = [id]
			if ab.radius > 0.0:
				for pid in Social.party_members(id):
					if pid != id and Characters.zone_of(pid) == zone and not is_dead(pid) \
							and Characters.position_of(pid).distance_to(origin) <= ab.radius:
						healed.append(pid)
			var total_healed := 0
			for pid in healed:
				var a := Characters.avatar_of(pid)
				if a:
					total_healed += a.health.heal(roundi(a.health.max_hp * ab.power))
			# Curar quem esta lutando chama a atencao dos monstros (metade da cura)
			if total_healed > 0:
				for m in _alive_monsters(zone):
					for pid in healed:
						if m.is_fighting(pid):
							m.add_threat(id, total_healed * 0.5)
							break
	if ab.kind == AbilityData.Kind.WARCRY and ab.guard < 1.0:
		_players[id].guard_until = now + int(ab.guard_seconds * 1000.0)
		_players[id].guard_mult = ab.guard
		_push_status(id)
	if ab.kind == AbilityData.Kind.LEAP:
		Characters.grant_dash(id, ab.range + 8.0)
	for m in hits:
		_apply_ability(id, ab, damage if ab.power > 0.0 else 0, m, origin)
	for pid in Characters.players_in_zone(zone):
		_ability_fx.rpc_id(pid, ab.id, origin, fx_at, id)


## Servidor: dano e efeitos de uma habilidade num monstro.
func _apply_ability(id: int, ab: AbilityData, damage: int, m: Monster, origin: Vector2) -> void:
	if ab.kind == AbilityData.Kind.WARCRY:
		m.taunt(id)
	if damage > 0:
		if ab.threat > 1.0:
			m.add_threat(id, damage * (ab.threat - 1.0))
		m.health.take_damage(damage, id)
		_hit_confirmed.rpc_id(id, get_path_to(m), false)
	if not m.can_be_hit():
		return  # morreu com o golpe
	if ab.knockback > 0.0:
		m.push_back((m.hitbox.center() - origin).normalized(), ab.knockback)
	if ab.slow > 0.0:
		m.apply_slow(ab.slow, ab.slow_seconds)
	if ab.stun_seconds > 0.0:
		m.apply_stun(ab.stun_seconds)
	if damage == 0 and ab.kind != AbilityData.Kind.WARCRY:
		m.add_threat(id, 5.0)  # efeito sem dano tambem chama a atencao


## Alvo mandado pelo cliente: so vale se for um monstro vivo desta zona.
func _valid_target(path: NodePath, zone: String) -> Monster:
	if path.is_empty():
		return null
	var m := get_node_or_null(path) as Monster
	return m if m and m.can_be_hit() and m.zone == zone else null


## Projetil: o alvo, se estiver ao alcance e na direcao mirada (o cliente
## mirou nele); senao o 1o monstro na linha.
func _projectile_target(zone: String, origin: Vector2, aim: Vector2, reach: float, target: Monster) -> Monster:
	if target:
		var to := target.hitbox.center() - origin
		if to.length() <= reach + target.hitbox.radius and (to.length() < Targeting.CLOSE or aim.dot(to.normalized()) >= 0.8) \
				and _clear_line(zone, origin, target.hitbox.center(), target.hitbox.radius):
			return target
	var alive := _alive_monsters(zone)
	var on_line := Targeting.ray_hits(origin, aim, reach, _hitboxes(alive))
	return alive[on_line[0]] if not on_line.is_empty() else null


## Recarga com orcamento: pode usar? (`next_ms` = hora marcada da proxima)
static func cooldown_ready(next_ms: int, now: int) -> bool:
	return now >= next_ms - COOLDOWN_TOLERANCE_MS


## Proxima hora marcada: conta da hora anterior se o pedido veio adiantado.
static func cooldown_next(next_ms: int, now: int, seconds: float) -> int:
	return maxi(now, next_ms) + int(seconds * 1000.0)


## Servidor: recarga generica por jogador (ex.: "item:pocao"). Gasta e
## devolve verdadeiro se ja pode.
func use_cooldown(id: int, key: String, seconds: float) -> bool:
	if not _players.has(id):
		return false
	var cds: Dictionary = _players[id].cooldowns
	var now := Time.get_ticks_msec()
	if not cooldown_ready(int(cds.get(key, 0)), now):
		return false
	cds[key] = cooldown_next(int(cds.get(key, 0)), now, seconds)
	return true


## Servidor: ate onde um golpe/projetil vai de `from` na direcao `dir` antes
## de bater numa parede (posicoes locais da zona; no servidor as zonas ficam
## afastadas, entao o raio e feito na posicao global do mapa).
func _reach_until_wall(zone: String, from: Vector2, dir: Vector2, reach: float) -> float:
	var map := _zone_map(zone)
	if map == null or reach <= 0.0:
		return reach
	var offset := map.global_position
	var q := PhysicsRayQueryParameters2D.create(offset + from, offset + from + dir * reach, WALL_MASK)
	q.collide_with_areas = false
	var hit := map.get_world_2d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return reach
	return maxf(0.0, (hit.position - offset).distance_to(from) - 1.0)


## Servidor: nada solido entre `a` e `b`? `slack` = raio do alvo (um monstro
## encostado na parede pode ter o centro "dentro" da colisao dela).
func _clear_line(zone: String, a: Vector2, b: Vector2, slack := 2.0) -> bool:
	var d := b - a
	if d.length() <= slack:
		return true
	return _reach_until_wall(zone, a, d.normalized(), d.length()) >= d.length() - slack


func _zone_map(zone: String) -> Node2D:
	var root: Node = _monster_roots.get(zone)
	return root.get_parent() as Node2D if root else null


func _hitboxes(monsters: Array[Monster]) -> Array:
	var out := []
	for m in monsters:
		out.append(m.hitbox)
	return out


## Monstros da zona que podem ser atingidos (vivos e nao voltando para casa).
func _alive_monsters(zone: String) -> Array[Monster]:
	var out: Array[Monster] = []
	if _monster_roots.has(zone):
		for m: Monster in _monster_roots[zone].get_children():
			if m.can_be_hit():
				out.append(m)
	return out


## Servidor -> zona: efeito de habilidade (projetil de `from` ate `to` e efeito em `to`).
@rpc("authority", "call_remote", "reliable")
func _ability_fx(ability_id: String, from: Vector2, to: Vector2, caster_id: int) -> void:
	var path := "res://resources/abilities/%s.tres" % ability_id
	if not ability_id.is_valid_identifier() or not ResourceLoader.exists(path):
		return
	var ab: AbilityData = load(path)
	var world := _fx_parent()
	if world == null:
		return
	# Outro jogador lancou: pose de lancamento no avatar dele (sem corte de espada)
	if caster_id != multiplayer.get_unique_id():
		for map in world.get_children():
			var rp := map.get_node_or_null("Players/%d" % caster_id) as RemotePlayer
			if rp:
				rp.play_cast()
	match ab.kind:
		AbilityData.Kind.RANGED:
			GameAudio.play_at("throw" if ab.id == "tiro_perfurante" else "magic", from)
		AbilityData.Kind.AREA_TARGET:
			GameAudio.play_at("magic", from)
		AbilityData.Kind.HEAL:
			GameAudio.play_at("heal", from)
		AbilityData.Kind.WARCRY:
			GameAudio.play_at("slam", from)
		AbilityData.Kind.LEAP:
			GameAudio.play_at("dodge", from)
		_:
			GameAudio.play_at("swing", from)
	var delay := 0.0
	if ab.projectile:
		var p := Sprite2D.new()
		p.texture = ab.projectile
		p.position = from
		p.rotation = (to - from).angle() - deg_to_rad(ab.projectile_angle)
		p.z_index = 3
		world.add_child(p)
		delay = clampf(from.distance_to(to) / 260.0, 0.05, 0.5)
		var t := p.create_tween()
		t.tween_property(p, "position", to, delay)
		t.tween_callback(p.queue_free)
	if ab.effect:
		if delay > 0.0:
			await get_tree().create_timer(delay).timeout
		if is_instance_valid(world):
			var fx := ab.effect.instantiate() as Node2D
			fx.position = to
			world.add_child(fx)
			if ab.kind == AbilityData.Kind.AREA_TARGET or ab.splash > 0.0:
				GameAudio.play_at("explosion", to)


## Servidor -> zona: golpe basico de longe (projetil da classe de `from` ate `to`).
@rpc("authority", "call_remote", "reliable")
func _shot_fx(class_id: String, from: Vector2, to: Vector2, caster_id: int) -> void:
	if not class_id in PlayerData.CLASS_IDS:
		return
	var cls := PlayerData.class_data(class_id)
	var world := _fx_parent()
	if world == null or cls.basic_projectile == null or not from.is_finite() or not to.is_finite():
		return
	if caster_id != multiplayer.get_unique_id():
		for map in world.get_children():
			var rp := map.get_node_or_null("Players/%d" % caster_id) as RemotePlayer
			if rp:
				rp.play_cast()
	GameAudio.play_at("throw" if cls.id == "arqueiro" else "magic", from, 0.08)
	var p := Sprite2D.new()
	p.texture = cls.basic_projectile
	p.position = from
	p.rotation = (to - from).angle() - deg_to_rad(cls.basic_projectile_angle)
	p.z_index = 3
	world.add_child(p)
	var t := p.create_tween()
	t.tween_property(p, "position", to, clampf(from.distance_to(to) / 320.0, 0.05, 0.45))
	t.tween_callback(p.queue_free)


@rpc("authority", "call_remote", "reliable")
func _effect(effect_id: String, pos: Vector2) -> void:
	var path := "res://scenes/effects/%s.tscn" % effect_id
	var world := _fx_parent()
	if world == null or not effect_id.is_valid_identifier() or not ResourceLoader.exists(path):
		return
	var fx := (load(path) as PackedScene).instantiate() as Node2D
	fx.position = pos
	world.add_child(fx)
	match effect_id:
		"levelup":
			GameAudio.play_at("levelup", pos, 0.0)
		"explosion":
			GameAudio.play_at("slam", pos)
			boss_slam_seen.emit(pos)
		"spark":
			GameAudio.play_at("potion", pos)
		"smoke":
			GameAudio.play_at("slam", pos, 0.15)


## Onde os efeitos aparecem no cliente (o mundo da cena do jogo).
func _fx_parent() -> Node:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("World") if scene else null


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
func _own_status(statuses: Dictionary) -> void:
	my_status = statuses
	own_status_changed.emit(statuses)


@rpc("authority", "call_remote", "reliable")
func _death_penalty(xp_lost: int) -> void:
	own_death_penalty.emit(xp_lost)


@rpc("authority", "call_remote", "reliable")
func _hit_confirmed(monster_path: NodePath, heavy: bool) -> void:
	own_hit.emit(monster_path, heavy)


@rpc("authority", "call_remote", "reliable")
func _dodged() -> void:
	own_dodged.emit()


## Servidor -> zona: circulo de aviso no chao por `seconds`.
@rpc("authority", "call_remote", "reliable")
func _warning(pos: Vector2, radius: float, seconds: float) -> void:
	var world := _fx_parent()
	if world == null or not pos.is_finite() or radius <= 0.0 or radius > 200.0 or seconds <= 0.0 or seconds > 5.0:
		return
	var w := GROUND_WARNING.new() as Node2D
	w.position = pos
	w.set("radius", radius)
	w.set("seconds", seconds)
	world.add_child(w)


func _log(text: String) -> void:
	print("[%s] [Combate] %s" % [Time.get_time_string_from_system(), text])
