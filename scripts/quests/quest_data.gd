class_name QuestData
extends Resource
## Missao (E21). Dada por um NPC (`giver`), com um objetivo de derrotar
## monstros (KILL) ou juntar itens (COLLECT, os itens sao entregues).

enum Kind { KILL, COLLECT, TALK }

@export var id := ""
@export var title := ""
@export var giver := ""              ## npc_id de quem da e recebe a missao
@export var giver_name := ""         ## nome dele no rastreador ("volte ao Ancião")
@export var requires := ""           ## missao que precisa estar concluida antes
@export var min_level := 1
@export_multiline var offer_text := ""
@export_multiline var progress_text := ""
@export_multiline var done_text := ""
@export var kind: Kind = Kind.KILL
@export var target_id := ""          ## monster_id (KILL) ou item_id (COLLECT)
@export var target_name := ""        ## para o rastreador ("Slimes")
@export var count := 5
@export var reward_xp := 50
@export var reward_item: ItemData
@export var reward_count := 1
## Pacote C: ouro de recompensa.
@export var reward_gold := 0
## Pacote C: recompensa conforme a classe (o item com `class_only` igual a
## classe do jogador). Vem alem de `reward_item`.
@export var class_rewards: Array[ItemData] = []
## Pacote C: quem recebe a entrega, se nao for quem deu (TALK: levar um
## recado). Vazio = o proprio `giver`.
@export var turn_in_to := ""
@export var turn_in_name := ""
## Pacote C: pode ser feita de novo depois de tantas horas (0 = uma vez so).
@export var repeat_hours := 0.0


func turn_in_npc() -> String:
	return turn_in_to if turn_in_to != "" else giver


func turn_in_npc_name() -> String:
	return turn_in_name if turn_in_to != "" else giver_name


## Item de classe da recompensa para `class_id` (ou null).
func class_reward(class_id: String) -> ItemData:
	for it in class_rewards:
		if it and it.class_only == class_id:
			return it
	return null
