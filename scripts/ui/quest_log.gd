class_name QuestLog
extends Control
## Diario de missoes (pacote F), tecla L. Pergaminho com a lista das
## missoes ativas (o rastreador mostra so 3) e o detalhe da marcada: o que
## fazer, com quem falar, recompensa. Setas/mouse escolhem; L ou Esc fecha.

const SIZE := Vector2(330, 196)

var _list: VBoxContainer
var _title: Label
var _body: Label
var _done: Label


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.dimmer())
	var origin := ((Vector2(480, 270) - SIZE) / 2.0).round()
	var page := UiKit.parchment(SIZE, 6.0)
	page.position = origin
	add_child(page)
	var head := UiKit.gothic("Diário", 24, UiKit.RUBRIC)
	head.position = origin + Vector2(16, 4)
	add_child(head)
	var hint := UiKit.ink_text("L ou Esc fecha")
	hint.position = origin + Vector2(SIZE.x - 84, 12)
	hint.modulate.a = 0.7
	add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.position = origin + Vector2(14, 36)
	scroll.size = Vector2(124, SIZE.y - 66)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.custom_minimum_size.x = 118
	_list.add_theme_constant_override("separation", -3)
	scroll.add_child(_list)
	var rule := ColorRect.new()
	rule.color = Color(UiKit.INK, 0.35)
	rule.position = origin + Vector2(144, 36)
	rule.size = Vector2(1, SIZE.y - 66)
	add_child(rule)
	_title = UiKit.ink_text("", SIZE.x - 170)
	_title.add_theme_color_override("font_color", UiKit.RUBRIC)
	_title.position = origin + Vector2(152, 34)
	add_child(_title)
	_body = UiKit.ink_text("", SIZE.x - 170)
	_body.position = origin + Vector2(152, 50)
	add_child(_body)
	_done = UiKit.ink_text("")
	_done.position = origin + Vector2(16, SIZE.y - 26)
	_done.modulate.a = 0.75
	add_child(_done)
	PlayerData.changed.connect(func() -> void:
		if visible:
			_rebuild())


func toggle() -> void:
	visible = not visible
	GameAudio.play("open" if visible else "close")
	if visible:
		_rebuild(true)
	else:
		var f := get_viewport().gui_get_focus_owner()
		if f and is_ancestor_of(f):
			f.release_focus()


func _rebuild(_focus_first := false) -> void:
	var me := PlayerData.me
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var buttons: Array[Button] = []
	var done := 0
	for qid: String in me.get("quests", {}):
		var q := PlayerData.quest(qid)
		if q == null:
			continue
		var st := PlayerData.quest_state(me.quests, qid)
		if st == "done":
			done += 1
			continue
		var ready := int(me.quest_progress.get(qid, 0)) >= q.count
		var b := Button.new()
		b.theme_type_variation = &"InkFlatButton"
		b.text = q.title
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.custom_minimum_size = Vector2(118, 14)
		if ready:
			b.add_theme_color_override("font_color", Color(0.55, 0.38, 0.05))
		b.focus_entered.connect(_show.bind(q))
		_list.add_child(b)
		buttons.append(b)
	_done.text = "Concluídas: %d" % done
	if buttons.is_empty():
		_list.add_child(UiKit.ink_text("Nenhuma missão ativa."))
		_title.text = "Sem missões"
		_body.text = "Procure um NPC com \"!\" sobre a cabeça. O primeiro é o Ancião, na praça da vila."
		return
	# Refeita a cada mudanca: o foco volta para a primeira (com a seta)
	UiKit.choices(buttons, true, false)


func _show(q: QuestData) -> void:
	if q == null:
		return
	var me := PlayerData.me
	var prog := int(me.quest_progress.get(q.id, 0))
	var ready := prog >= q.count
	_title.text = q.title
	var lines: PackedStringArray = []
	lines.append(q.offer_text)
	if q.kind == QuestData.Kind.TALK:
		lines.append("Objetivo: falar com o %s." % q.turn_in_npc_name())
	elif ready:
		lines.append("Pronta! Volte ao %s." % q.turn_in_npc_name())
	else:
		lines.append("Objetivo: %s %d/%d." % [q.target_name, prog, q.count])
	lines.append("Recompensa: %s" % DialogueBox._reward_text(q, String(me.get("class", ""))))
	_body.text = "\n".join(lines)
