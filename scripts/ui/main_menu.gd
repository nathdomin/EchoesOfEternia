extends Node2D
## Menu principal (E4): Hospedar (nome, porta, IPs) e Entrar (nome, IP, porta).
## Grava a escolha em Session e abre o jogo. A rede de verdade entra na E5.
##
## Visual: vila ao entardecer ao fundo com camera passeando, vegetacao em
## silhueta no primeiro plano, particulas, logo com brilho, menu so de texto
## com seta na opcao selecionada, musica e fade de entrada/saida.

const GAME_SCENE := "res://scenes/main/main.tscn"
const PAN_SPEED := 12.0                   ## px/s do passeio da camera
const SUNSET_TINT := Color(0.86, 0.62, 0.56)
const MUSIC_DB := -12.0
const ARROW := preload("res://assets/ui/ninja/Theme/Theme Wood/arrow_right.png")

@onready var _camera: Camera2D = $Camera2D
@onready var _village: Village = $Village
@onready var _music: AudioStreamPlayer = $Music
@onready var _fade: ColorRect = $FadeLayer/Fade
@onready var _logo: Control = %Logo

@onready var _main_page: Control = %MainPage
@onready var _host_page: Control = %HostPage
@onready var _join_page: Control = %JoinPage
@onready var _host_name: LineEdit = %HostName
@onready var _join_name: LineEdit = %JoinName
@onready var _ip_list: VBoxContainer = %IpList
@onready var _host_port: LineEdit = %HostPort
@onready var _host_error: Label = %HostError
@onready var _join_ip: LineEdit = %JoinIp
@onready var _join_port: LineEdit = %JoinPort
@onready var _join_error: Label = %JoinError

var _pan_points: Array[Vector2] = []
var _pan_index := 0
var _no_arrow: Texture2D
var _leaving := false


func _ready() -> void:
	%HostButton.pressed.connect(_show_page.bind(_host_page))
	%JoinButton.pressed.connect(_show_page.bind(_join_page))
	%QuitButton.pressed.connect(_quit)
	%HostBack.pressed.connect(_show_page.bind(_main_page))
	%JoinBack.pressed.connect(_show_page.bind(_main_page))
	%HostStart.pressed.connect(_on_host_start)
	%JoinConnect.pressed.connect(_on_join_connect)
	_join_ip.text_submitted.connect(func(_t: String) -> void: _on_join_connect())
	_host_port.text_submitted.connect(func(_t: String) -> void: _on_host_start())

	%Version.text = "v" + GameVersion.VERSION
	_host_name.text = Session.player_name
	_join_name.text = Session.player_name
	_host_port.text = str(Session.port)
	_join_port.text = str(Session.port)
	_join_ip.text = Session.host_ip

	_setup_menu_buttons()
	_fill_ip_list()
	_setup_background()
	_show_page(_main_page)
	_play_intro()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _main_page.visible and not _leaving:
		_show_page(_main_page)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _pan_points.is_empty():
		return
	var target := _pan_points[_pan_index]
	_camera.position = _camera.position.move_toward(target, PAN_SPEED * delta)
	if _camera.position.distance_to(target) < 1.0:
		_pan_index = (_pan_index + 1) % _pan_points.size()


# ---------- botoes de menu (texto + seta) ----------

func _setup_menu_buttons() -> void:
	# Icone transparente do mesmo tamanho da seta: o texto nao "pula"
	var img := Image.create(ARROW.get_width(), ARROW.get_height(), false, Image.FORMAT_RGBA8)
	_no_arrow = ImageTexture.create_from_image(img)
	for b: Button in get_tree().get_nodes_in_group("menu_buttons"):
		b.icon = _no_arrow
		b.focus_entered.connect(func() -> void: b.icon = ARROW)
		b.focus_exited.connect(func() -> void: b.icon = _no_arrow)
		b.mouse_entered.connect(b.grab_focus)


# ---------- paginas ----------

func _show_page(page: Control) -> void:
	for p in [_main_page, _host_page, _join_page]:
		p.visible = p == page
	_set_error(_host_error, "")
	_set_error(_join_error, "")
	if page == _main_page:
		%HostButton.grab_focus()
	elif page == _host_page:
		%HostStart.grab_focus()
	else:
		_join_ip.grab_focus()
	# entrada suave da pagina
	page.modulate.a = 0.0
	create_tween().tween_property(page, "modulate:a", 1.0, 0.2)


