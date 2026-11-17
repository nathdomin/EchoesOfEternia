class_name InventoryWindow
extends Control
## Inventario e equipamento (E18), em pergaminho como o dialogo e a pausa
## (revisao visual). Tecla I abre/fecha, Esc fecha.
## Clique: usa (pocao) ou equipa (troca com o equipado). Clique no
## equipamento: desequipa. Botao direito duas vezes: descarta.
## Pacote F: teclado (setas andam pelos espacos, Enter usa/equipa/tira,
## Delete duas vezes descarta), contorno no espaco marcado, nome na cor da
## raridade, comparacao com o equipado e o ouro.
## Tudo vai para o servidor; a janela so mostra o retrato (PlayerData.me).

const COLS := 5
const SLOT := 22.0
const SIZE := Vector2(300, 198)
const EQUIP_NAMES := {"weapon": "Arma", "armor": "Armadura", "trinket": "Acessório"}

var _grid: GridContainer
var _equip: Dictionary = {}
var _face: TextureRect
var _class_line: Label
var _stats: Label
var _info: Label
var _discard_armed := -1


func _ready() -> void:
	visible = false
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UiKit.parchment(SIZE, 6.0))
	var title := UiKit.gothic("Inventário", 24, UiKit.RUBRIC)
	title.position = Vector2(16, 4)
	add_child(title)
	var hint := UiKit.ink_text("I ou Esc fecha")
	hint.position = Vector2(SIZE.x - 82, 10)
	hint.modulate.a = 0.7
	add_child(hint)
	# Bolsa: 5 x 4
	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.position = Vector2(16, 34)
	_grid.add_theme_constant_override("h_separation", 2)
	_grid.add_theme_constant_override("v_separation", 2)
	add_child(_grid)
	for i in PlayerData.INVENTORY_SLOTS:
		var s := UiKit.slot(SLOT, true)
		s.gui_input.connect(_on_slot_input.bind(i))
		_make_focusable(s, _show_info.bind(i))
		_grid.add_child(s)
	# Divisoria em tinta
	var line := ColorRect.new()
	line.color = Color(UiKit.INK, 0.35)
	line.position = Vector2(140, 36)
	line.size = Vector2(1, 92)
	add_child(line)
	# Personagem: retrato com arma, armadura e acessorio em volta
	_face = TextureRect.new()
	_face.position = Vector2(176, 50)
	_face.size = Vector2(38, 38)
	_face.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	add_child(_face)
	var spots := {"weapon": Vector2(150, 58), "armor": Vector2(184, 30), "trinket": Vector2(218, 58)}
	for slot: String in PlayerData.EQUIP_SLOTS:
		var s := UiKit.slot(SLOT, true)
		s.position = spots[slot]
		s.tooltip_text = EQUIP_NAMES[slot]
		s.gui_input.connect(_on_equip_input.bind(slot))
		_make_focusable(s, _show_equip_info.bind(slot))
		add_child(s)
		_equip[slot] = s
	_class_line = UiKit.ink_text("")
	_class_line.add_theme_color_override("font_color", UiKit.RUBRIC)
	_class_line.position = Vector2(150, 92)
	add_child(_class_line)
	_stats = UiKit.ink_text("")
	_stats.position = Vector2(150, 106)
	add_child(_stats)
	_info = UiKit.ink_text("Setas ou mouse escolhem; Enter usa ou equipa.", SIZE.x - 36)
	_info.position = Vector2(16, 140)
	_info.custom_minimum_size.y = 40  # ate 3 linhas (raridade, atributos, comparacao)
	add_child(_info)
	PlayerData.changed.connect(refresh)
	refresh()


func toggle() -> void:
	visible = not visible
	_discard_armed = -1
	GameAudio.play("open" if visible else "close")
	if visible:
		refresh()
		(_grid.get_child(0) as Control).grab_focus.call_deferred()
	else:
		var f := get_viewport().gui_get_focus_owner()
		if f and is_ancestor_of(f):
			f.release_focus()


## Espaco que recebe foco (setas/mouse) e mostra um contorno vermelho.
func _make_focusable(s: Panel, on_focus: Callable) -> void:
	s.focus_mode = Control.FOCUS_ALL
	var ring := Panel.new()
	ring.name = "Ring"
	var st := StyleBoxFlat.new()
	st.draw_center = false
	st.set_border_width_all(1)
	st.border_color = UiKit.RUBRIC
	st.set_corner_radius_all(2)
	st.expand_margin_left = 1; st.expand_margin_top = 1; st.expand_margin_right = 1; st.expand_margin_bottom = 1
	ring.add_theme_stylebox_override("panel", st)
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.visible = false
	s.add_child(ring)
	s.focus_entered.connect(func() -> void:
		ring.visible = true
		on_focus.call())
	s.focus_exited.connect(func() -> void: ring.visible = false)
	s.mouse_entered.connect(s.grab_focus)


