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

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _marker: Label = $Marker


func _ready() -> void:
	if frames:
		_sprite.sprite_frames = frames
	_sprite.play("idle_down")
	$NameLabel.text = display_name
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		return
	PlayerData.changed.connect(_refresh_marker)
	_refresh_marker()


func _refresh_marker() -> void:
	var me := PlayerData.me
	var mark := ""
	if not me.is_empty():
		for q in PlayerData.quests_of(npc_id):
			var st := PlayerData.quest_state(me.quests, q.id)
			if st == "active" and int(me.quest_progress.get(q.id, 0)) >= q.count:
				mark = "?"
				break
			if st == "" and PlayerData.can_accept(me, q):
				mark = "!"
	_marker.text = mark
	_marker.visible = mark != ""
