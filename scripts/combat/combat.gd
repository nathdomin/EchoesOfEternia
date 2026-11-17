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
##
## Vida do jogador: fica no RemotePlayer do servidor (HealthComponent). Os
## outros veem pelo Sync do avatar; o dono recebe por _own_health.

signal own_health_changed(hp: int, max_hp: int)
signal own_died(respawn_seconds: float)
signal own_respawned(pos: Vector2)
## Servidor: um jogador derrotou um monstro (a E16 da XP aqui).
signal monster_defeated(killer_id: int, monster: Monster)
## Cliente: o proprio ataque acertou este monstro (para o quadro do alvo).
## `heavy` = 3o golpe do combo.
signal own_hit(monster_path: NodePath, heavy: bool)
## Cliente: a esquiva evitou um golpe.
signal own_dodged
## Cliente: um chefe deu o pisao em `pos` (tremor de tela se perto).
signal boss_slam_seen(pos: Vector2)

const BASE_STATS := preload("res://resources/combat/player_base.tres")
const MONSTER_SCENE := preload("res://scenes/combat/monster.tscn")
const RESPAWN_SECONDS := 5.0
## Folga na recarga do ataque (lag/quadros irregulares).
const COOLDOWN_SLACK := 0.85
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
	if _dodging(target_id):
		_dodged.rpc_id(target_id)
		return
	avatar.health.take_damage(damage, 0)


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
				avatar.health.take_damage(damage, 0)


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
## servidor decide se acertou).
func request_attack(aim: Vector2, pos: Vector2) -> void:
	if NetworkManager.is_logged_in() and not my_dead:
		_request_attack.rpc_id(1, aim, pos)


## O cliente comecou uma esquiva (o servidor libera o movimento extra e
## alguns instantes sem dano).
func request_dodge() -> void:
	if NetworkManager.is_logged_in() and not my_dead:
		_request_dodge.rpc_id(1)


## Habilidade `index` (0-2) da classe, mirando `target` (pode ser null).
func request_ability(index: int, dir: Vector2i, target: Node) -> void:
	if NetworkManager.is_logged_in() and not my_dead:
		_request_ability.rpc_id(1, index, dir, get_path_to(target) if target else NodePath())


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
	_players[id].respawn_at_ms = Time.get_ticks_msec() + int(RESPAWN_SECONDS * 1000.0)
	Characters.avatar_of(id).dead = true
	_own_died.rpc_id(id, RESPAWN_SECONDS)
	_log("%s morreu" % NetworkManager.player_name(id))


func _respawn(id: int) -> void:
	var p: Dictionary = _players[id]
	p.dead = false
	if Characters.avatar_of(id) == null:
		return
	# Renasce sempre na praca da vila (o comeco do jogo); de outra zona, a
	# troca de mapa vem antes do aviso de renascimento.
	var pos := Characters.home_position()
	if String(Characters.data_of(id).get("zone", "")) != Characters.home_zone():
		Characters.move_to_zone(id, Characters.home_zone(), pos)
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
		if h.hp < h.max_hp and h.seconds_since_damage() >= BASE_STATS.regen_delay:
			h.heal(maxi(1, roundi(h.max_hp * BASE_STATS.regen_per_sec)))


# ---------- RPCs ----------

@rpc("any_peer", "call_remote", "reliable")
func _request_attack(aim: Vector2, at: Vector2) -> void:
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
	if now < p.next_attack_ms:
		return  # rapido demais: ignora
	var st := PlayerData.stats_of(id)
	p.next_attack_ms = now + int(st.attack_cooldown * 1000.0 * COOLDOWN_SLACK)
	var zone := Characters.zone_of(id)
	var avatar := Characters.avatar_of(id)
	if zone.is_empty() or avatar == null or not _monster_roots.has(zone):
		return
	# Combo: golpes seguidos dentro da janela contam 1, 2, 3, 1...
	var step := (int(p.combo) % 3) + 1 if now <= int(p.combo_until) else 1
	p.combo = step
	p.combo_until = now + int((st.attack_cooldown + BASE_STATS.combo_window) * 1000.0)
	var heavy := step == 3
	avatar.facing = cardinal(aim)
	avatar.attack_seq += 1  # os outros veem o golpe
	# Posicao do cliente se estiver perto da validada (a validada chega atrasada)
	var feet := Characters.position_of(id)
	if at.is_finite() and at.distance_to(feet) <= ATTACK_POS_TOLERANCE:
		feet = at
	var origin := feet + BODY
	var damage := roundi(st.damage * (BASE_STATS.combo_finisher_mult if heavy else 1.0))
	for m: Monster in _monster_roots[zone].get_children():
		if not m.can_be_hit() or not m.hitbox.is_hit_by(origin, aim, st.reach):
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
	if now < int(_players[id].next_dodge_ms):
		return
	_players[id].next_dodge_ms = now + int(BASE_STATS.dodge_cooldown * 1000.0 * COOLDOWN_SLACK)
	_players[id].invuln_until = now + int(BASE_STATS.dodge_invuln * 1000.0)
	Characters.grant_dash(id, BASE_STATS.dodge_distance + 8.0)


