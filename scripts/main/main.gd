extends Node2D
## Cena do cliente: so abre depois do login aceito no menu (E7). Coloca o
## player onde o personagem parou (E8, enviado pelo servidor) e avisa o
## servidor da posicao enquanto anda. Na E9 o spawn dos jogadores passa a
## ser feito pelo servidor (MultiplayerSpawner).
##
## Combate (E12-E14): Espaco/J ataca na direcao do personagem; clique ou
## Tab escolhe o alvo (quadro no topo); Esc limpa o alvo. Ao morrer, conta
## o tempo ate renascer no ponto inicial da zona.
##
## Gate 3 (E16-E22): 1-3 habilidades, 4 pocao, I inventario, E conversar
## com NPC, Enter chat, G convida o jogador selecionado. Esc fecha a janela
## aberta, depois limpa o alvo, depois abre a pausa (de onde se sai do jogo).
##
## Queda de conexao (E10): o jogo fica na tela com "Reconectando..." e tenta
## voltar com o token de sessao (sem pedir a senha), esperando cada vez mais
## entre as tentativas (~40 s no total com o tempo de cada conexao; cobre o
## servidor reiniciando sozinho na VM, que leva ~6 s).
## Se o servidor recusar (sessao expirada, manutencao, conta em outro lugar)
## ou as tentativas acabarem, volta ao menu com o motivo.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const REPORT_INTERVAL := 0.1  ## segundos entre avisos de posicao ao servidor
const TARGET_PICK_RADIUS := 12.0  ## px em volta do clique
const TARGET_TAB_RANGE := 160.0
const NPC_RANGE := 30.0
## Espera antes de cada tentativa de reconexao (segundos).
const RECONNECT_DELAYS := [1.0, 2.0, 3.0, 4.0, 5.0]

var _last_sent_pos := Vector2.INF
var _last_sent_facing := Vector2i.ZERO
var _report_timer := 0.0
## -1 = conectado; 0+ = tentativas de reconexao ja feitas
var _reconnect_attempt := -1
var _respawn_left := 0.0
var _zone := ""
var _last_hp := -1
## Para os sons de item/missao (comparar o retrato anterior com o novo).
var _last_item_total := -1
var _last_done_quests := -1
var _last_ready_quests := -1
var _player_light: PointLight2D
var _music_check := 0.0

## Mapa da zona atual (Village, Forest ou Dungeon; todas usam o script Village).
@onready var _map: Village = $World/Village
@onready var _player: Player = $World/Player
@onready var _hud: NetHud = $NetHud
@onready var _game_hud: GameHud = $GameHud


func _ready() -> void:
	var s := Characters.spawn
	_switch_map(String(s.get("zone", "village")))
	if s.has("position"):
		_player.place(s.position, s.facing)
	else:
		_player.place(_map.get_spawn_position(), Vector2i.DOWN)
	Characters.zone_changed.connect(_on_zone_changed)
	_last_sent_pos = _player.global_position
	_last_sent_facing = _player.facing
	Characters.position_corrected.connect(func(pos: Vector2) -> void: _player.place(pos, _player.facing))
	_player.setup_look(s.get("skin", "knight"), NetworkManager.player_name(multiplayer.get_unique_id()))
	_game_hud.setup_player(_player.skin, NetworkManager.player_name(multiplayer.get_unique_id()))
	_game_hud.set_health(Combat.my_hp, Combat.my_max_hp)
	Combat.own_health_changed.connect(_game_hud.set_health)
	Combat.own_health_changed.connect(_on_own_health)
	Combat.own_died.connect(_on_died)
	Combat.boss_slam_seen.connect(func(pos: Vector2) -> void:
		var d := pos.distance_to(_player.global_position)
		if d < 160.0:
			_player.shake(4.0 * (1.0 - d / 160.0) + 1.0, 0.35))
	PlayerData.changed.connect(_on_player_data_changed)
	_on_player_data_changed()
	Combat.own_respawned.connect(_on_respawned)
	Combat.own_hit.connect(_on_own_hit)
	Combat.own_dodged.connect(func() -> void:
		FloatingText.spawn(_map, _player.global_position, "esquivou", FloatingText.XP))
	$NetHud/Log.visible = false  # o chat mostra as mensagens de sistema
	_game_hud.hotbar.slot_clicked.connect(_use_slot)
	_game_hud.pause_menu.help_requested.connect(func() -> void: _game_hud.controls.open())
	_game_hud.pause_menu.leave_requested.connect(func() -> void:
		NetworkManager.leave()
		_back_to_menu(""))
	PlayerData.level_up.connect(func(level: int) -> void:
		_hud.show_banner("Nível %d!" % level)
		get_tree().create_timer(2.0).timeout.connect(func() -> void:
			if _respawn_left <= 0.0 and _reconnect_attempt < 0:
				_hud.show_banner("")))
	# Agora os spawners existem: o servidor pode mandar os outros jogadores
	Characters.notify_ready()

	NetworkManager.connection_ended.connect(_on_connection_ended)
	NetworkManager.connection_lost.connect(_on_connection_lost)
	NetworkManager.connection_ready.connect(_on_reconnected)
	if not NetworkManager.is_logged_in():
		# Aberta sem login (F6 nesta cena, ou a conexao caiu no fade do menu)
		_back_to_menu.call_deferred("Faça login para entrar no mundo.")


