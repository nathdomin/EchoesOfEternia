class_name GameHud
extends CanvasLayer
## HUD do jogo (E12, E16-E22): quadro do jogador (retrato, nome, nivel,
## vida, XP), quadro do alvo, grupo, rastreador de missoes, barra de
## habilidades, chat, inventario, dialogo, escolha de classe e pausa.

@onready var _player_face: TextureRect = %PlayerFace
@onready var _player_name: Label = %PlayerName
@onready var _player_bar: ProgressBar = %PlayerHp
@onready var _player_text: Label = %PlayerHpText
@onready var _target_frame: Control = %TargetFrame
@onready var _target_face: TextureRect = %TargetFace
@onready var _target_name: Label = %TargetName
@onready var _target_bar: ProgressBar = %TargetHp
@onready var _target_text: Label = %TargetHpText

var target: Node2D = null
var chat: ChatBox
var hotbar: Hotbar
var inventory: InventoryWindow
var dialogue: DialogueBox
var class_chooser: ClassChooser
var pause_menu: PauseMenu
var debug_panel: DebugPanel
var controls: ControlsWindow
var _tutorial_pending := false
var _level_badge: Label
var _death: Control
var _death_count: Label
var _xp_bar: ProgressBar
var _display_name := ""


func _ready() -> void:
	_xp_bar = UiKit.bar(78, 3, Color(0.95, 0.75, 0.25))
	_xp_bar.tooltip_text = "Experiência"
	_xp_bar.mouse_filter = Control.MOUSE_FILTER_PASS  # UiKit.bar ignora o mouse: sem isso a dica nunca aparecia
	# Nome do alvo longo (jogador "Nome  Nv 10  (G convida)") nao alarga o quadro
	_target_name.clip_text = true
	_target_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_player_text.get_parent().add_child(_xp_bar)
	var party := PartyFrames.new()
	party.position = Vector2(4, 58)
	add_child(party)
	var tracker := QuestTracker.new()
	tracker.position = Vector2(480 - 164, 22)
	tracker.custom_minimum_size.x = 160
	add_child(tracker)
	hotbar = Hotbar.new()
	hotbar.position = Vector2(240 - (4 * Hotbar.SLOT + 9) / 2.0, 270 - Hotbar.SLOT - 5)
	# Moldura de madeira atras da barra
	var frame := UiKit.wood_frame(Vector2(4 * Hotbar.SLOT + 9 + 8, Hotbar.SLOT + 8))
	frame.position = hotbar.position - Vector2(4, 4)
	add_child(frame)
	add_child(hotbar)
	var help := Label.new()
	help.text = "F1 Ajuda"
	help.position = Vector2(480 - 46, 270 - 16)
	help.modulate = Color(1, 1, 1, 0.75)
	help.add_theme_constant_override("outline_size", 3)
	help.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.03))
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(help)
	# Brasao de nivel sobre o canto do retrato
	_level_badge = Label.new()
	_level_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_badge.add_theme_color_override("font_color", UiKit.GOLD)
	var badge := StyleBoxFlat.new()
	badge.bg_color = Color(0.45, 0.08, 0.06)
	badge.set_border_width_all(1)
	badge.border_color = UiKit.GOLD
	badge.set_corner_radius_all(3)
	badge.content_margin_left = 2
	badge.content_margin_right = 2
	badge.content_margin_top = -2
	badge.content_margin_bottom = -1
	_level_badge.add_theme_stylebox_override("normal", badge)
	_level_badge.position = Vector2(1, 22)
	_level_badge.mouse_filter = Control.MOUSE_FILTER_PASS  # dica com nivel e XP
	_player_face.add_child(_level_badge)
	chat = ChatBox.new()
	chat.bottom_left = Vector2(4, 240)  # acima da barra de habilidades
	add_child(chat)
	dialogue = DialogueBox.new()
	add_child(dialogue)
	inventory = InventoryWindow.new()
	inventory.position = (Vector2(480, 270) - InventoryWindow.SIZE) / 2.0 - Vector2(0, 8)
	add_child(inventory)
	class_chooser = ClassChooser.new()
	add_child(class_chooser)
	debug_panel = DebugPanel.new()
	add_child(debug_panel)
	_build_death_screen()
	controls = ControlsWindow.new()
	add_child(controls)
	_tutorial_pending = ControlsWindow.first_time()
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	PlayerData.changed.connect(_on_me_changed)
	_on_me_changed()


