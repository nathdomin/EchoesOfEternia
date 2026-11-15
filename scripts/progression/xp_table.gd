class_name XpTable
extends Resource
## Tabela de XP (E16): quanto falta do nivel N para o N+1.
## O nivel maximo e o tamanho da tabela + 1.

@export var xp_to_next: PackedInt32Array = PackedInt32Array([40, 90, 160, 250, 360, 500, 680, 900, 1200])


func max_level() -> int:
	return xp_to_next.size() + 1


## XP para passar do nivel `level` (0 no nivel maximo).
func needed(level: int) -> int:
	if level < 1 or level >= max_level():
		return 0
	return xp_to_next[level - 1]
