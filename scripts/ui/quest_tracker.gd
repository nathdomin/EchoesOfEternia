class_name QuestTracker
extends VBoxContainer
## Rastreador de missoes (E21), no lado direito: titulo e progresso de cada
## missao ativa. Fica dourado quando da para entregar.
## Gate 5: no maximo MAX_SHOWN missoes (as prontas primeiro); o resto vira
## "+N missões", para nao cobrir a lateral da tela.

const MAX_SHOWN := 3
const TEXT := Color(1, 0.96, 0.88)
const DIM := Color(0.85, 0.82, 0.74)


func _ready() -> void:
	add_theme_constant_override("separation", -2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN
	PlayerData.changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	var me := PlayerData.me
	if me.is_empty():
		return
	var active: Array = []
	for qid: String in me.quests:
		var q := PlayerData.quest(qid)
		if q and PlayerData.quest_state(me.quests, qid) == "active":
			var prog := int(me.quest_progress.get(qid, 0))
			active.append({"q": q, "prog": prog, "done": prog >= q.count})
	if active.is_empty():
		# Pacote F: sem missao ativa, aponta a proxima (comeco do jogo: Anciao)
		var next := _next_offer(me)
		if next:
			_line("Próximo passo", UiKit.GOLD)
			_line("Fale com o %s" % next.giver_name, TEXT)
		return
	active.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.done and not b.done)
	_line("Missões", UiKit.GOLD)
	for i in mini(active.size(), MAX_SHOWN):
		var e: Dictionary = active[i]
		var q: QuestData = e.q
		_line(q.title, UiKit.GOLD if e.done else TEXT)
		var who := q.turn_in_npc_name() if q.turn_in_npc_name() != "" else "NPC"
		if q.kind == QuestData.Kind.TALK:
			_line("Fale com o %s" % who, DIM)
		else:
			_line("Volte ao %s" % who if e.done else "%s %d/%d" % [q.target_name, e.prog, q.count], DIM)
	if active.size() > MAX_SHOWN:
		_line("+%d missões" % (active.size() - MAX_SHOWN), DIM)


## Primeira missao que da para aceitar agora (a de menor nivel minimo).
static func _next_offer(me: Dictionary) -> QuestData:
	var best: QuestData = null
	for f in DirAccess.get_files_at("res://resources/quests"):
		var fname := f.trim_suffix(".remap")
		if not fname.ends_with(".tres"):
			continue
		var q := PlayerData.quest(fname.get_basename())
		if q and q.repeat_hours <= 0.0 and PlayerData.can_accept(me, q) and (best == null or q.min_level < best.min_level):
			best = q
	return best


func _line(text: String, color: Color) -> void:
	var l := UiKit.label(text, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Largura fixa: texto longo vira "..." em vez de sair da tela
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.custom_minimum_size.x = custom_minimum_size.x
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.03))
	add_child(l)
