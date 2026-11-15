class_name UiKit
extends RefCounted
## Pecas de interface reutilizadas pela HUD (E17-E22). Dois estilos:
## - janelas escuras (DarkPanel) para a HUD e o inventario;
## - pergaminho de manuscrito (shader parchment) para dialogo, escolha de
##   classe e pausa, igual ao menu principal.

const PARCHMENT := preload("res://shaders/parchment.gdshader")
const GOTHIC := preload("res://assets/ui/fonts/jacquard24.ttf")
const GOTHIC_SMALL := preload("res://assets/ui/fonts/jacquard12.ttf")
const INK := Color(0.2, 0.11, 0.08)
const RUBRIC := Color(0.66, 0.11, 0.08)
const GOLD := Color(1, 0.85, 0.4)


## Pagina de pergaminho do tamanho pedido (moldura e vinhas pelo shader).
static func parchment(size: Vector2, margin := 8.0) -> ColorRect:
	var r := ColorRect.new()
	r.custom_minimum_size = size
	r.size = size
	var mat := ShaderMaterial.new()
	mat.shader = PARCHMENT
	mat.set_shader_parameter("size", size)
	mat.set_shader_parameter("frame_margin", margin)
	r.material = mat
	return r


static func label(text: String, color := Color(1, 0.96, 0.88), ink := false) -> Label:
	var l := Label.new()
	l.text = text
	if ink:
		l.theme_type_variation = &"InkLabel"
	l.add_theme_color_override("font_color", color if not ink else INK)
	return l


static func ink_text(text: String, width := 0.0) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"InkLabel"
	l.text = text
	if width > 0.0:
		l.custom_minimum_size.x = width
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func gothic(text: String, size := 24, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", GOTHIC if size >= 24 else GOTHIC_SMALL)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 0)
	return l


## Botao de tinta (vermelho de rubrica ao passar o mouse), para o pergaminho.
static func ink_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = &"InkMenuButton"
	b.focus_mode = Control.FOCUS_ALL
	return b


static func dark_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"DarkPanel"
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


static func bar(width: float, height: float, fill: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(width, height)
	b.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.06, 0.06, 0.9)
	bg.set_border_width_all(1)
	bg.border_color = Color(0.05, 0.02, 0.02)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


## Quadradinho de icone (inventario, barra de habilidades).
static func slot(size := 22.0) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(size, size)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.1, 0.06, 0.05, 0.85)
	st.set_border_width_all(1)
	st.border_color = Color(0.55, 0.4, 0.22)
	p.add_theme_stylebox_override("panel", st)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 1; icon.offset_top = 1; icon.offset_right = -1; icon.offset_bottom = -1
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(icon)
	var count := Label.new()
	count.name = "Count"
	count.add_theme_font_size_override("font_size", 11)
	# Posicao fixa (ancorar no canto empurrava o numero para fora quando o
	# quadrado ganhava tamanho depois de criado)
	count.position = Vector2(size - 14, size - 15)
	count.size = Vector2(13, 14)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(count)
	return p


## Fundo escuro que tampa a tela atras de uma janela modal.
static func dimmer() -> ColorRect:
	var d := ColorRect.new()
	d.color = Color(0, 0, 0, 0.45)
	d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return d