func refresh() -> void:
	var me := PlayerData.me
	if me.is_empty():
		return
	var inv: Array = me.inventory
	for i in _grid.get_child_count():
		var s: Panel = _grid.get_child(i)
		var it := PlayerData.item(inv[i].id) if i < inv.size() and inv[i] is Dictionary else null
		(s.get_node("Icon") as TextureRect).texture = it.icon if it else null
		(s.get_node("Icon") as TextureRect).modulate = it.tint if it else Color.WHITE
		(s.get_node("Count") as Label).text = str(inv[i].n) if it and int(inv[i].n) > 1 else ""
	for slot: String in _equip:
		var it := PlayerData.item(String(me.equipment.get(slot, "")))
		(_equip[slot].get_node("Icon") as TextureRect).texture = it.icon if it else null
		(_equip[slot].get_node("Icon") as TextureRect).modulate = it.tint if it else Color.WHITE
	var has_class := String(me["class"]) != ""
	var cd := PlayerData.class_data(String(me["class"])) if has_class else null
	_class_line.text = "%s  ·  Nv %d" % [cd.display_name if cd else "Sem classe", me.level]
	_stats.text = "Ataque %d    Vida %d\nOuro %d" % [me.damage, me.max_hp, int(me.get("gold", 0))]
	var skin := cd.skin if cd else String(me.get("skin", "knight"))
	_face.texture = Player.FACESETS.get(skin, Player.FACESETS.knight)
	_face.material = Player.outfit_material(int(me.get("outfit", 0)))
	# O item marcado pode ter mudado (usou, equipou): atualiza a descricao
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if visible and f and f.get_parent() == _grid:
		_show_info(f.get_index())


func _item_at(i: int) -> ItemData:
	var inv: Array = PlayerData.me.get("inventory", [])
	return PlayerData.item(inv[i].id) if i < inv.size() and inv[i] is Dictionary else null


func _show_info(i: int) -> void:
	if _discard_armed != i:
		_discard_armed = -1
	var it := _item_at(i)
	_set_info(it, _describe(it) if it else "Espaço vazio.")


## Descricao do item: raridade, o que faz, classe e a diferenca para o equipado.
func _describe(it: ItemData) -> String:
	var parts: PackedStringArray = []
	if it.rarity != ItemData.Rarity.COMMON:
		parts.append(ItemData.RARITY_NAMES[it.rarity])
	parts.append(it.description.trim_suffix("."))
	var st := it.stat_text()
	if st != "":
		parts.append(st)
	var cls := String(PlayerData.me.get("class", ""))
	if it.class_only != "":
		parts.append(("Só " if it.usable_by(cls) else "Não serve: só ") + PlayerData.class_data(it.class_only).display_name)
	if it.equip_slot() != "" and it.usable_by(cls):
		var cur := PlayerData.item(String(PlayerData.me.get("equipment", {}).get(it.equip_slot(), "")))
		var dd := it.bonus_damage - (cur.bonus_damage if cur else 0)
		var dh := it.bonus_hp - (cur.bonus_hp if cur else 0)
		var diff: PackedStringArray = []
		if dd != 0:
			diff.append("%+d ataque" % dd)
		if dh != 0:
			diff.append("%+d vida" % dh)
		if not diff.is_empty():
			parts.append("vs. equipado: " + ", ".join(diff))
	return "%s: %s" % [it.display_name, ". ".join(parts)]


func _set_info(it: ItemData, text: String) -> void:
	_info.text = text
	if it:
		_info.add_theme_color_override("font_color", it.name_color(true))
	else:
		_info.remove_theme_color_override("font_color")


func _show_equip_info(slot: String) -> void:
	var it := PlayerData.item(String(PlayerData.me.get("equipment", {}).get(slot, "")))
	_set_info(it, "%s (Enter ou clique tira) %s" % [it.display_name, it.stat_text()] if it else "%s: vazio" % EQUIP_NAMES[slot])


func _on_slot_input(event: InputEvent, i: int) -> void:
	var it := _item_at(i)
	# Teclado: Enter = clique, Delete = botao direito
	var use: bool = event.is_action_pressed("ui_accept")
	var drop: bool = event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_DELETE
	if use or drop:
		accept_event()
	if it == null:
		return
	if event is InputEventMouseButton and event.pressed:
		use = event.button_index == MOUSE_BUTTON_LEFT
		drop = event.button_index == MOUSE_BUTTON_RIGHT
	if use:
		_discard_armed = -1
		if it.equip_slot() != "":
			GameAudio.play("equip")
		PlayerData.use_slot(i)
	elif drop:
		if _discard_armed == i:
			PlayerData.discard(i)
			GameAudio.play("drop")
			_discard_armed = -1
			_set_info(null, "%s descartado." % it.display_name)
		else:
			_discard_armed = i
			_set_info(null, "De novo (botão direito ou Delete) para DESCARTAR %s." % it.display_name)


func _on_equip_input(event: InputEvent, slot: String) -> void:
	if event.is_action_pressed("ui_accept") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		accept_event()
		GameAudio.play("equip")
		PlayerData.unequip(slot)
