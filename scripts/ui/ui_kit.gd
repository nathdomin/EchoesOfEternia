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


const ARROW := preload("res://assets/ui/ninja/Theme/Theme Wood/arrow_right.png")
static var _no_arrow: Texture2D


## Opcoes de escolha (dialogo, classe, pausa) que funcionam com mouse e
## teclado do mesmo jeito: a seta aparece so no botao focado, passar o mouse
## move o foco (o Enter aperta o que se ve marcado) e as setas dao a volta.
## `wrap` = falso deixa o Godot achar os vizinhos (janela com outros controles).
static func choices(buttons: Array, focus_first := true, wrap := true) -> void:
	if buttons.is_empty():
		return
	if _no_arrow == null:
		_no_arrow = ImageTexture.create_from_image(
				Image.create(ARROW.get_width(), ARROW.get_height(), false, Image.FORMAT_RGBA8))
	var n := buttons.size()
	for i in n:
		var b: Button = buttons[i]
		var prev: Button = buttons[(i - 1 + n) % n]
		var next: Button = buttons[(i + 1) % n]
		b.icon = _no_arrow
		b.focus_mode = Control.FOCUS_ALL
		for c in ["icon_normal_color", "icon_focus_color", "icon_hover_color", "icon_pressed_color", "icon_disabled_color"]:
			b.add_theme_color_override(c, RUBRIC)  # seta vermelha (rubrica) em qualquer botao
		b.focus_entered.connect(func() -> void:
			b.icon = ARROW
			GameAudio.play("click", 0.0, 0.35))
		b.focus_exited.connect(func() -> void: b.icon = _no_arrow)
		b.mouse_entered.connect(b.grab_focus)
		# Vizinhos em laco: so depois que todos estao na arvore
		var link := func() -> void:
			for x: Variant in [b, prev, next]:
				if not is_instance_valid(x) or not (x as Node).is_inside_tree() \
						or (x as Node).is_queued_for_deletion():
					return
			for side in [SIDE_LEFT, SIDE_TOP]:
				b.set_focus_neighbor(side, b.get_path_to(prev))
			for side in [SIDE_RIGHT, SIDE_BOTTOM]:
				b.set_focus_neighbor(side, b.get_path_to(next))
			b.focus_previous = b.get_path_to(prev)
			b.focus_next = b.get_path_to(next)
		if wrap:
			link.call_deferred()
	if focus_first:
		var first: Button = buttons[0]
		(func() -> void:
			if is_instance_valid(first) and first.is_visible_in_tree() and not first.is_queued_for_deletion():
				first.grab_focus()).call_deferred()


## Controle deslizante em tinta (volume na pausa): linha marrom, marcador vermelho.
static func ink_slider(width := 90.0) -> HSlider:
	var s := HSlider.new()
	s.custom_minimum_size = Vector2(width, 12)
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.focus_mode = Control.FOCUS_ALL
	var track := StyleBoxFlat.new()
	track.bg_color = Color(INK, 0.35)
	track.content_margin_top = 1
	track.content_margin_bottom = 1
	var filled := StyleBoxFlat.new()
	filled.bg_color = RUBRIC
	filled.content_margin_top = 1
	filled.content_margin_bottom = 1
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", filled)
	s.add_theme_stylebox_override("grabber_area_highlight", filled)
	var img := Image.create(5, 9, false, Image.FORMAT_RGBA8)
	img.fill(INK)
	img.fill_rect(Rect2i(1, 1, 3, 7), RUBRIC)
	var knob := ImageTexture.create_from_image(img)
	s.add_theme_icon_override("grabber", knob)
	s.add_theme_icon_override("grabber_highlight", knob)
	var focus := StyleBoxEmpty.new()
	s.add_theme_stylebox_override("focus", focus)
	return s


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


const WOOD_PANEL := preload("res://assets/ui/ninja/Theme/Theme Wood/nine_path_panel.png")


## Moldura de madeira do pacote (9-patch), atras da barra de habilidades.
static func wood_frame(size: Vector2) -> NinePatchRect:
	var n := NinePatchRect.new()
	n.texture = WOOD_PANEL
	n.patch_margin_left = 5
	n.patch_margin_top = 5
	n.patch_margin_right = 5
	n.patch_margin_bottom = 5
	n.size = size
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return n


## Quadradinho de icone (inventario, barra de habilidades). `ink` = no
## pergaminho: fundo de papel mais escuro e borda de tinta.
static func slot(size := 22.0, ink := false) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(size, size)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.1, 0.06, 0.05, 0.85) if not ink else Color(0.62, 0.48, 0.3, 0.45)
	st.set_border_width_all(1)
	st.border_color = Color(0.55, 0.4, 0.22) if not ink else Color(INK, 0.75)
	st.set_corner_radius_all(2 if ink else 0)
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
	count.add_theme_constant_override("outline_size", 3)
	count.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.03))
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(count)
	return p


## Fundo escuro que tampa a tela atras de uma janela modal.
static func dimmer() -> ColorRect:
	var d := ColorRect.new()
	d.color = Color(0, 0, 0, 0.45)
	d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return d
