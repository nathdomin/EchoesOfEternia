class_name ControlsWindow
extends Control
## Tutorial (revisao de HUD e controles): pergaminho com duas abas,
## "Controles" (todas as teclas) e "Como jogar" (primeiros passos).
## F1 abre/fecha, tambem pelo menu de pausa. Abre sozinho no primeiro jogo
## deste PC (user://client.cfg, secao "ui", chave "tutorial_seen").

const SIZE := Vector2(372, 214)

const KEYS := [
	["Movimento", [
		["W A S D / setas", "andar (8 direções)"],
	]],
	["Combate", [
		["Espaço / J", "atacar à frente"],
		["1 2 3", "habilidades"],
		["4", "poção de vida"],
		["Clique / Tab", "escolher alvo"],
		["Esc", "limpar o alvo"],
	]],
	["Mundo", [
		["E", "falar / abrir baú"],
		["I", "inventário"],
		["G", "convidar o alvo"],
	]],
	["Chat", [
		["Enter", "abrir o chat"],
		["/", "comandos (/w /g /z)"],
	]],
	["Outros", [
		["Esc", "pausa e volume"],
		["F1", "esta ajuda"],
		["F3", "painel de rede"],
	]],
]

const GUIDE := [
	"1. Fale com o Ancião (o \"!\" na praça) com a tecla E e aceite a missão.",
	"2. Derrote os monstros pedidos. O rastreador à direita mostra o progresso.",
	"3. Volte ao NPC (\"?\") para entregar: XP e itens de recompensa.",
	"4. Equipe o que ganhar no inventário (I). Poções vão na tecla 4.",
	"5. A estrada a leste da vila leva à Floresta Sombria; mais a leste fica a Caverna do Rei Slime. Procure baús pelo caminho.",
	"6. Junte-se a outros: /convidar Nome ou G no jogador. O grupo divide a XP com bônus.",
]

var _pages: Array[Control] = []
var _tabs: Array[Button] = []


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.dimmer())
	var origin := (Vector2(480, 270) - SIZE) / 2.0
	var page := UiKit.parchment(SIZE, 6.0)
	page.position = origin
	add_child(page)
	var title := UiKit.gothic("Ajuda", 24, UiKit.RUBRIC)
	title.position = origin + Vector2(16, 4)
	add_child(title)
	var tabs := HBoxContainer.new()
	tabs.position = origin + Vector2(112, 8)
	tabs.add_theme_constant_override("separation", 12)
	add_child(tabs)
	for i in 2:
		var b := UiKit.ink_button(["Controles", "Como jogar"][i])
		b.pressed.connect(show_tab.bind(i))
		tabs.add_child(b)
		_tabs.append(b)
	var close_hint := UiKit.ink_text("F1 ou Esc fecha")
	close_hint.position = origin + Vector2(SIZE.x - 92, SIZE.y - 26)
	close_hint.modulate.a = 0.7
	add_child(close_hint)
	_pages.append(_build_keys(origin + Vector2(18, 36)))
	_pages.append(_build_guide(origin + Vector2(18, 38)))
	show_tab(0)


func _build_keys(at: Vector2) -> Control:
	var root := Control.new()
	root.position = at
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# Duas colunas de secoes
	var cols := [VBoxContainer.new(), VBoxContainer.new()]
	for c in 2:
		cols[c].position = Vector2(c * 186, 0)
		cols[c].add_theme_constant_override("separation", -3)
		root.add_child(cols[c])
	for s in KEYS.size():
		var col: VBoxContainer = cols[0 if s < 2 else 1]
		var head := UiKit.ink_text(KEYS[s][0])
		head.add_theme_color_override("font_color", UiKit.RUBRIC)
		col.add_child(head)
		for pair in KEYS[s][1]:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			var key := UiKit.ink_text(pair[0])
			key.custom_minimum_size.x = 72 if s < 2 else 46
			key.add_theme_color_override("font_color", Color(0.12, 0.2, 0.42))
			row.add_child(key)
			row.add_child(UiKit.ink_text(pair[1]))
			col.add_child(row)
	return root


func _build_guide(at: Vector2) -> Control:
	var v := VBoxContainer.new()
	v.position = at
	v.add_theme_constant_override("separation", 1)
	add_child(v)
	for line in GUIDE:
		v.add_child(UiKit.ink_text(line, SIZE.x - 40))
	return v


func show_tab(i: int) -> void:
	for p in _pages.size():
		_pages[p].visible = p == i
		_tabs[p].add_theme_color_override("font_color", UiKit.RUBRIC if p == i else UiKit.INK)


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


## Primeira vez neste PC? (abre sozinho na entrada do jogo)
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