## Direcao cardinal mais proxima (horizontal no empate).
static func cardinal(v: Vector2) -> Vector2i:
	if absf(v.x) >= absf(v.y):
		return Vector2i.RIGHT if v.x > 0.0 else Vector2i.LEFT
	return Vector2i.DOWN if v.y > 0.0 else Vector2i.UP


@rpc("any_peer", "call_remote", "reliable")
func _request_ability(index: int, dir: Vector2i, target_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not _players.has(id) or _players[id].dead:
		return
	if not dir in [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]:
		return
	var st := PlayerData.stats_of(id)
	var cls: ClassData = st["class"]
	if String(Characters.data_of(id).get("class", "")) == "" or index < 0 or index >= cls.abilities.size():
		return
	var ab: AbilityData = cls.abilities[index]
	var now := Time.get_ticks_msec()
	var cds: Dictionary = _players[id].cooldowns
	if now < int(cds.get(ab.id, 0)):
		return
	cds[ab.id] = now + int(ab.cooldown * 1000.0 * COOLDOWN_SLACK)
	var zone := Characters.zone_of(id)
	var avatar := Characters.avatar_of(id)
	if zone.is_empty() or avatar == null:
		return
	avatar.facing = dir  # os outros veem o lancamento pelo _ability_fx
	var origin := Characters.position_of(id) + BODY
	var damage := roundi(st.damage * ab.power)
	# Alvo escolhido pelo cliente: so vale se for um monstro vivo da zona
	var target: Monster = null
	if not target_path.is_empty():
		target = get_node_or_null(target_path) as Monster
	if target and (not target.can_be_hit() or target.zone != zone):
		target = null
	var hits: Array[Monster] = []
	var fx_at := origin
	match ab.kind:
		AbilityData.Kind.MELEE_AROUND:
			for m in _alive_monsters(zone):
				if m.hitbox.overlaps(origin, ab.radius):
					hits.append(m)
		AbilityData.Kind.MELEE_CONE:
			for m in _alive_monsters(zone):
				if m.hitbox.is_hit_by(origin, Vector2(dir), ab.range):
					hits.append(m)
			fx_at = HitboxComponent.arc_center(origin, Vector2(dir), ab.range)
		AbilityData.Kind.RANGED:
			if target == null or target.hitbox.center().distance_to(origin) > ab.range + target.hitbox.radius:
				target = _nearest_in_front(zone, origin, Vector2(dir), ab.range)
			if target:
				hits.append(target)
				fx_at = target.hitbox.center()
			else:
				fx_at = origin + Vector2(dir) * ab.range * 0.5
		AbilityData.Kind.AREA_TARGET:
			fx_at = origin + Vector2(dir) * ab.range * 0.5
			if target and target.hitbox.center().distance_to(origin) <= ab.range:
				fx_at = target.hitbox.center()
			for m in _alive_monsters(zone):
				if m.hitbox.overlaps(fx_at, ab.radius):
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
	for m in hits:
		if ab.threat > 1.0:
			m.add_threat(id, damage * (ab.threat - 1.0))
		m.health.take_damage(damage, id)
		_hit_confirmed.rpc_id(id, get_path_to(m), false)
	for pid in Characters.players_in_zone(zone):
		_ability_fx.rpc_id(pid, ab.id, origin, fx_at, id)


## Monstros da zona que podem ser atingidos (vivos e nao voltando para casa).
func _alive_monsters(zone: String) -> Array[Monster]:
	var out: Array[Monster] = []
	if _monster_roots.has(zone):
		for m: Monster in _monster_roots[zone].get_children():
			if m.can_be_hit():
				out.append(m)
	return out


func _nearest_in_front(zone: String, origin: Vector2, dir: Vector2, reach: float) -> Monster:
	var best: Monster = null
	var best_d := INF
	for m in _alive_monsters(zone):
		var to := m.hitbox.center() - origin
		var d := to.length()
		if d <= reach + m.hitbox.radius and d < best_d and (d < 8.0 or dir.dot(to / d) >= 0.7):
			best = m
			best_d = d
	return best


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
			GameAudio.play_at("throw" if ab.projectile and ab.id != "bola_de_fogo" else "magic", from)
		AbilityData.Kind.AREA_TARGET:
			GameAudio.play_at("magic", from)
		AbilityData.Kind.HEAL:
			GameAudio.play_at("heal", from)
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
			if ab.kind == AbilityData.Kind.AREA_TARGET:
				GameAudio.play_at("explosion", to)


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
