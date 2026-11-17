extends Node
## Teste de rede do conteudo da 1.0 (pacotes C, E e F): um bot entra num
## servidor com conta nova, escolhe classe e cor, anda ate o Anciao e aceita
## a primeira missao, anda ate o Mercador, vende as pocoes iniciais e tenta
## comprar sem ouro. Tudo conferido no retrato que o SERVIDOR manda.
##   godot --headless --path . res://tools/test_rede_conteudo.tscn -- \
##     --join=127.0.0.1 --port=N --user=X --pass=Y --create --no-update
## Sai com codigo 1 se algo falhar.

const TIMEOUT_SEC := 90.0

var _fails := 0
var _shot_dir := ""
var _main: Node
var _player: Player


func _ready() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://client.cfg")
	cfg.set_value("ui", "tutorial_seen", true)
	cfg.save("user://client.cfg")
	get_tree().create_timer(TIMEOUT_SEC).timeout.connect(func() -> void:
		print("TEMPO ESGOTADO")
		get_tree().quit(1))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot_dir = a.trim_prefix("--shot=")
	_run.call_deferred()


## Captura da tela do jogo de verdade (so com janela e --shot=PASTA).
func _shot(name: String) -> void:
	if _shot_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/jogo_%s.png" % [_shot_dir, name])


func _check(cond: bool, what: String) -> void:
	print(("  ok    " if cond else "  FALHA ") + what)
	if not cond:
		_fails += 1


func _run() -> void:
	get_tree().current_scene = null
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	while not (get_tree().current_scene and get_tree().current_scene.name == "Game" \
			and NetworkManager.is_logged_in() and not PlayerData.me.is_empty()):
		await get_tree().process_frame
	_main = get_tree().current_scene
	_player = _main.get("_player")
	var me := PlayerData.me
	print("Personagem novo:")
	_check(int(me.get("gold", -1)) == 0, "comeca sem ouro")
	_check(PlayerData.count_in(me.inventory, "pocao") == 3, "comeca com 3 pocoes")
	_check(not bool(me.get("tutorial_seen", true)), "ajuda ainda nao vista nesta conta")
	PlayerData.choose_class("arqueiro", 2)
	while String(PlayerData.me.get("class", "")) == "":
		await get_tree().process_frame
	await _wait(0.5)
	_check(int(PlayerData.me.get("outfit", 0)) == 2, "cor da roupa escolhida ficou salva (2)")
	_check(_player.get_node("Sprite").material != null, "boneco com a cor escolhida")
	_check(bool(PlayerData.me.get("tutorial_seen", false)), "ajuda marcada como vista na conta")
	var hud0: GameHud = _main.get("_game_hud")
	_check(hud0.controls.visible, "ajuda abriu sozinha no primeiro jogo da conta")
	hud0.controls.close()  # senao o teclado do bot fica preso na janela

	print("Missao do Anciao:")
	await _walk_to_npc("Anciao")
	var hud: GameHud = _main.get("_game_hud")
	_main.call("_talk_to_nearest_npc")
	await _wait(0.4)
	_check(hud.dialogue.visible, "E perto do Anciao abre a conversa")
	await _shot("dialogo_anciao")
	hud.dialogue.close()
	PlayerData.accept_quest("gosma_na_horta")
	await _wait(0.6)
	await _shot("hud_com_missao")
	_check(PlayerData.quest_state(PlayerData.me.quests, "gosma_na_horta") == "active", "aceitou Gosma na horta perto do Anciao")
	PlayerData.accept_quest("carta_ao_guarda")
	await _wait(0.6)
	_check(PlayerData.quest_state(PlayerData.me.quests, "carta_ao_guarda") == "", "servidor recusa missao fora de ordem")

	print("Mercador:")
	PlayerData.buy("mercador", "pocao")  # longe do Mercador ainda
	await _wait(0.5)
	_check(PlayerData.count_in(PlayerData.me.inventory, "pocao") == 3, "longe do mercador nao compra")
	await _walk_to_npc("Mercador")
	var slot := -1
	for i in PlayerData.me.inventory.size():
		var s: Variant = PlayerData.me.inventory[i]
		if s is Dictionary and s.id == "pocao":
			slot = i
	for k in 3:
		PlayerData.sell(slot)
		await _wait(0.3)
	var gold := int(PlayerData.me.get("gold", 0))
	hud.shop.open(_main.get("_map").get_node("Npcs/Mercador"))
	await _wait(0.3)
	await _shot("comercio")
	hud.shop.close()
	var each := PlayerData.sell_price(PlayerData.item("pocao"))
	_check(gold == 3 * each, "vendeu 3 pocoes por %d de ouro (tem %d)" % [3 * each, gold])
	PlayerData.buy("mercador", "pocao")
	await _wait(0.5)
	_check(int(PlayerData.me.get("gold", 0)) == gold and PlayerData.count_in(PlayerData.me.inventory, "pocao") == 0,
			"sem ouro suficiente nao compra")
	PlayerData.buy("mercador", "lamina_do_rei")
	await _wait(0.5)
	_check(PlayerData.count_in(PlayerData.me.inventory, "lamina_do_rei") == 0, "nao compra o que o mercador nao vende")
	print("RESULTADO: %s" % ("OK" if _fails == 0 else "%d FALHA(S)" % _fails))
	get_tree().quit(1 if _fails > 0 else 0)


## Anda ate ficar a menos de 26 px do NPC (o servidor aceita ate 40).
func _walk_to_npc(npc_name: String) -> void:
	var map: Node = _main.get("_map")
	var npc := map.get_node("Npcs/" + npc_name) as Node2D
	var last := _player.global_position
	var stuck := 0.0
	var side := Vector2.ZERO
	var t := 0.0
	while t < 25.0:
		var to := npc.global_position + Vector2(0, 14) - _player.global_position
		if to.length() <= 10.0:
			break
		_steer(to.normalized() if side == Vector2.ZERO else side)
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		if _player.global_position.distance_to(last) < 0.3:
			stuck += dt
			if stuck > 0.4:
				side = to.normalized().orthogonal() * (1.0 if randf() < 0.5 else -1.0)
				stuck = -0.5
		elif stuck < 0.0:
			stuck += dt
			if stuck >= 0.0:
				side = Vector2.ZERO
		else:
			stuck = 0.0
		last = _player.global_position
	_release()
	await _wait(0.4)  # a posicao chega ao servidor ~10x/s
	_check(_player.global_position.distance_to(npc.global_position) <= 30.0, "chegou perto do %s" % npc_name)


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


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout
