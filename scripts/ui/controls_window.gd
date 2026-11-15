class_name ControlsWindow
extends Control
## Ajuda (revisao de HUD e controles): pergaminho com duas abas.
## "Controles": cada tecla desenhada como uma tecla, ao lado do que faz.
## "Como jogar": cinco passos curtos, numerados.
## F1 abre/fecha, tambem pelo menu de pausa. Abre sozinha no primeiro jogo
## deste PC (user://client.cfg, secao "ui", chave "tutorial_seen").

const SIZE := Vector2(392, 236)
const ROW := 19.0
const HEAD := 14.0
const PAPER_LIGHT := Color(0.98, 0.94, 0.82)
const PAPER_DARK := Color(0.8, 0.68, 0.48)

## Grupos de teclas: [titulo, [[teclas...], o que faz], ...]
const LEFT := [
	["Movimento", [
		[["W", "A", "S", "D"], "andar"],
		[["setas"], "também andam"],
	]],
	["Combate", [
		[["Espaço"], "atacar"],
		[["1", "2", "3"], "habilidades"],
		[["4"], "poção de vida"],
		[["Tab"], "trocar de alvo"],
	]],
]
const RIGHT := [
	["Mundo", [
		[["E"], "falar / abrir baú"],
		[["I"], "inventário"],
		[["G"], "convidar para o grupo"],
	]],
	["Chat", [
		[["Enter"], "conversar"],
		[["/"], "comandos (/w, /g, /z)"],
	]],
	["Menus", [
		[["Esc"], "pausa e volume"],
		[["F1"], "esta ajuda"],
	]],
]
const GUIDE := [
	"Fale com o Ancião na praça (tecla E) e aceite a missão.",
	"Derrote os monstros. O progresso aparece à direita da tela.",
	"Volte ao NPC com \"?\" para ganhar XP e itens.",
	"Equipe o que ganhar no inventário (tecla I).",
	"A leste ficam a Floresta e a Caverna. Abra os baús!",
	"Jogue junto: clique num jogador e aperte G.",
]

var _pages: Array[Control] = []
var _tabs: Array[Button] = []


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.dimmer())
	var origin := ((Vector2(480, 270) - SIZE) / 2.0).round()
	var page := UiKit.parchment(SIZE, 6.0)
	page.position = origin
	add_child(page)
	var title := UiKit.gothic("Ajuda", 24, UiKit.RUBRIC)
	title.position = origin + Vector2(18, 4)
	add_child(title)
	# Abas: dois marcadores lado a lado, a ativa "colada" na pagina
	var tabs := HBoxContainer.new()
	tabs.position = origin + Vector2(84, 14)
	tabs.add_theme_constant_override("separation", 4)
	add_child(tabs)
	for i in 2:
		var b := Button.new()
		b.text = ["Controles", "Como jogar"][i]
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size = Vector2(72, 15)
		b.pressed.connect(show_tab.bind(i))
		tabs.add_child(b)
		_tabs.append(b)
	var esc := UiKit.ink_text("Esc fecha")
	esc.position = origin + Vector2(SIZE.x - 66, 14)
	esc.modulate.a = 0.6
	add_child(esc)
	var rule := ColorRect.new()
	rule.color = Color(UiKit.INK, 0.45)
	rule.position = origin + Vector2(16, 30)
	rule.size = Vector2(SIZE.x - 32, 1)
	add_child(rule)
	_pages.append(_build_keys(origin + Vector2(22, 38)))
	_pages.append(_build_guide(origin + Vector2(22, 42)))
	show_tab(0)


func _build_keys(at: Vector2) -> Control:
	var root := Control.new()
	root.position = at
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	for c in 2:
		var y := 0.0
		for group in [LEFT, RIGHT][c]:
			var head := UiKit.ink_text(String(group[0]).to_upper())
			head.add_theme_color_override("font_color", UiKit.RUBRIC)
			head.position = Vector2(c * 180.0, y)
			root.add_child(head)
			y += HEAD
			for entry in group[1]:
				var x := c * 180.0
				for k: String in entry[0]:
					var cap := _keycap(k)
					cap.position = Vector2(x, y + 1)
					root.add_child(cap)
					x += cap.size.x + 2
				var desc := UiKit.ink_text(entry[1])
				desc.position = Vector2(maxf(x + 5, c * 180.0 + (58.0 if c == 0 else 44.0)), y)
				root.add_child(desc)
				y += ROW
			y += 2
	return root


