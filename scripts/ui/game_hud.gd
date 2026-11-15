class_name GameHud
extends CanvasLayer
## HUD do jogo (E12): quadro do jogador (retrato, nome, vida) no canto e
## quadro do alvo (monstro ou jogador selecionado) no topo. A E16 acrescenta
## nivel e XP no quadro do jogador.

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


func setup_player(skin: String, display_name: String) -> void:
	_player_face.texture = Player.FACESETS.get(skin, Player.FACESETS.knight)
	_player_name.text = display_name


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
		_target_name.text = node.display_name()
		_target_face.texture = node.data.faceset
	elif node is RemotePlayer:
		_target_name.text = node.display_name
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
