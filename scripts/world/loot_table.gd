class_name LootTable
extends Resource
## Tabela de saque (bau, revisao do cenario). Cada item tem uma chance; o
## bau sempre da pelo menos `guaranteed` (o primeiro da lista se nada sair).

@export var items: Array[ItemData] = []
@export var chances: Array[float] = []
## Quantidade de cada item que sair (mesmo indice); vazio = 1.
@export var amounts: Array[int] = []
@export var guaranteed: ItemData
## Tempo para o mesmo jogador poder abrir de novo (s). Cada jogador tem o seu.
@export var respawn_seconds := 600


## Sorteia: lista de {"item": ItemData, "n": int}.
func roll() -> Array:
	var out := []
	for i in items.size():
		if i < chances.size() and randf() < chances[i]:
			out.append({"item": items[i], "n": amounts[i] if i < amounts.size() else 1})
	if out.is_empty() and guaranteed:
		out.append({"item": guaranteed, "n": 1})
	return out
