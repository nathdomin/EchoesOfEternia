class_name PauseMenu
extends Control
## Menu de pausa (E22), Esc. O mundo continua (e um MMO): so abre as opcoes.

signal leave_requested
signal help_requested

const SIZE := Vector2(210, 170)


var _sliders: Array[HSlider] = []


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.dimmer())
	var page := UiKit.parchment(SIZE, 8.0)
	page.position = (Vector2(480, 270) - SIZE) / 2.0
	add_child(page)
	var v := VBoxContainer.new()
	v.position = page.position + Vector2(24, 14)
	v.add_theme_constant_override("separation", -2)
	add_child(v)
	v.add_child(UiKit.gothic("Pausa", 24, UiKit.RUBRIC))
	var cont := UiKit.ink_button("Continuar")
	cont.pressed.connect(close)
	v.add_child(cont)
	for spec in [["Música", "music_volume"], ["Efeitos", "sfx_volume"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var l := UiKit.ink_text(spec[0])
		l.custom_minimum_size.x = 52
		row.add_child(l)
		var s := UiKit.ink_slider(96)
		s.value = GameAudio.get(spec[1])
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.value_changed.connect(_on_volume_changed)
		row.add_child(s)
		v.add_child(row)
		_sliders.append(s)
	var help := UiKit.ink_button("Controles e ajuda (F1)")
	help.pressed.connect(func() -> void:
		close()
		help_requested.emit())
	v.add_child(help)
	var out := UiKit.ink_button("Sair para o menu")
	out.pressed.connect(func() -> void: leave_requested.emit())
	v.add_child(out)


func open() -> void:
	visible = true
	(get_child(-1).get_child(1) as Button).grab_focus()


func _on_volume_changed(_v: float) -> void:
	GameAudio.set_volumes(_sliders[0].value, _sliders[1].value)
	GameAudio.play("click", 0.0)


func close() -> void:
	visible = false
