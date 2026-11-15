class_name PauseMenu
extends Control
## Menu de pausa (E22), Esc. O mundo continua (e um MMO): so abre as opcoes.

signal leave_requested

const SIZE := Vector2(200, 150)


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
	var out := UiKit.ink_button("Sair para o menu")
	out.pressed.connect(func() -> void: leave_requested.emit())
	v.add_child(out)
	v.add_child(UiKit.ink_text("1-3 habilidades, 4 poção\nI inventário, E conversar\nEnter chat, G convidar", 160))


func open() -> void:
	visible = true
	(get_child(-1).get_child(1) as Button).grab_focus()


func close() -> void:
	visible = false
