extends Control
## Menu principal: Entrar no mundo (nome, IP e porta do servidor dedicado).
## Grava a escolha em Session e abre o jogo, que conecta ao servidor (E5/E6).
##
## Visual de manuscrito iluminado: pagina de pergaminho (shader), letra
## capitular "E" com janela em arco mostrando a vila ao vivo (SubViewport)
## com um cavaleiro andando, titulo em letra gotica e opcoes em tinta que
## ficam vermelhas (rubrica) ao selecionar.

const GAME_SCENE := "res://scenes/main/main.tscn"
const PAN_SPEED := 16.0                   ## px/s do passeio na janela
const MUSIC_DB := -12.0
const ARROW := preload("res://assets/ui/ninja/Theme/Theme Wood/arrow_right.png")

@onready var _viewport: SubViewport = $VillageViewport
@onready var _village: Village = $VillageViewport/Village
@onready var _camera: Camera2D = $VillageViewport/Camera2D
@onready var _knight: AnimatedSprite2D = $VillageViewport/Camera2D/Knight/Sprite
@onready var _music: AudioStreamPlayer = $Music
@onready var _fade: ColorRect = $FadeLayer/Fade

@onready var _main_page: Control = %MainPage
@onready var _join_page: Control = %JoinPage
@onready var _join_name: LineEdit = %JoinName
@onready var _join_ip: LineEdit = %JoinIp
@onready var _join_port: LineEdit = %JoinPort
@onready var _join_error: Label = %JoinError

var _pan_points: Array[Vector2] = []
var _pan_index := 0
var _no_arrow: Texture2D
var _leaving := false


func _ready() -> void:
	# --join=IP na linha de comando: pula o menu (testes rapidos)
	if Session.apply_cmdline():
		get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
		return
	_show_notice(Session.last_error)
	Session.last_error = ""

	%JoinButton.pressed.connect(_show_page.bind(_join_page))
	%QuitButton.pressed.connect(_quit)
	%JoinBack.pressed.connect(_show_page.bind(_main_page))
	%JoinConnect.pressed.connect(_on_join_connect)
	_join_ip.text_submitted.connect(func(_t: String) -> void: _on_join_connect())

	%Version.text = "v" + GameVersion.VERSION
	_join_name.text = Session.player_name
	_join_port.text = str(Session.port)
	_join_ip.text = Session.host_ip

	%VillageView.texture = _viewport.get_texture()
	_setup_menu_buttons()
	_setup_window_scene()
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
	var dir := target - _camera.position
	_camera.position = _camera.position.move_toward(target, PAN_SPEED * delta)
	_update_knight(dir)
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
	for p in [_main_page, _join_page]:
		p.visible = p == page
	_set_error(_join_error, "")
	if page == _main_page:
		%JoinButton.grab_focus()
	else:
		_join_ip.grab_focus()
	page.modulate.a = 0.0
	create_tween().tween_property(page, "modulate:a", 1.0, 0.25)


## Aviso no topo das opcoes (ex.: motivo de ter voltado da partida).
func _show_notice(msg: String) -> void:
	%Notice.text = msg
	%Notice.visible = not msg.is_empty()


## A mensagem de erro so ocupa espaco quando existe.
func _set_error(label: Label, msg: String) -> void:
	label.text = msg
	label.visible = not msg.is_empty()




# ---------- acoes ----------


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


# ---------- cena viva na janela da capitular ----------

func _setup_window_scene() -> void:
	var b := _village.get_bounds()
	_camera.limit_left = int(b.position.x)
	_camera.limit_top = int(b.position.y)
	_camera.limit_right = int(b.end.x)
	_camera.limit_bottom = int(b.end.y)
	# Rota do cavaleiro passando pelas casas, mercado, lago e area de treino
	var spawn := _village.get_spawn_position()
	_pan_points = [
		spawn + Vector2(0, -100),     # mercado / estrada norte
		Vector2(330, 180),            # casa bege
		Vector2(232, 205),            # casa laranja
		Vector2(140, 300),            # area de treino
		Vector2(380, 450),            # loja ao sul
		Vector2(690, 430),            # lago
		Vector2(650, 230),            # casas do leste
		Vector2(560, 175),            # casa vermelha
	]
	# comeca em frente a casa bege, ja com algo bonito na janela
	_camera.position = _pan_points[1]
	_pan_index = 2


## O cavaleiro fica no centro da janela e anda na direcao do passeio.
func _update_knight(dir: Vector2) -> void:
	if dir.length() < 0.5:
		_knight.play("idle_down")
		return
	var anim := "walk_"
	if absf(dir.x) > absf(dir.y):
		anim += "right" if dir.x > 0.0 else "left"
	else:
		anim += "down" if dir.y > 0.0 else "up"
	if _knight.animation != anim:
		_knight.play(anim)


func _play_intro() -> void:
	_fade.color.a = 1.0
	var t := create_tween().set_parallel()
	t.tween_property(_fade, "color:a", 0.0, 1.2)
	t.tween_property(_music, "volume_db", MUSIC_DB, 2.0)
	var stream := _music.stream as AudioStreamOggVorbis
	if stream:
		stream.loop = true
	_music.play()