func _process(delta: float) -> void:
	_music_check -= delta
	if _music_check <= 0.0:
		_music_check = 0.5
		_update_boss_music()
	if _respawn_left > 0.0:
		_respawn_left -= delta
		_game_hud.show_death(maxf(_respawn_left, 0.0))


func _physics_process(delta: float) -> void:
	_player.input_locked = _game_hud.blocks_input()
	_report_timer += delta
	if _report_timer < REPORT_INTERVAL:
		return
	_report_timer = 0.0
	var pos := _player.global_position
	if pos.distance_to(_last_sent_pos) > 0.5 or _player.facing != _last_sent_facing:
		_last_sent_pos = pos
		_last_sent_facing = _player.facing
		Characters.report_position(pos, _player.facing)


# ---------- reconexao ----------

func _on_connection_lost() -> void:
	_reconnect_attempt = 0
	_player.set_physics_process(false)
	_player.place(_player.global_position, _player.facing)
	_clear_remote_players()
	_try_reconnect()


func _try_reconnect() -> void:
	if _reconnect_attempt >= RECONNECT_DELAYS.size():
		_back_to_menu("Não foi possível reconectar ao servidor. Verifique a internet e entre de novo.")
		return
	var delay: float = RECONNECT_DELAYS[_reconnect_attempt]
	_reconnect_attempt += 1
	_hud.show_banner("Conexão perdida. Reconectando... (%d/%d)" % [_reconnect_attempt, RECONNECT_DELAYS.size()])
	await get_tree().create_timer(delay).timeout
	if not is_inside_tree() or _reconnect_attempt < 0:
		return
	Session.setup_resume()
	if NetworkManager.start_from_session() != OK:
		_try_reconnect()


func _on_connection_ended(reason: String) -> void:
	# Tentativa de reconexao que nao conectou (servidor ainda fora): tenta de novo
	if _reconnect_attempt >= 0 and not NetworkManager.last_end_was_rejection:
		_try_reconnect()
		return
	_back_to_menu(reason)


func _on_reconnected() -> void:
	if _reconnect_attempt < 0:
		return
	_reconnect_attempt = -1
	_hud.show_banner("")
	# Caiu durante a contagem da morte: a sessao nova ja nasce viva (o
	# servidor gravou o personagem renascido na vila); sai da tela de morte.
	if _player.is_dead:
		_respawn_left = 0.0
		_game_hud.show_death(-1.0)
		_player.set_dead(false)
	var s := Characters.spawn
	_switch_map(String(s.get("zone", "village")))
	if s.has("position"):
		_player.place(s.position, s.facing)
	_last_sent_pos = _player.global_position
	_last_sent_facing = _player.facing
	_player.set_physics_process(true)
	Characters.notify_ready()


## Os outros jogadores e os monstros voltam pelo spawner depois de reconectar.
func _clear_remote_players() -> void:
	_game_hud.set_target(null)
	for container in [_map.get_node("Players"), _map.get_node("Monsters")]:
		for c in container.get_children():
			container.remove_child(c)
			c.queue_free()


# ---------- zonas (E23) ----------

