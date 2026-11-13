extends Node2D
## Menu principal (E4): nome do jogador, Hospedar (mostra IPs e porta) e
## Entrar (IP + porta). Grava a escolha em Session e abre o jogo.
## A conexao de rede de verdade entra na E5 (NetworkManager).

const GAME_SCENE := "res://scenes/main/main.tscn"
const PAN_SPEED := 14.0   ## px/s do passeio da camera no fundo

@onready var _camera: Camera2D = $Camera2D
@onready var _village: Village = $Village

@onready var _main_page: Control = %MainPage
@onready var _host_page: Control = %HostPage
@onready var _join_page: Control = %JoinPage
@onready var _name_edit: LineEdit = %NameEdit
@onready var _ip_list: VBoxContainer = %IpList
@onready var _host_port: LineEdit = %HostPort
@onready var _host_error: Label = %HostError
@onready var _join_ip: LineEdit = %JoinIp
@onready var _join_port: LineEdit = %JoinPort
@onready var _join_error: Label = %JoinError
@onready var _version: Label = %Version

var _pan_points: Array[Vector2] = []
var _pan_index := 0


func _ready() -> void:
	%HostButton.pressed.connect(_show_page.bind(_host_page))
	%JoinButton.pressed.connect(_show_page.bind(_join_page))
	%QuitButton.pressed.connect(get_tree().quit)
	%HostBack.pressed.connect(_show_page.bind(_main_page))
	%JoinBack.pressed.connect(_show_page.bind(_main_page))
	%HostStart.pressed.connect(_on_host_start)
	%JoinConnect.pressed.connect(_on_join_connect)
	_join_ip.text_submitted.connect(func(_t: String) -> void: _on_join_connect())

	_version.text = "v" + GameVersion.VERSION
	_name_edit.text = Session.player_name
	_host_port.text = str(Session.port)
	_join_port.text = str(Session.port)
	_join_ip.text = Session.host_ip
	_fill_ip_list()
	_setup_camera()
	_show_page(_main_page)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _main_page.visible:
		_show_page(_main_page)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _pan_points.is_empty():
		return
	var target := _pan_points[_pan_index]
	_camera.position = _camera.position.move_toward(target, PAN_SPEED * delta)
	if _camera.position.distance_to(target) < 1.0:
		_pan_index = (_pan_index + 1) % _pan_points.size()


# ---------- paginas ----------

func _show_page(page: Control) -> void:
	for p in [_main_page, _host_page, _join_page]:
		p.visible = p == page
	_host_error.text = ""
	_join_error.text = ""
	# foco no primeiro controle util da pagina (navegacao por teclado)
	if page == _main_page:
		%HostButton.grab_focus()
	elif page == _host_page:
		%HostStart.grab_focus()
	else:
		_join_ip.grab_focus()


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
		b.text = "%s  (%s)" % [item.ip, item.kind]
		b.tooltip_text = "Clique para copiar"
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
		_host_error.text = "Porta inválida (1024 a 65535)"
		return
	Session.setup_host(int(_host_port.text), _name_edit.text)
	_start_game()


func _on_join_connect() -> void:
	if not NetUtils.is_valid_host(_join_ip.text):
		_join_error.text = "IP inválido (ex.: 192.168.0.10)"
		return
	if not NetUtils.is_valid_port(_join_port.text):
		_join_error.text = "Porta inválida (1024 a 65535)"
		return
	Session.setup_join(_join_ip.text, int(_join_port.text), _name_edit.text)
	_start_game()


func _start_game() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


# ---------- fundo ----------

func _setup_camera() -> void:
	var b := _village.get_bounds()
	_camera.limit_left = int(b.position.x)
	_camera.limit_top = int(b.position.y)
	_camera.limit_right = int(b.end.x)
	_camera.limit_bottom = int(b.end.y)
	var c := b.get_center()
	_pan_points = [c + Vector2(-150, -60), c + Vector2(150, -70), c + Vector2(140, 80), c + Vector2(-140, 70)]
	_camera.position = _village.get_spawn_position()
