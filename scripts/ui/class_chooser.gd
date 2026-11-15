class_name ClassChooser
extends Control
## Escolha de classe (E17), na primeira entrada do personagem. Pagina de
## manuscrito com as 3 classes (retrato, descricao, habilidades). A escolha
## e definitiva e o servidor confere que o personagem ainda nao tem classe.

const SIZE := Vector2(440, 236)


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.dimmer())
	var page := UiKit.parchment(SIZE, 10.0)
	page.position = (Vector2(480, 270) - SIZE) / 2.0
	add_child(page)
	var title := UiKit.gothic("Escolha sua classe", 24, UiKit.RUBRIC)
	title.position = page.position + Vector2(24, 12)
	add_child(title)
	var row := HBoxContainer.new()
	row.position = page.position + Vector2(22, 46)
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	for cid: String in PlayerData.CLASS_IDS:
		row.add_child(_card(PlayerData.class_data(cid)))
	PlayerData.changed.connect(_refresh)
	_refresh()  # o retrato ja pode ter chegado antes da cena carregar


func _refresh() -> void:
	visible = not PlayerData.me.is_empty() and String(PlayerData.me.get("class", "")) == ""


func _card(c: ClassData) -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(124, 170)
	v.add_theme_constant_override("separation", 2)
	var top := HBoxContainer.new()
	var face := TextureRect.new()
	face.texture = Player.FACESETS.get(c.skin)
	face.custom_minimum_size = Vector2(38, 38)
	top.add_child(face)
	top.add_child(UiKit.gothic(c.display_name, 24))
	v.add_child(top)
	v.add_child(UiKit.ink_text("%s\nVida %d  Ataque %d" % [c.description, c.base_hp, c.base_damage], 124))
	var icons := HBoxContainer.new()
	for ab in c.abilities:
		var t := TextureRect.new()
		t.texture = ab.icon
		t.custom_minimum_size = Vector2(22, 22)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.tooltip_text = "%s: %s" % [ab.display_name, ab.description]
		icons.add_child(t)
	v.add_child(icons)
	var b := UiKit.ink_button("Escolher")
	b.pressed.connect(func() -> void: PlayerData.choose_class(c.id))
	v.add_child(b)
	return v
