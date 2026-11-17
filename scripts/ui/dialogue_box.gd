class_name DialogueBox
extends Control
## Conversa com NPC (E21) no estilo manuscrito: retrato, nome em letra
## gotica, texto em tinta e opcoes (aceitar/entregar a missao, sair).
## O servidor confere a distancia ate o NPC e o estado da missao.

signal closed
## Pacote C: o jogador escolheu "Comércio" com este NPC.
signal shop_requested(npc: Npc)

## 1.0.1: mais largo e com a fileira de botoes na largura toda (com Aceitar,
## Comercio e Ate logo juntos, os botoes passavam da borda da pagina).
const SIZE := Vector2(400, 118)
const BUTTONS_MARGIN := 16.0

var _page: ColorRect
var _face: TextureRect
var _name: Label
var _text: Label
var _buttons: HBoxContainer
var _npc: Npc


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	position = Vector2((480 - SIZE.x) / 2.0, 270 - SIZE.y - 30)
	size = SIZE
	_page = UiKit.parchment(SIZE, 5.0)
	add_child(_page)
	_face = TextureRect.new()
	_face.position = Vector2(14, 14)
	_face.size = Vector2(38, 38)
	add_child(_face)
	_name = UiKit.gothic("", 24, UiKit.RUBRIC)
	_name.position = Vector2(60, 6)
	add_child(_name)
	_text = UiKit.ink_text("", SIZE.x - 80)
	_text.position = Vector2(60, 28)
	add_child(_text)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 10)
	_buttons.alignment = BoxContainer.ALIGNMENT_END
	_buttons.position = Vector2(BUTTONS_MARGIN, SIZE.y - 34)
	_buttons.size = Vector2(SIZE.x - 2.0 * BUTTONS_MARGIN, 26)
	add_child(_buttons)
	PlayerData.changed.connect(func() -> void:
		if visible and _npc:
			open(_npc))


func open(npc: Npc) -> void:
	var reopening := visible and _npc == npc
	_npc = npc
	if not visible:
		GameAudio.play("open")
	visible = true
	_face.texture = npc.faceset
	_face.modulate = npc.tint
	_name.text = npc.display_name
	for b in _buttons.get_children():
		_buttons.remove_child(b)
		b.queue_free()
	var me := PlayerData.me
	var text := ""
	var action := Callable()
	var action_label := ""
	var cls := String(me.get("class", ""))
	# Pacote C: entregas prontas aqui primeiro (inclusive recados de outro
	# NPC), depois o andamento das missoes deste NPC, depois uma nova.
	var quests := PlayerData.quests_for(npc.npc_id)
	for q in quests:
		if PlayerData.quest_state(me.quests, q.id) == "active" and q.turn_in_npc() == npc.npc_id 				and int(me.quest_progress.get(q.id, 0)) >= q.count:
			text = q.done_text
			action = func() -> void: PlayerData.turn_in_quest(q.id)
			action_label = "Entregar"
			break
	if action_label.is_empty():
		for q in quests:
			if q.giver != npc.npc_id:
				continue
			var st := PlayerData.quest_state(me.quests, q.id)
			if st == "active":
				var prog := int(me.quest_progress.get(q.id, 0))
				if q.turn_in_npc() != npc.npc_id:
					text = "%s (fale com %s)" % [q.progress_text, q.turn_in_npc_name()]
				else:
					text = "%s (%s %d/%d)" % [q.progress_text, q.target_name, prog, q.count]
				break
			if PlayerData.can_accept(me, q, PlayerData.server_now()):
				text = "%s
Recompensa: %s" % [q.offer_text, _reward_text(q, cls)]
				action = func() -> void:
					GameAudio.play("confirm")
					PlayerData.accept_quest(q.id)
				action_label = "Aceitar"
				break
	if text.is_empty():
		# Nada de missao: cumprimento e, nas proximas conversas, outras falas
		text = npc.next_idle_line() if not reopening else _text.text
	_text.text = text
	# Opcoes: setas escolhem, Enter confirma (UiKit.choices); a primeira ja
	# vem marcada, com ou sem missao.
	var options: Array[Button] = []
	if action.is_valid():
		var b := UiKit.ink_button(action_label)
		b.pressed.connect(action)
		options.append(b)
	if not npc.shop_items.is_empty():
		var shop := UiKit.ink_button("Comércio")
		shop.pressed.connect(func() -> void:
			var n := _npc
			close()
			shop_requested.emit(n))
		options.append(shop)
	var bye := UiKit.ink_button("Até logo")
	bye.pressed.connect(close)
	options.append(bye)
	for b in options:
		_buttons.add_child(b)
	UiKit.choices(options)


## "120 XP, 30 de ouro, Espada de Ferro"
static func _reward_text(q: QuestData, cls: String) -> String:
	var parts: PackedStringArray = ["%d XP" % q.reward_xp]
	if q.reward_gold > 0:
		parts.append("%d de ouro" % q.reward_gold)
	if q.reward_item:
		parts.append(q.reward_item.display_name + (" x%d" % q.reward_count if q.reward_count > 1 else ""))
	var ci := q.class_reward(cls)
	if ci:
		parts.append(ci.display_name)
	return ", ".join(parts)


func close() -> void:
	if visible:
		GameAudio.play("close")
	visible = false
	_npc = null
	closed.emit()
