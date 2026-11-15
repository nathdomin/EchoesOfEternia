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
var _xp_bar: ProgressBar
var _display_name := ""


func _ready() -> void:
	_xp_bar = UiKit.bar(78, 3, Color(0.95, 0.75, 0.25))
	_xp_bar.tooltip_text = "Experiência"
	_player_text.get_parent().add_child(_xp_bar)
	var party := PartyFrames.new()
	party.position = Vector2(4, 52)
	add_child(party)
	var tracker := QuestTracker.new()
	tracker.position = Vector2(480 - 164, 22)
	tracker.custom_minimum_size.x = 160
	add_child(tracker)
	hotbar = Hotbar.new()
	hotbar.position = Vector2(240 - (4 * Hotbar.SLOT + 9) / 2.0, 270 - Hotbar.SLOT - 4)
	add_child(hotbar)
	chat = ChatBox.new()
	chat.bottom_left = Vector2(4, 240)  # acima da barra de habilidades
	add_child(chat)
	dialogue = DialogueBox.new()
	add_child(dialogue)
	inventory = InventoryWindow.new()
	inventory.position = Vector2(92, 50)
	add_child(inventory)
	class_chooser = ClassChooser.new()
	add_child(class_chooser)
	debug_panel = DebugPanel.new()
	add_child(debug_panel)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	PlayerData.changed.connect(_on_me_changed)
	_on_me_changed()


## Alguma janela que pega o teclado esta aberta? (o personagem nao anda)
func blocks_input() -> bool:
	return chat.is_open or dialogue.visible or class_chooser.visible or pause_menu.visible


func _on_me_changed() -> void:
	var me := PlayerData.me
	if me.is_empty():
		return
	if not _display_name.is_empty():
		_player_name.text = "%s  Nv %d" % [_display_name, me.level]
	_xp_bar.max_value = maxi(int(me.xp_next), 1)
	_xp_bar.value = int(me.xp) if int(me.xp_next) > 0 else _xp_bar.max_value
	_xp_bar.tooltip_text = "XP %d/%d" % [me.xp, me.xp_next] if int(me.xp_next) > 0 else "Nível máximo"
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
	if target == null:
		return
	if not is_instance_valid(target):
		set_target(null)
		return
	var dead: bool = target.is_dead() if target is Monster else target.dead
	_target_bar.max_value = maxi(target.max_hp, 1)
	_target_bar.value = 0 if dead else target.hp
	_target_text.text = "derrotado" if dead else "%d/%d" % [target.hp, target.max_hp]
