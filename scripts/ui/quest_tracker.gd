class_name QuestTracker
extends VBoxContainer
## Rastreador de missoes (E21), no lado direito: titulo e progresso de cada
## missao ativa. Fica dourado quando da para entregar.

func _ready() -> void:
	add_theme_constant_override("separation", 0)
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
	var any := false
	for qid: String in me.quests:
		if PlayerData.quest_state(me.quests, qid) != "active":
			continue
		var q := PlayerData.quest(qid)
		if q == null:
			continue
		if not any:
			var title := UiKit.label("Missões", UiKit.GOLD)
			title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			add_child(title)
			any = true
		var prog := int(me.quest_progress.get(qid, 0))
		var done := prog >= q.count
		var l := UiKit.label("%s\n%s %d/%d%s" % [q.title, q.target_name, prog, q.count, "  (entregar)" if done else ""],
				UiKit.GOLD if done else Color(1, 0.96, 0.88))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		add_child(l)