## Uma tecla: papel claro, borda de tinta e "sombra" embaixo.
func _keycap(text: String) -> Label:
	var l := UiKit.ink_text(text)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var st := StyleBoxFlat.new()
	st.bg_color = PAPER_LIGHT
	st.border_color = Color(UiKit.INK, 0.8)
	st.set_border_width_all(1)
	st.border_width_bottom = 2
	st.set_corner_radius_all(2)
	st.content_margin_left = 3
	st.content_margin_right = 3
	st.content_margin_top = -2
	st.content_margin_bottom = -1
	l.add_theme_stylebox_override("normal", st)
	l.custom_minimum_size = Vector2(13, 13)
	l.reset_size()
	return l


func _build_guide(at: Vector2) -> Control:
	var root := Control.new()
	root.position = at
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	for i in GUIDE.size():
		var y := i * 28.0
		var badge := UiKit.ink_text(str(i + 1))
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.add_theme_color_override("font_color", PAPER_LIGHT)
		var st := StyleBoxFlat.new()
		st.bg_color = UiKit.RUBRIC
		st.set_corner_radius_all(7)
		st.content_margin_top = -2
		st.content_margin_bottom = -1
		badge.add_theme_stylebox_override("normal", st)
		badge.custom_minimum_size = Vector2(14, 14)
		badge.position = Vector2(0, y + 2)
		root.add_child(badge)
		var text := UiKit.ink_text(GUIDE[i])
		text.position = Vector2(22, y + 1)
		root.add_child(text)
		if i < GUIDE.size() - 1:
			var dots := ColorRect.new()
			dots.color = Color(UiKit.INK, 0.15)
			dots.position = Vector2(22, y + 21)
			dots.size = Vector2(SIZE.x - 66, 1)
			root.add_child(dots)
	return root


func show_tab(i: int) -> void:
	for p in _pages.size():
		_pages[p].visible = p == i
		_style_tab(_tabs[p], p == i)


## Aba ativa: papel claro com texto vermelho; inativa: papel escuro, apagada.
func _style_tab(b: Button, active: bool) -> void:
	var st := StyleBoxFlat.new()
	st.bg_color = PAPER_LIGHT if active else Color(PAPER_DARK, 0.55)
	st.border_color = Color(UiKit.INK, 0.7 if active else 0.35)
	st.set_border_width_all(1)
	st.border_width_bottom = 0
	st.corner_radius_top_left = 3
	st.corner_radius_top_right = 3
	st.content_margin_top = -2
	st.content_margin_bottom = 0
	var hover := st.duplicate() as StyleBoxFlat
	hover.bg_color = PAPER_LIGHT
	for s in ["normal", "pressed", "focus"]:
		b.add_theme_stylebox_override(s, st)
	b.add_theme_stylebox_override("hover", hover)
	var color := UiKit.RUBRIC if active else Color(UiKit.INK, 0.75)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, color)
	b.add_theme_constant_override("outline_size", 0)


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open(tab := 0) -> void:
	visible = true
	show_tab(tab)
	GameAudio.play("open")
	_tabs[tab].grab_focus()


func close() -> void:
	visible = false
	_mark_seen()


## Primeira vez neste PC? (abre sozinha na entrada do jogo)
static func first_time() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(Session.PREFS_PATH)
	return not bool(cfg.get_value("ui", "tutorial_seen", false))


func _mark_seen() -> void:
	var cfg := ConfigFile.new()
	cfg.load(Session.PREFS_PATH)
	if not bool(cfg.get_value("ui", "tutorial_seen", false)):
		cfg.set_value("ui", "tutorial_seen", true)
		cfg.save(Session.PREFS_PATH)
