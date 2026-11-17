extends Node
## Teste de rede do combate (revisao das classes). Entra num servidor com
## uma classe, anda ate os monstros mais perto e usa o golpe basico e as 3
## habilidades, contando os acertos que o SERVIDOR confirma e conferindo os
## efeitos (lentidao/congelado nos monstros, salto do personagem).
## Uso (servidor rodando; conta nova para cada classe):
##   godot --headless --path . res://tools/test_rede_combate.tscn -- \
##     --join=127.0.0.1 --user=BotArq --pass=bot12345 --create --test-class=arqueiro
## Sai com codigo 1 se algo falhar.

const TIMEOUT_SEC := 90.0

var _cls := "guerreiro"
var _hits := 0
var _fails := 0
var _main: Node
var _player: Player


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test-class="):
			_cls = a.trim_prefix("--test-class=")
	# A ajuda F1 abre sozinha no 1o jogo e travaria o teclado do bot
	var cfg := ConfigFile.new()
	cfg.load("user://client.cfg")
	cfg.set_value("ui", "tutorial_seen", true)
	cfg.save("user://client.cfg")
	Combat.own_hit.connect(func(_p: NodePath, _h: bool) -> void: _hits += 1)
	get_tree().create_timer(TIMEOUT_SEC).timeout.connect(func() -> void:
		print("TEMPO ESGOTADO")
		get_tree().quit(1))
	_run.call_deferred()


func _check(cond: bool, what: String) -> void:
	print(("  ok    " if cond else "  FALHA ") + what)
	if not cond:
		_fails += 1


func _run() -> void:
	# Este no fica na raiz; o menu faz o login pela linha de comando
	get_tree().current_scene = null
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	while not (get_tree().current_scene and get_tree().current_scene.name == "Game" \
			and NetworkManager.is_logged_in() and not PlayerData.me.is_empty()):
		await get_tree().process_frame
	_main = get_tree().current_scene
	_player = _main.get("_player")
	if String(PlayerData.me.get("class", "")) == "":
		PlayerData.choose_class(_cls)
	while String(PlayerData.me.get("class", "")) != _cls:
		await get_tree().process_frame
	await _wait(1.0)
	var cls := PlayerData.class_data(_cls)
	_check(_player.skin == cls.skin, "boneco com a aparencia da classe logo ao escolher (%s)" % _player.skin)
	print("Classe %s (golpe basico %s):" % [cls.display_name, "de longe" if cls.is_ranged() else "de perto"])

	# Golpe basico: 3 vezes
	await _approach(cls)
	var before := _hits
	for i in 3:
		_press("attack")
		await _wait(cls.attack_cooldown + 0.15)
	_check(_hits > before, "golpe basico acerta (%d acertos)" % (_hits - before))

	# Habilidades 1-3
	for i in cls.abilities.size():
		var ab: AbilityData = cls.abilities[i]
		await _approach(cls, ab)
		before = _hits
		var start := _player.global_position
		_main.call("_use_slot", i)
		var status_seen := false
		for f in 40:  # ~0.7 s
			await get_tree().process_frame
			status_seen = status_seen or _any_status()
		var hits := _hits - before
		match ab.kind:
			AbilityData.Kind.LEAP:
				_check(_player.global_position.distance_to(start) >= 25.0, "%s: o personagem salta (%.0f px)" % [ab.display_name, _player.global_position.distance_to(start)])
			AbilityData.Kind.HEAL, AbilityData.Kind.WARCRY:
				_check(not _player.is_dead, "%s: lancada" % ab.display_name)
			_:
				_check(hits > 0, "%s: acerta (%d)" % [ab.display_name, hits])
		if ab.slow > 0.0 or ab.stun_seconds > 0.0:
			_check(status_seen, "%s: monstro fica %s" % [ab.display_name, "congelado" if ab.stun_seconds > 0.0 else "lento"])
		await _wait(0.4)
	print("RESULTADO: %s" % ("OK" if _fails == 0 else "%d FALHA(S)" % _fails))
	get_tree().quit(1 if _fails > 0 else 0)


## Anda ate ficar perto do monstro vivo mais proximo (de longe: a distancia
## de tiro; de perto: encostado). Monstros por perto tambem vem ate o bot.
func _approach(cls: ClassData, ab: AbilityData = null) -> void:
	var stop := 16.0
	if ab and ab.kind in [AbilityData.Kind.RANGED, AbilityData.Kind.AREA_TARGET]:
		stop = minf(ab.range * 0.6, 70.0)
	elif ab == null and cls.is_ranged():
		stop = minf(cls.basic_range * 0.6, 70.0)
	var last := _player.global_position
	var stuck := 0.0
	var side := Vector2.ZERO
	var t := 0.0
	while t < 20.0:
		var m := _nearest()
		if m == null:
			_release()
			await _wait(0.5)
			t += 0.5
			continue
		var to := m.global_position - _player.global_position
		if to.length() <= stop:
			break
		var dir := to.normalized() if side == Vector2.ZERO else side
		_steer(dir)
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		if _player.global_position.distance_to(last) < 0.3:
			stuck += dt
			if stuck > 0.4:  # preso num obstaculo: anda de lado um pouco
				side = to.normalized().orthogonal() * (1.0 if randf() < 0.5 else -1.0)
				stuck = -0.5
		elif stuck < 0.0:
			stuck += dt
			if stuck >= 0.0:
				side = Vector2.ZERO
		else:
			stuck = 0.0
		last = _player.global_position
	# Ultimo passo: olha para o monstro (a mira sem alvo e a direcao em que andou)
	var m := _nearest()
	if m:
		_steer((m.global_position - _player.global_position).normalized())
		await get_tree().physics_frame
	_release()
	await _wait(0.1)


func _nearest() -> Monster:
	var best: Monster = null
	var best_d := INF
	var map: Node = _main.get("_map")
	for m in map.get_node("Monsters").get_children():
		if m is Monster and not m.is_dead():
			var d := (m as Monster).global_position.distance_to(_player.global_position)
			if d < best_d:
				best_d = d
				best = m
	return best


func _any_status() -> bool:
	var map: Node = _main.get("_map")
	for m in map.get_node("Monsters").get_children():
		if m is Monster and (m as Monster).status != Monster.Status.NONE:
			return true
	return false


func _steer(dir: Vector2) -> void:
	_set_action("move_right", dir.x > 0.3)
	_set_action("move_left", dir.x < -0.3)
	_set_action("move_down", dir.y > 0.3)
	_set_action("move_up", dir.y < -0.3)


func _release() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(a)


func _set_action(action: String, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout
