class_name Npc
extends Node2D
## Personagem nao jogavel (E21). Fica na cena da zona, dentro de "Npcs".
## Mostra "!" quando tem missao para oferecer e "?" quando o jogador pode
## entregar uma. A conversa (DialogueBox) usa as QuestData com giver = npc_id.

@export var npc_id := "anciao"
@export var display_name := "Ancião"
@export var frames: SpriteFrames
@export var faceset: Texture2D
@export_multiline var greeting := "Bons ventos, viajante."
## Pacote C: falas depois das missoes (uma por conversa, em sequencia),
## cor do desenho (mesmo personagem com outra roupa) e o que vende.
@export var idle_lines: PackedStringArray = PackedStringArray()
@export var tint := Color.WHITE
@export var shop_items: Array[ItemData] = []

var _line := -1

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _marker: Label = $Marker


func _ready() -> void:
	if frames:
		_sprite.sprite_frames = frames
	_sprite.play("idle_down")
	_sprite.modulate = tint
	$NameLabel.text = display_name
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		return
	PlayerData.changed.connect(_refresh_marker)
	_refresh_marker()


func _refresh_marker() -> void:
	var mark := marker_for(PlayerData.me)
	_marker.text = mark
	_marker.visible = mark != ""


## "?" = tem entrega pronta aqui; "!" = tem missao nova; "" = nada.
func marker_for(me: Dictionary) -> String:
	if me.is_empty():
		return ""
	var mark := ""
	for q in PlayerData.quests_for(npc_id):
		var st := PlayerData.quest_state(me.quests, q.id)
		if st == "active" and q.turn_in_npc() == npc_id and int(me.quest_progress.get(q.id, 0)) >= q.count:
			return "?"
		if q.giver == npc_id and PlayerData.can_accept(me, q, PlayerData.server_now()):
			mark = "!"
	return mark


## Proxima fala solta (depois das missoes). Vazio = so o cumprimento.
func next_idle_line() -> String:
	if idle_lines.is_empty():
		return greeting
	_line = (_line + 1) % (idle_lines.size() + 1)
	return greeting if _line == 0 else idle_lines[_line - 1]
