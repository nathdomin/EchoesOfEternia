class_name PauseMenu
extends Control
## Menu de pausa (E22), Esc. O mundo continua (e um MMO): so abre as opcoes.
## Gate 5: tudo centralizado na pagina; titulo, tres botoes em letra gotica
## e o volume em tinta, numa caixa propria.

signal leave_requested
signal help_requested

const SIZE := Vector2(232, 224)

var _sliders: Array[HSlider] = []
var _first: Button
var _res_button: Button


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.dimmer())
	var origin := ((Vector2(480, 270) - SIZE) / 2.0).round()
	var page := UiKit.parchment(SIZE, 8.0)
	page.position = origin
	add_child(page)
	var v := VBoxContainer.new()
	v.position = origin + Vector2(16, 12)
	v.custom_minimum_size.x = SIZE.x - 32
	v.add_theme_constant_override("separation", -4)
	add_child(v)
	var title := UiKit.gothic("Pausa", 24, UiKit.RUBRIC)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_first = _button(v, "Continuar", close)
	var help := _button(v, "Ajuda", func() -> void:
		close()
		help_requested.emit())
	var leave := _button(v, "Sair para o menu", func() -> void: leave_requested.emit())
	# Seta no focado e mouse = foco; sem laco aqui, as setas descem ate o volume
	UiKit.choices([_first, help, leave], false, false)
	# Volume: duas linhas em tinta, alinhadas
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 6
	v.add_child(spacer)
	v.add_child(box)
	for spec in [["Música", "music_volume"], ["Efeitos", "sfx_volume"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var l := UiKit.ink_text(spec[0])
		l.custom_minimum_size.x = 46
		row.add_child(l)
		var s := UiKit.ink_slider(110)
		s.value = GameAudio.get(spec[1])
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.value_changed.connect(_on_volume_changed)
		_mark_focus(s, l)
		row.add_child(s)
		box.add_child(row)
		_sliders.append(s)
	# Resolucao: clique troca entre 960x540, 1440x810 e 1920x1080
	var res_row := HBoxContainer.new()
	res_row.add_theme_constant_override("separation", 6)
	var rl := UiKit.ink_text("Tela")
	rl.custom_minimum_size.x = 46
	res_row.add_child(rl)
	_res_button = Button.new()
	_res_button.theme_type_variation = &"InkFlatButton"
	_res_button.focus_mode = Control.FOCUS_ALL
	_res_button.custom_minimum_size.x = 110
	_res_button.text = DisplaySettings.label(DisplaySettings.current_index())
	_res_button.pressed.connect(_on_resolution_pressed)
	_mark_focus(_res_button, rl)
	res_row.add_child(_res_button)
	box.add_child(res_row)
	# Pacote F: liga/desliga numeros de dano e tremor da tela
	for spec in [["Números", "damage_numbers"], ["Tremor", "screen_shake"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var l := UiKit.ink_text(spec[0])
		l.custom_minimum_size.x = 46
		row.add_child(l)
		var b := Button.new()
		b.theme_type_variation = &"InkFlatButton"
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size.x = 110
		var key: String = spec[1]
		b.text = "Ligado" if DisplaySettings.flag(key) else "Desligado"
		b.pressed.connect(func() -> void:
			DisplaySettings.set_flag(key, not DisplaySettings.flag(key))
			b.text = "Ligado" if DisplaySettings.flag(key) else "Desligado")
		_mark_focus(b, l)
		row.add_child(b)
		box.add_child(row)


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := UiKit.ink_button(text)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.pressed.connect(action)
	parent.add_child(b)
	return b


## O rotulo da linha fica vermelho enquanto o controle dela tem o foco
## (o deslizante e o botao de tela nao mostram o foco sozinhos).
func _mark_focus(control: Control, label: Label) -> void:
	control.focus_entered.connect(func() -> void:
		label.add_theme_color_override("font_color", UiKit.RUBRIC))
	control.focus_exited.connect(func() -> void:
		label.remove_theme_color_override("font_color"))
	control.mouse_entered.connect(control.grab_focus)


func open() -> void:
	visible = true
	_first.grab_focus()


func _on_volume_changed(_v: float) -> void:
	GameAudio.set_volumes(_sliders[0].value, _sliders[1].value)
	GameAudio.play("click", 0.0)


func _on_resolution_pressed() -> void:
	var next := (DisplaySettings.current_index() + 1) % DisplaySettings.option_count()
	DisplaySettings.set_index(next)
	_res_button.text = DisplaySettings.label(next)


func close() -> void:
	visible = false
