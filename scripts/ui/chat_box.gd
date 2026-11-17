class_name ChatBox
extends VBoxContainer
## Chat (E19), no canto inferior esquerdo. Enter abre/envia, Esc fecha.
## Mostra global, grupo (/g) e mensagens de sistema. As linhas somem depois
## de LINE_TIME s, mas reaparecem com o chat aberto.

const MAX_LINES := 7
const LINE_TIME := 12.0
## Altura maxima das linhas (px): mensagens longas nao sobem por cima do
## quadro do grupo; as mais antigas somem primeiro (Gate 5).
const MAX_HEIGHT := 92.0
const COLORS := {"global": Color(1, 0.96, 0.88), "grupo": Color(0.55, 0.85, 1.0), "zona": Color(0.7, 1.0, 0.65),
		"de": Color(1.0, 0.6, 0.9), "para": Color(1.0, 0.6, 0.9), "sistema": Color(1, 0.88, 0.5)}
const PREFIX := {"grupo": "[Grupo] %s: ", "zona": "[Zona] %s: ", "de": "%s sussurra: ", "para": "Para %s: ", "global": "%s: "}

var is_open := false
## Pacote F: mensagens enviadas (seta para cima/baixo repete, como no terminal).
const HISTORY_MAX := 20
var _history: PackedStringArray = []
var _history_pos := -1
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
	_input.placeholder_text = "Mensagem (/ajuda: comandos)"
	_input.visible = false
	_input.text_submitted.connect(_on_submit)
	_input.gui_input.connect(_on_input_key)
	add_child(_input)
	Social.chat_received.connect(add_line)


func add_line(channel: String, author: String, text: String) -> void:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 230
	l.add_theme_color_override("font_color", COLORS.get(channel, Color.WHITE))
	l.text = text if author.is_empty() else String(PREFIX.get(channel, "%s: ")) % author + text
	l.set_meta("born", Time.get_ticks_msec())
	_lines.add_child(l)
	while _lines.get_child_count() > MAX_LINES:
		_lines.get_child(0).free()


## `prefix` ja vem escrito (tecla "/" abre com "/").
func open(prefix := "") -> void:
	is_open = true
	_input.visible = true
	_input.text = prefix
	_input.grab_focus()
	_input.caret_column = prefix.length()


func close() -> void:
	is_open = false
	_input.clear()
	_input.visible = false
	_input.release_focus()


func _on_submit(text: String) -> void:
	if not text.strip_edges().is_empty():
		_history.append(text)
		if _history.size() > HISTORY_MAX:
			_history.remove_at(0)
	_history_pos = -1
	Social.send_chat(text)
	close()


func _on_input_key(event: InputEvent) -> void:
	if _history.is_empty() or not (event is InputEventKey and event.pressed):
		return
	var k := (event as InputEventKey).keycode
	if k != KEY_UP and k != KEY_DOWN:
		return
	if k == KEY_UP:
		_history_pos = _history.size() - 1 if _history_pos < 0 else maxi(_history_pos - 1, 0)
	elif _history_pos >= 0:
		_history_pos += 1
		if _history_pos >= _history.size():
			_history_pos = -1
	_input.text = _history[_history_pos] if _history_pos >= 0 else ""
	_input.caret_column = _input.text.length()
	_input.accept_event()


## Base do chat presa neste ponto da tela (o painel cresce para cima).
var bottom_left := Vector2(4, 240)


func _process(_delta: float) -> void:
	reset_size()
	position = bottom_left - Vector2(0, size.y)
	var used := 0.0
	var all := _lines.get_children()
	for i in range(all.size() - 1, -1, -1):
		var line := all[i] as Label
		used += line.get_combined_minimum_size().y - 3.0
		line.visible = used <= MAX_HEIGHT
	var now := Time.get_ticks_msec()
	for l in _lines.get_children():
		var age := (now - int(l.get_meta("born"))) / 1000.0
		l.modulate.a = 1.0 if is_open else clampf(LINE_TIME + 1.0 - age, 0.0, 1.0)
	queue_redraw()


## Fundo escuro translucido atras das linhas visiveis (o texto claro nao
## some mais na grama da vila). Some junto com as linhas.
func _draw() -> void:
	var alpha := 0.0
	var top := size.y
	for l: Label in _lines.get_children():
		if l.visible and l.modulate.a > 0.01:
			alpha = maxf(alpha, l.modulate.a)
			top = minf(top, l.position.y + _lines.position.y)
	if is_open:
		alpha = 1.0
		top = minf(top, _input.position.y)
	if alpha <= 0.0:
		return
	var r := Rect2(Vector2(-3, top - 1), Vector2(240, size.y - top + 2))
	draw_rect(r, Color(0.05, 0.03, 0.03, 0.45 * alpha))
