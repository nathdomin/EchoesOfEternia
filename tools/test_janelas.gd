extends Node
## Teste das janelas com escolhas pelo teclado (dialogo, classe, pausa, ajuda).
## godot --headless --path . res://tools/test_janelas.tscn
## Sem --headless e com "-- --shot=PASTA" salva capturas de cada janela.

const NPC_SCENE := preload("res://scenes/npc/npc.tscn")

var _fails := 0
var _shot_dir := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot_dir = a.trim_prefix("--shot=")
	PlayerData.me = {"level": 1, "xp": 0, "xp_next": 40, "class": "guerreiro", "quests": {},
			"quest_progress": {}, "inventory": [], "equipment": {}}
	var layer := CanvasLayer.new()
	add_child(layer)
	await _test_dialogue(layer)
	await _test_class_chooser(layer)
	await _test_pause(layer)
	await _test_help(layer)
	_test_fonts()
	await _test_tracker(layer)
	print("RESULTADO: ", "OK" if _fails == 0 else "%d FALHA(S)" % _fails)
	get_tree().quit(1 if _fails else 0)


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FALHOU", what])
	if not ok:
		_fails += 1


func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()


func _press(action: StringName) -> void:
	for pressed in [true, false]:
		var e := InputEventAction.new()
		e.action = action
		e.pressed = pressed
		Input.parse_input_event(e)
		await get_tree().process_frame
	await get_tree().process_frame


func _frames(n := 2) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	if _shot_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shot_dir, name])


func _test_dialogue(layer: CanvasLayer) -> void:
	print("Dialogo:")
	var npc: Npc = NPC_SCENE.instantiate()
	npc.npc_id = "anciao"
	npc.display_name = "Ancião"
	add_child(npc)
	var box := DialogueBox.new()
	layer.add_child(box)
	await _frames()
	# Com missao para oferecer: Aceitar + Ate logo
	box.open(npc)
	await _frames()
	var f := _focus() as Button
	_check(f != null and f.text == "Aceitar", "com missão: foco em Aceitar")
	_check(f != null and f.icon == UiKit.ARROW, "seta no botão focado")
	await _shot("dialogo_missao")
	await _press(&"ui_right")
	f = _focus() as Button
	_check(f != null and f.text == "Até logo", "seta para a direita vai para Até logo")
	await _press(&"ui_right")
	f = _focus() as Button
	_check(f != null and f.text == "Aceitar", "e dá a volta")
	await _press(&"ui_up")
	_check(_focus() is Button and (_focus() as Button).text == "Até logo", "seta para cima também troca")
	# Sem missao (todas entregues): so Ate logo, ja com foco; Enter fecha
	var done := {}
	for q in PlayerData.quests_of("anciao"):
		done[q.id] = {"state": "done"}
	PlayerData.me.quests = done
	box.open(npc)
	await _frames()
	f = _focus() as Button
	_check(f != null and f.text == "Até logo", "sem missão: foco em Até logo")
	await _shot("dialogo_sem_missao")
	await _press(&"ui_accept")
	_check(not box.visible, "Enter em Até logo fecha")
	PlayerData.me.quests = {}
	box.queue_free()
	npc.queue_free()


func _test_class_chooser(layer: CanvasLayer) -> void:
	print("Escolha de classe:")
	PlayerData.me["class"] = ""
	var cc := ClassChooser.new()
	layer.add_child(cc)
	await _frames(3)
	_check(cc.visible, "aparece sem classe")
	var f := _focus() as Button
	_check(f != null and f.text == "Escolher", "foco na primeira carta")
	await _press(&"ui_right")
	var second := _focus()
	_check(second != null and second != f, "seta troca de carta")
	await _shot("classe")
	await _press(&"ui_accept")
	_check((_focus() as Button).text == "Confirmar?", "primeiro Enter pede confirmação")
	await _shot("classe_confirmar")
	await _press(&"ui_left")
	await _press(&"ui_right")
	_check((_focus() as Button).text == "Escolher", "trocar de carta cancela a confirmação")
	PlayerData.me["class"] = "guerreiro"
	PlayerData.changed.emit()
	await _frames()
	cc.queue_free()


func _test_pause(layer: CanvasLayer) -> void:
	print("Pausa:")
	var p := PauseMenu.new()
	layer.add_child(p)
	await _frames()
	p.open()
	await _frames()
	var f := _focus() as Button
	_check(f != null and f.text == "Continuar" and f.icon == UiKit.ARROW, "foco e seta em Continuar")
	await _press(&"ui_down")
	await _press(&"ui_down")
	await _press(&"ui_down")
	_check(_focus() is HSlider, "setas descem até o volume")
	await _shot("pausa_volume")
	p.queue_free()


func _test_help(layer: CanvasLayer) -> void:
	print("Ajuda:")
	var c := ControlsWindow.new()
	layer.add_child(c)
	await _frames()
	c.open(0)
	await _frames()
	await _press(&"ui_right")
	await _shot("ajuda_aba2")
	_check(c._pages[1].visible and not c._pages[0].visible, "seta troca a aba")
	c.queue_free()


## Pacote A: caracteres usados nos textos existem na fonte padrao (Pixelify).
func _test_fonts() -> void:
	print("Fonte:")
	var font := ThemeDB.get_project_theme().default_font
	for ch in ["·", "…", "ã", "ç", "é", "í", "ó", "ú", "â", "ê", "ô", "à", "Á"]:
		_check(font.has_char(ch.unicode_at(0)), "Pixelify tem \"%s\"" % ch)


## Pacote A: rastreador com largura fixa e nome de quem recebe a missao.
func _test_tracker(layer: CanvasLayer) -> void:
	print("Rastreador:")
	var t := QuestTracker.new()
	t.position = Vector2(480 - 164, 22)
	t.custom_minimum_size.x = 160
	layer.add_child(t)
	PlayerData.me.quests = {"o_rei_slime": {"state": "active"}, "gosma_na_horta": {"state": "active"}}
	PlayerData.me.quest_progress = {"o_rei_slime": 1, "gosma_na_horta": 2}
	PlayerData.changed.emit()
	await _frames(3)
	var texts: PackedStringArray = []
	for c in t.get_children():
		if c is Label and not c.is_queued_for_deletion():
			texts.append(c.text)
	_check("Volte ao Guarda Florestal" in texts, "missão pronta diz a quem voltar %s" % [texts])
	_check(t.get_rect().end.x <= 480.0, "não sai da tela (termina em x %.0f)" % t.get_rect().end.x)
	await _shot("rastreador")
	t.queue_free()