## Troca o mapa carregado para `zone` (o no tem o mesmo nome que no servidor).
func _switch_map(zone: String) -> void:
	var node_name := Zones.node_name(zone)
	if _map and _map.name == node_name:
		_player.set_camera_limits(_map.get_bounds())
		_apply_zone_look(zone)
		return
	var path: String = Zones.SCENES.get(zone, Zones.SCENES.village)
	var new_map := (load(path) as PackedScene).instantiate() as Village
	new_map.name = node_name
	if _map:
		# O mapa antigo fica escondido e sem colisao por 1 s: as remocoes do
		# spawner da zona antiga ainda podem chegar e precisam achar os nos
		# (pelo caminho, entao o nome do no nao pode mudar).
		var old := _map
		old.visible = false
		for layer in old.find_children("*", "TileMapLayer", true, false):
			(layer as TileMapLayer).collision_enabled = false
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			if is_instance_valid(old):
				old.queue_free())
	# Voltou rapido para uma zona cujo mapa antigo ainda nao saiu: tira agora
	var stale := $World.get_node_or_null(node_name)
	if stale:
		stale.free()
	_map = new_map
	$World.add_child(new_map)
	_player.set_camera_limits(_map.get_bounds())
	_apply_zone_look(zone)


## Musica e clima da zona (cor, folhas, vaga-lumes, escuro com luz no jogador).
func _apply_zone_look(zone: String) -> void:
	_zone = zone
	_hud.set_zone(Zones.display_name(zone))
	GameAudio.play_music(Zones.MUSIC.get(zone, ""))
	GameAudio.play_ambience(Zones.AMBIENCE.get(zone, {}))
	var look := Zones.look(zone)
	var amb := $Ambience
	amb.position = Vector2.ZERO
	(amb.get_node("Tint") as CanvasModulate).color = look.tint
	var b := _map.get_bounds()
	for n: String in ["Leaves", "Fireflies"]:
		var p := amb.get_node(n) as CPUParticles2D
		p.position = b.get_center()
		p.emission_rect_extents = b.size / 2.0
	var leaves := amb.get_node("Leaves") as CPUParticles2D
	leaves.visible = look.leaves
	leaves.emitting = look.leaves
	var flies := amb.get_node("Fireflies") as CPUParticles2D
	flies.visible = look.fireflies > 0
	flies.emitting = look.fireflies > 0
	if look.fireflies > 0 and flies.amount != look.fireflies:
		flies.amount = look.fireflies
	var vig := amb.get_node("Screen/Vignette") as ColorRect
	(vig.material as ShaderMaterial).set_shader_parameter("strength", look.vignette)
	if _player_light == null:
		_player_light = PointLight2D.new()
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.5, Color(1, 1, 1, 0.55))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.width = 176
		tex.height = 176
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		_player_light.texture = tex
		_player_light.color = Color(1.0, 0.85, 0.6)
		_player_light.energy = 0.6
		_player_light.position = Vector2(0, -6)
		_player.add_child(_player_light)
	_player_light.enabled = look.light


func _on_zone_changed(zone: String, pos: Vector2) -> void:
	_game_hud.set_target(null)
	_game_hud.dialogue.close()
	_switch_map(zone)
	_player.place(pos, _player.facing)
	_last_sent_pos = pos
	Characters.notify_ready()
	GameAudio.play("zone")
	_hud.show_banner(Zones.display_name(zone))
	get_tree().create_timer(2.0).timeout.connect(func() -> void:
		if _respawn_left <= 0.0 and _reconnect_attempt < 0:
			_hud.show_banner(""))


# ---------- combate ----------

func _on_died(respawn_seconds: float) -> void:
	_player.set_dead(true)
	GameAudio.play("death", 0.0)
	_respawn_left = respawn_seconds
	_hud.show_banner("")
	_game_hud.set_target(null)
	_game_hud.show_death(respawn_seconds)


func _on_respawned(pos: Vector2) -> void:
	_respawn_left = 0.0
	_game_hud.show_death(-1.0)
	_player.set_dead(false)
	_player.place(pos, Vector2i.DOWN)
	_last_sent_pos = pos
	_hud.show_banner("Você renasceu na %s." % Zones.display_name(_zone))
	_game_hud.chat.add_line("sistema", "", "Você renasceu na praça da %s com a vida cheia." % Zones.display_name(_zone))
	get_tree().create_timer(3.0).timeout.connect(func() -> void:
		if _respawn_left <= 0.0 and _reconnect_attempt < 0:
			_hud.show_banner(""))


## Chefe vivo perto (lutando ou a vista): musica de luta; senao a da zona.
func _update_boss_music() -> void:
	if _zone.is_empty() or _reconnect_attempt >= 0:
		return
	var fighting := false
	for m in _map.get_node("Monsters").get_children():
		if m is Monster and m.data and m.data.is_boss and not m.is_dead() \
				and m.position.distance_to(_player.global_position) < 200.0:
			fighting = true
	GameAudio.play_music(Zones.BOSS_MUSIC if fighting else Zones.MUSIC.get(_zone, ""))


## Vida propria mudou: numero de dano/cura, som e tremor.
func _on_own_health(hp: int, max_hp: int) -> void:
	var before := _last_hp
	_last_hp = hp
	if before < 0 or _player.is_dead:
		return
	var delta := hp - before
	if delta < 0:
		FloatingText.spawn(_map, _player.global_position, str(-delta), FloatingText.HURT)
		GameAudio.play("hurt")
		_player.shake(2.0)
	elif delta >= maxi(8, max_hp / 12):
		FloatingText.spawn(_map, _player.global_position, "+%d" % delta, FloatingText.HEAL)


## Sons de item recebido, missao pronta e missao entregue.
func _on_player_data_changed() -> void:
	var me := PlayerData.me
	if me.is_empty():
		return
	var items := 0
	for s in me.get("inventory", []):
		if s is Dictionary:
			items += int(s.n)
	var done := 0
	var ready_n := 0
	for qid: String in me.get("quests", {}):
		var st := PlayerData.quest_state(me.quests, qid)
		var q := PlayerData.quest(qid)
		if st == "done":
			done += 1
		elif q and int(me.get("quest_progress", {}).get(qid, 0)) >= q.count:
			ready_n += 1
	if _last_done_quests >= 0:
		if done > _last_done_quests or ready_n > _last_ready_quests:
			GameAudio.play("quest", 0.0)
		elif items > _last_item_total:
			GameAudio.play("pickup")
	_last_item_total = items
	_last_done_quests = done
	_last_ready_quests = ready_n


## O servidor confirmou um acerto: sem alvo, o monstro atingido vira o alvo.
## `heavy` = 3o golpe do combo (pausa e tremor maiores).
func _on_own_hit(monster_path: NodePath, heavy: bool) -> void:
	var m := Combat.get_node_or_null(monster_path) as Node2D
	if m and (_game_hud.target == null or not is_instance_valid(_game_hud.target)):
		_game_hud.set_target(m)
	if m is Monster:
		(m as Monster).knockback(_player.global_position)
		_hitstop(HITSTOP_HEAVY_SEC if heavy else HITSTOP_SEC)
		if heavy:
			_player.shake(1.5, 0.12)


## Pausa curtissima no impacto (so o visual deste cliente): o golpe "pesa".
const HITSTOP_SEC := 0.04
const HITSTOP_HEAVY_SEC := 0.08
var _hitstop_on := false


func _exit_tree() -> void:
	Engine.time_scale = 1.0  # saiu no meio de uma pausa de impacto


func _hitstop(seconds: float) -> void:
	if _hitstop_on:
		return
	_hitstop_on = true
	Engine.time_scale = 0.05
	await get_tree().create_timer(seconds, true, false, true).timeout
	Engine.time_scale = 1.0
	_hitstop_on = false


func _targets() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for m in _map.get_node("Monsters").get_children():
		if m is Monster and not m.is_dead():
			out.append(m)
	for p in _map.get_node("Players").get_children():
		if p is RemotePlayer:
			out.append(p)
	return out


func _select_at(world_pos: Vector2) -> void:
	var best: Node2D = null
	var best_d := TARGET_PICK_RADIUS
	for t in _targets():
		var d := t.global_position.distance_to(world_pos + Vector2(0, 7))
		if d < best_d:
			best_d = d
			best = t
	if best:
		_game_hud.set_target(best)


## Tab: proximo monstro vivo mais perto (em volta).
func _cycle_target() -> void:
	var near: Array[Node2D] = []
	for t in _targets():
		if t is Monster and t.global_position.distance_to(_player.global_position) <= TARGET_TAB_RANGE:
			near.append(t)
	if near.is_empty():
		return
	near.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return a.global_position.distance_to(_player.global_position) < b.global_position.distance_to(_player.global_position))
	var i := near.find(_game_hud.target)
	_game_hud.set_target(near[(i + 1) % near.size()])


## Teclas que valem mesmo com o chat ou uma janela aberta.
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if _game_hud.chat.is_open:
		if event.is_action("ui_cancel"):
			_game_hud.chat.close()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("help"):
		_game_hud.pause_menu.close()
		_game_hud.controls.toggle()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		if _game_hud.controls.visible:
			_game_hud.controls.close()
		elif _game_hud.pause_menu.visible:
			_game_hud.pause_menu.close()
		elif _game_hud.dialogue.visible:
			_game_hud.dialogue.close()
		elif _game_hud.inventory.visible:
			_game_hud.inventory.toggle()
		elif _game_hud.target != null:
			_game_hud.set_target(null)
		elif not _game_hud.class_chooser.visible:
			_game_hud.pause_menu.open()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("chat") and not _game_hud.blocks_input():
		_game_hud.chat.open.call_deferred()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("chat_command") and not _game_hud.blocks_input():
		_game_hud.chat.open.call_deferred("/")
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_panel"):
		_game_hud.debug_panel.toggle()
		return
	if _game_hud.blocks_input():
		return
	for i in 4:
		if event.is_action_pressed("ability_%d" % (i + 1)):
			_use_slot(i)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("inventory"):
		_game_hud.inventory.toggle()
		return
	if event.is_action_pressed("interact"):
		_talk_to_nearest_npc()
		return
	if event.is_action_pressed("party_invite"):
		if _game_hud.target is RemotePlayer:
			Social.invite(_game_hud.target.display_name)
		else:
			_game_hud.chat.add_line("sistema", "", "Selecione um jogador (clique nele) e aperte G para convidar.")
		return
	if event.is_action_pressed("attack") and _reconnect_attempt < 0:
		var cls := PlayerData.class_data(String(PlayerData.me.get("class", "")))
		var aim := _attack_aim(cls.reach)
		if _player.try_attack(cls.attack_cooldown, aim, cls.reach) > 0:
			Combat.request_attack(aim, _player.global_position)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("dodge") and _reconnect_attempt < 0:
		if _player.try_dodge():
			Combat.request_dodge()
		elif not _player.is_dead:
			GameAudio.play("error", 0.0)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("target_next"):
		_cycle_target()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_at(get_global_mouse_position())
		return


## Mira do golpe basico: o alvo selecionado, se estiver perto o bastante
## para o corte encostar; senao, para onde o personagem olha.
func _attack_aim(reach: float) -> Vector2:
	var m := _game_hud.target as Monster
	if m and is_instance_valid(m) and not m.is_dead():
		var to := m.hitbox.center() - (_player.global_position + Combat.BODY)
		if to.length() > 0.5 and to.length() <= reach * (HitboxComponent.ARC_FORWARD + HitboxComponent.ARC_RADIUS) + m.hitbox.radius + 6.0:
			return to.normalized()
	return Vector2(_player.facing)


## Barra: 0-2 habilidades da classe, 3 pocao.
func _use_slot(i: int) -> void:
	if _reconnect_attempt >= 0 or _player.is_dead:
		return
	if i == 3:
		if _game_hud.hotbar.try_use(3):
			PlayerData.use_potion()
		else:
			GameAudio.play("error", 0.0)
		return
	var ab := _game_hud.hotbar.ability(i)
	if ab == null or not _game_hud.hotbar.try_use(i):
		return
	# Habilidade de alvo: vira o personagem para o alvo
	var target := _game_hud.target as Monster
	if target and ab.kind in [AbilityData.Kind.RANGED, AbilityData.Kind.AREA_TARGET]:
		var d := target.global_position - _player.global_position
		_player.facing = (Vector2i.RIGHT if d.x > 0 else Vector2i.LEFT) if absf(d.x) >= absf(d.y) \
				else (Vector2i.DOWN if d.y > 0 else Vector2i.UP)
	_player.play_cast()
	Combat.request_ability(i, _player.facing, target)


func _talk_to_nearest_npc() -> void:
	# Bau perto (e ainda cheio para mim) vem primeiro
	var chests := _map.get_node_or_null("Chests")
	if chests:
		for c in chests.get_children():
			if c is Chest and c.global_position.distance_to(_player.global_position) <= Chest.OPEN_RANGE:
				if c.is_open_for_me():
					var left := ceili(PlayerData.chest_seconds_left(c.zone(), c.name) / 60.0)
					_game_hud.chat.add_line("sistema", "", "Este baú já foi aberto. Volta a encher em %d min." % left)
				else:
					GameAudio.play("chest")
					PlayerData.open_chest(c.name)
				return
	var npcs := _map.get_node_or_null("Npcs")
	if npcs == null:
		return
	for n in npcs.get_children():
		if n is Npc and n.global_position.distance_to(_player.global_position) <= NPC_RANGE:
			_game_hud.dialogue.open(n)
			return


func _back_to_menu(reason: String) -> void:
	if not reason.is_empty():
		print("[Rede] Voltando ao menu: ", reason)
	Session.last_error = reason
	Session.reset()
	get_tree().change_scene_to_file(MENU_SCENE)