## A mensagem de erro so ocupa espaco quando existe.
func _set_error(label: Label, msg: String) -> void:
	label.text = msg
	label.visible = not msg.is_empty()


func _fill_ip_list() -> void:
	for c in _ip_list.get_children():
		c.queue_free()
	var ips := NetUtils.local_ipv4()
	if ips.is_empty():
		var l := Label.new()
		l.text = "Nenhuma rede encontrada"
		_ip_list.add_child(l)
		return
	for item in ips:
		var b := Button.new()
		b.flat = true
		b.text = "%s  (%s)" % [item.ip, item.kind]
		b.tooltip_text = "Clique para copiar"
		b.add_theme_color_override("font_color", Color(1, 0.86, 0.5))
		b.pressed.connect(_copy_ip.bind(b, item.ip))
		_ip_list.add_child(b)


func _copy_ip(button: Button, ip: String) -> void:
	DisplayServer.clipboard_set(ip)
	var old := button.text
	button.text = "Copiado!"
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(button):
		button.text = old


# ---------- acoes ----------

func _on_host_start() -> void:
	if not NetUtils.is_valid_port(_host_port.text):
		_set_error(_host_error, "Porta inválida (1024 a 65535)")
		return
	Session.setup_host(int(_host_port.text), _host_name.text)
	_leave_to(GAME_SCENE)


func _on_join_connect() -> void:
	if not NetUtils.is_valid_host(_join_ip.text):
		_set_error(_join_error, "IP inválido (ex.: 192.168.0.10)")
		return
	if not NetUtils.is_valid_port(_join_port.text):
		_set_error(_join_error, "Porta inválida (1024 a 65535)")
		return
	Session.setup_join(_join_ip.text, int(_join_port.text), _join_name.text)
	_leave_to(GAME_SCENE)


func _quit() -> void:
	_leave_to("")


## Fade para preto + musica baixando; depois troca de cena (ou fecha o jogo).
func _leave_to(scene: String) -> void:
	if _leaving:
		return
	_leaving = true
	var t := create_tween().set_parallel()
	t.tween_property(_fade, "color:a", 1.0, 0.6)
	t.tween_property(_music, "volume_db", -40.0, 0.6)
	await t.finished
	if scene.is_empty():
		get_tree().quit()
	else:
		get_tree().change_scene_to_file(scene)


# ---------- fundo e animacoes ----------

func _setup_background() -> void:
	var b := _village.get_bounds()
	_camera.limit_left = int(b.position.x)
	_camera.limit_top = int(b.position.y)
	_camera.limit_right = int(b.end.x)
	_camera.limit_bottom = int(b.end.y)
	var c := b.get_center()
	_pan_points = [c + Vector2(-150, -60), c + Vector2(150, -70), c + Vector2(140, 80), c + Vector2(-140, 70)]
	_camera.position = _village.get_spawn_position()

	# Entardecer: tom quente e vinheta mais forte so no menu
	($Ambience/Tint as CanvasModulate).color = SUNSET_TINT
	var vignette := $Ambience/Screen/Vignette as ColorRect
	var mat := vignette.material.duplicate() as ShaderMaterial
	mat.set_shader_parameter("strength", 0.6)
	mat.set_shader_parameter("radius", 0.45)
	vignette.material = mat

	# Vegetacao do primeiro plano balancando com o vento
	for path in ["Foreground/TreeLeft", "Foreground/TreeRight", "Foreground/Pines"]:
		var n := get_node(path) as Node2D
		var sway := create_tween().set_loops().set_trans(Tween.TRANS_SINE)
		var amount := randf_range(0.025, 0.04)
		sway.tween_property(n, "skew", amount, randf_range(2.2, 3.0))
		sway.tween_property(n, "skew", -amount, randf_range(2.2, 3.0))


func _play_intro() -> void:
	_fade.color.a = 1.0
	var t := create_tween().set_parallel()
	t.tween_property(_fade, "color:a", 0.0, 1.2)
	t.tween_property(_music, "volume_db", MUSIC_DB, 2.0)
	var stream := _music.stream as AudioStreamOggVorbis
	if stream:
		stream.loop = true
	_music.play()

	# Logo flutuando devagar
	var y := _logo.position.y
	var bob := create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	bob.tween_property(_logo, "position:y", y + 3.0, 1.8)
	bob.tween_property(_logo, "position:y", y, 1.8)