## Tela de morte: vermelho escuro, "Voce morreu" grande e a contagem.
func _build_death_screen() -> void:
	_death = Control.new()
	_death.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_death.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death.visible = false
	var shade := ColorRect.new()
	shade.color = Color(0.25, 0.0, 0.0, 0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death.add_child(shade)
	var title := UiKit.gothic("Você morreu", 48, Color(0.95, 0.25, 0.2))
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_color_override("font_outline_color", Color(0.08, 0.02, 0.02))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(480, 56)
	title.position = Vector2(0, 88)
	_death.add_child(title)
	_death_count = Label.new()
	_death_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_count.size = Vector2(480, 16)
	_death_count.position = Vector2(0, 146)
	_death_count.add_theme_constant_override("outline_size", 4)
	_death_count.add_theme_color_override("font_outline_color", Color(0.08, 0.02, 0.02))
	_death.add_child(_death_count)
	add_child(_death)


## seconds < 0 esconde a tela de morte.
func show_death(seconds: float) -> void:
	_death.visible = seconds >= 0.0
	if _death.visible:
		_death_count.text = "Renascendo na praça da vila em %d s..." % ceili(seconds)


## Alguma janela que pega o teclado esta aberta? (o personagem nao anda)
func blocks_input() -> bool:
	return chat.is_open or dialogue.visible or class_chooser.visible or pause_menu.visible or controls.visible



func _on_me_changed() -> void:
	var me := PlayerData.me
	if me.is_empty():
		return
	if not _display_name.is_empty():
		_player_name.text = _display_name
	_level_badge.text = str(me.level)
	_level_badge.reset_size()
	_xp_bar.max_value = maxi(int(me.xp_next), 1)
	_xp_bar.value = int(me.xp) if int(me.xp_next) > 0 else _xp_bar.max_value
	_xp_bar.tooltip_text = "XP %d/%d" % [me.xp, me.xp_next] if int(me.xp_next) > 0 else "Nível máximo"
	_level_badge.tooltip_text = "Nv %d  ·  %s" % [me.level, _xp_bar.tooltip_text]
	if String(me.get("class", "")) != "":
		_player_face.texture = Player.FACESETS.get(PlayerData.class_data(me["class"]).skin, _player_face.texture)


func setup_player(skin: String, display_name: String) -> void:
	_player_face.texture = Player.FACESETS.get(skin, Player.FACESETS.knight)
	_display_name = display_name
	_player_name.text = display_name
	_on_me_changed()


func set_health(hp: int, max_hp: int) -> void:
	_player_bar.max_value = maxi(max_hp, 1)
	_player_bar.value = hp
	_player_text.text = "%d/%d" % [hp, max_hp]


## Seleciona o alvo (Monster ou RemotePlayer); null limpa.
func set_target(node: Node2D) -> void:
	target = node
	_target_frame.visible = node != null
	if node == null:
		return
	if node is Monster:
		_target_name.text = node.display_name() + ("  (chefe)" if node.data.is_boss else "")
		_target_face.texture = node.data.faceset
	elif node is RemotePlayer:
		_target_name.text = "%s  Nv %d  (G convida)" % [node.display_name, node.level]
		_target_face.texture = Player.FACESETS.get(node.skin, Player.FACESETS.knight)
	_process(0.0)


func _process(_delta: float) -> void:
	# Primeiro jogo neste PC: abre a ajuda depois da escolha de classe
	if _tutorial_pending and not class_chooser.visible and String(PlayerData.me.get("class", "")) != "":
		_tutorial_pending = false
		controls.open(1)
	if target == null:
		return
	if not is_instance_valid(target):
		set_target(null)
		return
	var dead: bool = target.is_dead() if target is Monster else target.dead
	_target_bar.max_value = maxi(target.max_hp, 1)
	_target_bar.value = 0 if dead else target.hp
	_target_text.text = "derrotado" if dead else "%d/%d" % [target.hp, target.max_hp]
