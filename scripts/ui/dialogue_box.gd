class_name DialogueBox
extends Control
## Conversa com NPC (E21) no estilo manuscrito: retrato, nome em letra
## gotica, texto em tinta e opcoes (aceitar/entregar a missao, sair).
## O servidor confere a distancia ate o NPC e o estado da missao.

signal closed

const SIZE := Vector2(340, 118)

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
	_buttons.add_theme_constant_override("separation", 14)
	_buttons.position = Vector2(60, SIZE.y - 34)
	add_child(_buttons)
	PlayerData.changed.connect(func() -> void:
		if visible and _npc:
			open(_npc))


func open(npc: Npc) -> void:
	_npc = npc
	if not visible:
		GameAudio.play("open")
	visible = true
	_face.texture = npc.faceset
	_name.text = npc.display_name
	for b in _buttons.get_children():
		b.queue_free()
	var me := PlayerData.me
	var text := npc.greeting
	var action := Callable()
	var action_label := ""
	for q in PlayerData.quests_of(npc.npc_id):
		var st := PlayerData.quest_state(me.quests, q.id)
		if st == "active":
			var prog := int(me.quest_progress.get(q.id, 0))
			if prog >= q.count:
				text = q.done_text
				action = func() -> void: PlayerData.turn_in_quest(q.id)
				action_label = "Entregar"
			else:
				text = "%s (%s %d/%d)" % [q.progress_text, q.target_name, prog, q.count]
			break
		if st == "" and PlayerData.can_accept(me, q):
			text = "%s\nRecompensa: %d XP%s" % [q.offer_text, q.reward_xp,
					", " + q.reward_item.display_name if q.reward_item else ""]
			action = func() -> void: PlayerData.accept_quest(q.id)
			action_label = "Aceitar"
			break
	_text.text = text
	if action.is_valid():
		var b := UiKit.ink_button(action_label)
		b.pressed.connect(action)
		_buttons.add_child(b)
		b.grab_focus.call_deferred()
	var bye := UiKit.ink_button("Até logo")
	bye.pressed.connect(close)
	_buttons.add_child(bye)


func close() -> void:
	visible = false
	_npc = null
	closed.emit()
