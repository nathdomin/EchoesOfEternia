class_name ChatBox
extends VBoxContainer
## Chat (E19), no canto inferior esquerdo. Enter abre/envia, Esc fecha.
## Mostra global, grupo (/g) e mensagens de sistema. As linhas somem depois
## de LINE_TIME s, mas reaparecem com o chat aberto.

const MAX_LINES := 7
const LINE_TIME := 12.0
const COLORS := {"global": Color(1, 0.96, 0.88), "grupo": Color(0.55, 0.85, 1.0), "sistema": Color(1, 0.88, 0.5)}

var is_open := false
var _lines: VBoxContainer
var _input: LineEdit


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 1)
	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", -3)
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lines)
	_input = LineEdit.new()
	_input.custom_minimum_size = Vector2(220, 16)
	_input.max_length = Social.MAX_CHAT
	_input.placeholder_text = "Mensagem (/g grupo, /convidar Nome, /ajuda)"
	_input.visible = false
	_input.text_submitted.connect(_on_submit)
	add_child(_input)
	Social.chat_received.connect(add_line)


func add_line(channel: String, author: String, text: String) -> void:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 230
	l.add_theme_color_override("font_color", COLORS.get(channel, Color.WHITE))
	l.text = text if author.is_empty() else ("[Grupo] " if channel == "grupo" else "") + "%s: %s" % [author, text]
	l.set_meta("born", Time.get_ticks_msec())
	_lines.add_child(l)
	while _lines.get_child_count() > MAX_LINES:
		_lines.get_child(0).free()


func open() -> void:
	is_open = true
	_input.visible = true
	_input.grab_focus()


func close() -> void:
	is_open = false
	_input.clear()
	_input.visible = false
	_input.release_focus()


func _on_submit(text: String) -> void:
	Social.send_chat(text)
	close()


## Base do chat presa neste ponto da tela (o painel cresce para cima).
var bottom_left := Vector2(4, 240)


func _process(_delta: float) -> void:
	reset_size()
	position = bottom_left - Vector2(0, size.y)
	var now := Time.get_ticks_msec()
	for l in _lines.get_children():
		var age := (now - int(l.get_meta("born"))) / 1000.0
		l.modulate.a = 1.0 if is_open else clampf(LINE_TIME + 1.0 - age, 0.0, 1.0)
