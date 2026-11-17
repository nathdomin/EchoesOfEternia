class_name PauseMenu
extends Control
## Menu de pausa (E22), Esc. O mundo continua (e um MMO): so abre as opcoes.
## Gate 5: tudo centralizado na pagina; titulo, tres botoes em letra gotica
## e o volume em tinta, numa caixa propria.

signal leave_requested
signal help_requested

const SIZE := Vector2(232, 196)

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
	_button(v, "Ajuda", func() -> void:
		close()
		help_requested.emit())
	_button(v, "Sair para o menu", func() -> void: leave_requested.emit())
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
	res_row.add_child(_res_button)
	box.add_child(res_row)


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := UiKit.ink_button(text)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func open() -> void:
	visible = true
	_first.grab_focus()


func _on_volume_changed(_v: float) -> void:
	GameAudio.set_volumes(_sliders[0].value, _sliders[1].value)
	GameAudio.play("click", 0.0)


func _on_resolution_pressed() -> void:
	var next := (DisplaySettings.current_index() + 1) % DisplaySettings.RESOLUTIONS.size()
	DisplaySettings.set_index(next)
	_res_button.text = DisplaySettings.label(next)


func close() -> void:
	visible = false
