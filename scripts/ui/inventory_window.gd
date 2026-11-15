class_name InventoryWindow
extends PanelContainer
## Inventario e equipamento (E18). Tecla I abre/fecha.
## Clique: usa (pocao) ou equipa (troca com o equipado). Clique no
## equipamento: desequipa. Botao direito duas vezes: descarta.
## Tudo vai para o servidor; a janela so mostra o retrato (PlayerData.me).

const COLS := 5
const SLOT := 24.0
const EQUIP_NAMES := {"weapon": "Arma", "armor": "Armadura", "trinket": "Acessório"}

var _grid: GridContainer
var _equip: Dictionary = {}
var _stats: Label
var _info: Label
var _discard_armed := -1


func _ready() -> void:
	theme_type_variation = &"DarkPanel"
	visible = false
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 3)
	add_child(root)
	var title := UiKit.label("Inventário  (I fecha)", UiKit.GOLD)
	root.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)
	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", 2)
	_grid.add_theme_constant_override("v_separation", 2)
	row.add_child(_grid)
	for i in PlayerData.INVENTORY_SLOTS:
		var s := UiKit.slot(SLOT)
		s.gui_input.connect(_on_slot_input.bind(i))
		s.mouse_entered.connect(_show_info.bind(i))
		_grid.add_child(s)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 2)
	row.add_child(side)
	for slot: String in PlayerData.EQUIP_SLOTS:
		var line := HBoxContainer.new()
		var s := UiKit.slot(SLOT)
		s.gui_input.connect(_on_equip_input.bind(slot))
		s.mouse_entered.connect(_show_equip_info.bind(slot))
		line.add_child(s)
		line.add_child(UiKit.label(EQUIP_NAMES[slot]))
		side.add_child(line)
		_equip[slot] = s
	_stats = UiKit.label("")
	side.add_child(_stats)
	_info = UiKit.label("Passe o mouse num item.", Color(0.85, 0.8, 0.7))
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(250, 26)
	root.add_child(_info)
	PlayerData.changed.connect(refresh)
	refresh()


func toggle() -> void:
	visible = not visible
	_discard_armed = -1
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
	var cls := PlayerData.class_data(String(me["class"])).display_name if String(me["class"]) != "" else "sem classe"
	_stats.text = "%s  Nv %d\nAtaque %d\nVida máx. %d" % [cls, me.level, me.damage, me.max_hp]


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
		PlayerData.use_slot(i)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if _discard_armed == i:
			PlayerData.discard(i)
			_discard_armed = -1
			_info.text = "%s descartado." % it.display_name
		else:
			_discard_armed = i
			_info.text = "Botão direito de novo para DESCARTAR %s." % it.display_name


func _on_equip_input(event: InputEvent, slot: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		PlayerData.unequip(slot)
