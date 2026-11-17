class_name ClassChooser
extends Control
## Escolha de classe (E17), na primeira entrada do personagem. Pagina de
## manuscrito com as 3 classes (retrato, descricao, habilidades). A escolha
## e definitiva e o servidor confere que o personagem ainda nao tem classe.
## Teclado: setas trocam de carta, Enter marca "Confirmar?" e o segundo
## Enter escolhe (trocar de carta cancela). O mouse faz o mesmo.

const SIZE := Vector2(440, 236)

var _buttons: Array[Button] = []
var _names: Array[Label] = []
var _classes: Array[ClassData] = []
var _armed := -1
## Pacote E: cor da roupa (Player.OUTFIT_SHIFTS) e os quadradinhos dela.
var _outfit := 0
var _focused := 0
var _swatches: Array[Button] = []
var _faces: Array[TextureRect] = []


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
	# Cor da roupa: retratos pequenos no canto de cima (setas para cima chegam neles)
	var cor := UiKit.ink_text("Cor")
	cor.position = page.position + Vector2(SIZE.x - 150, 20)
	add_child(cor)
	for k in Player.OUTFIT_SHIFTS.size():
		var sw := Button.new()
		sw.focus_mode = Control.FOCUS_ALL
		sw.custom_minimum_size = Vector2(24, 24)
		sw.size = Vector2(24, 24)
		sw.expand_icon = true
		sw.position = page.position + Vector2(SIZE.x - 124 + k * 27, 12)
		sw.tooltip_text = "Cor %d" % (k + 1)
		sw.pressed.connect(_set_outfit.bind(k))
		sw.focus_entered.connect(_set_outfit.bind(k))
		sw.mouse_entered.connect(sw.grab_focus)
		add_child(sw)
		_swatches.append(sw)
	UiKit.choices(_buttons, false, false)
	for i in _buttons.size():
		_buttons[i].focus_entered.connect(_on_focus.bind(i))
	_set_outfit(0)
	PlayerData.changed.connect(_refresh)
	_refresh()  # o retrato ja pode ter chegado antes da cena carregar


func _refresh() -> void:
	var was := visible
	visible = not PlayerData.me.is_empty() and String(PlayerData.me.get("class", "")) == ""
	if visible and not was:
		_disarm()
		_buttons[0].grab_focus.call_deferred()


func _card(c: ClassData) -> Control:
	var i := _classes.size()
	_classes.append(c)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(124, 170)
	v.add_theme_constant_override("separation", 2)
	var top := HBoxContainer.new()
	var face := TextureRect.new()
	face.texture = Player.FACESETS.get(c.skin)
	face.custom_minimum_size = Vector2(38, 38)
	top.add_child(face)
	_faces.append(face)
	var class_name_label := UiKit.gothic(c.display_name, 24)
	top.add_child(class_name_label)
	_names.append(class_name_label)
	v.add_child(top)
	# Pacote B: alcance junto (o dano por golpe sozinho enganava: o Guerreiro
	# bate menos por golpe, mas em combo; os de longe batem de longe)
	var reach := "Longe" if c.is_ranged() else "Perto"
	v.add_child(UiKit.ink_text("%s\nVida %d · Atq %d · %s" % [c.description, c.base_hp, c.base_damage, reach], 124))
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
	b.pressed.connect(_on_pressed.bind(i))
	v.add_child(b)
	_buttons.append(b)
	return v


func _on_focus(i: int) -> void:
	_focused = i
	_refresh_swatches()
	if _armed != i:
		_disarm()
	for k in _names.size():
		_names[k].add_theme_color_override("font_color", UiKit.RUBRIC if k == i else UiKit.INK)


## Primeiro aperto marca, segundo escolhe (a escolha e definitiva).
func _on_pressed(i: int) -> void:
	if _armed == i:
		GameAudio.play("confirm")
		PlayerData.choose_class(_classes[i].id, _outfit)
		return
	_disarm()
	_armed = i
	_buttons[i].text = "Confirmar?"


func _disarm() -> void:
	if _armed >= 0:
		_buttons[_armed].text = "Escolher"
	_armed = -1


func _set_outfit(k: int) -> void:
	_outfit = k
	for f in _faces:
		f.material = Player.outfit_material(k)
	_refresh_swatches()


## Quadradinhos com o retrato da classe marcada em cada cor; o escolhido
## tem borda vermelha (rubrica).
func _refresh_swatches() -> void:
	var face: Texture2D = Player.FACESETS.get(_classes[_focused].skin) if not _classes.is_empty() else null
	for k in _swatches.size():
		var sw := _swatches[k]
		sw.icon = face
		sw.material = null
		var st := StyleBoxFlat.new()
		st.bg_color = Color(UiKit.INK, 0.12)
		st.set_border_width_all(2 if k == _outfit else 1)
		st.border_color = UiKit.RUBRIC if k == _outfit else Color(UiKit.INK, 0.5)
		for state in ["normal", "hover", "pressed", "focus"]:
			sw.add_theme_stylebox_override(state, st)
		# O icone usa o material do botao: um TextureRect por cima mostra a cor
		var prev := sw.get_node_or_null("Face") as TextureRect
		if prev == null:
			prev = TextureRect.new()
			prev.name = "Face"
			prev.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			prev.offset_left = 2; prev.offset_top = 2; prev.offset_right = -2; prev.offset_bottom = -2
			prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			prev.mouse_filter = Control.MOUSE_FILTER_IGNORE
			sw.add_child(prev)
		sw.icon = null
		prev.texture = face
		prev.material = Player.outfit_material(k)
