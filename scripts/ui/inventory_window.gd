class_name InventoryWindow
extends Control
## Inventario e equipamento (E18), em pergaminho como o dialogo e a pausa
## (revisao visual). Tecla I abre/fecha, Esc fecha.
## Clique: usa (pocao) ou equipa (troca com o equipado). Clique no
## equipamento: desequipa. Botao direito duas vezes: descarta.
## Tudo vai para o servidor; a janela so mostra o retrato (PlayerData.me).

const COLS := 5
const SLOT := 22.0
const SIZE := Vector2(300, 172)
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
		s.mouse_entered.connect(_show_info.bind(i))
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
		s.mouse_entered.connect(_show_equip_info.bind(slot))
		add_child(s)
		_equip[slot] = s
	_class_line = UiKit.ink_text("")
	_class_line.add_theme_color_override("font_color", UiKit.RUBRIC)
	_class_line.position = Vector2(150, 92)
	add_child(_class_line)
	_stats = UiKit.ink_text("")
	_stats.position = Vector2(150, 106)
	add_child(_stats)
	_info = UiKit.ink_text("Passe o mouse num item.", SIZE.x - 36)
	_info.position = Vector2(16, 132)
	_info.custom_minimum_size.y = 26
	add_child(_info)
	PlayerData.changed.connect(refresh)
	refresh()


func toggle() -> void:
	visible = not visible
	_discard_armed = -1
	GameAudio.play("open" if visible else "close")
	if visible:
		refresh()


func refresh() -> void:
	var me := PlayerData.me
	if me.is_empty():
		return
	var inv: Array = me.inventory
	for i in _grid.get_child_count():
		var s: Panel = _grid.get_child(i)
		var it := PlayerData.item(inv[i].id) if i < inv.size() and inv[i] is Dictionary else null
		(s.get_node("Icon") as TextureRect).texture = it.icon if it else null
		(s.get_node("Count") as Label).text = str(inv[i].n) if it and int(inv[i].n) > 1 else ""
	for slot: String in _equip:
		var it := PlayerData.item(String(me.equipment.get(slot, "")))
		(_equip[slot].get_node("Icon") as TextureRect).texture = it.icon if it else null
	var has_class := String(me["class"]) != ""
	var cd := PlayerData.class_data(String(me["class"])) if has_class else null
	_class_line.text = "%s  ·  Nv %d" % [cd.display_name if cd else "Sem classe", me.level]
	_stats.text = "Ataque %d    Vida %d" % [me.damage, me.max_hp]
	var skin := cd.skin if cd else String(me.get("skin", "knight"))
	_face.texture = Player.FACESETS.get(skin, Player.FACESETS.knight)


func _item_at(i: int) -> ItemData:
	var inv: Array = PlayerData.me.get("inventory", [])
	return PlayerData.item(inv[i].id) if i < inv.size() and inv[i] is Dictionary else null


func _show_info(i: int) -> void:
	var it := _item_at(i)
	_info.text = "" if it == null else "%s - %s %s" % [it.display_name, it.description, it.stat_text()]


func _show_equip_info(slot: String) -> void:
	var it := PlayerData.item(String(PlayerData.me.get("equipment", {}).get(slot, "")))
	_info.text = "%s (clique para tirar) %s" % [it.display_name, it.stat_text()] if it else "%s: vazio" % EQUIP_NAMES[slot]


func _on_slot_input(event: InputEvent, i: int) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var it := _item_at(i)
	if it == null:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_discard_armed = -1
		if it.equip_slot() != "":
			GameAudio.play("equip")
		PlayerData.use_slot(i)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if _discard_armed == i:
			PlayerData.discard(i)
			GameAudio.play("drop")
			_discard_armed = -1
			_info.text = "%s descartado." % it.display_name
		else:
			_discard_armed = i
			_info.text = "Botão direito de novo para DESCARTAR %s." % it.display_name


func _on_equip_input(event: InputEvent, slot: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		GameAudio.play("equip")
		PlayerData.unequip(slot)
