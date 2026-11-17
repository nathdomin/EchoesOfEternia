class_name QuestData
extends Resource
## Missao (E21). Dada por um NPC (`giver`), com um objetivo de derrotar
## monstros (KILL) ou juntar itens (COLLECT, os itens sao entregues).

enum Kind { KILL, COLLECT }

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
