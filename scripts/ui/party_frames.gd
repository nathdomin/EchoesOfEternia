class_name PartyFrames
extends VBoxContainer
## Quadro do grupo (E20): os outros membros com nome, nivel e vida.
## Quem esta em outra zona aparece apagado. O lider tem uma coroa (*).

func _ready() -> void:
	add_theme_constant_override("separation", 2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Social.party_changed.connect(_rebuild)


func _rebuild(members: Array) -> void:
	for c in get_children():
		c.queue_free()
	var me := multiplayer.get_unique_id()
	var my_zone := ""
	for m in members:
		if int(m.id) == me:
			my_zone = String(m.zone)
	for m in members:
		if int(m.id) == me:
			continue
		var p := UiKit.dark_panel()
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		var who := UiKit.label(("* " if m.leader else "") + "%s  Nv %d" % [m.name, m.level], Color(0.55, 0.85, 1.0))
		v.add_child(who)
		var b := UiKit.bar(80, 5, Color(0.82, 0.18, 0.16))
		b.max_value = maxi(int(m.max_hp), 1)
		b.value = int(m.hp)
		v.add_child(b)
		p.add_child(v)
		p.modulate.a = 1.0 if String(m.zone) == my_zone else 0.5
		add_child(p)
