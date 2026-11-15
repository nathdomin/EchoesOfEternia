@tool
class_name MonsterSpawnPoint
extends Marker2D
## Onde os monstros de uma zona nascem (E13). Coloque na cena da zona, dentro
## de "MonsterSpawns". O servidor cria `count` monstros espalhados em `radius`
## px; cada um passeia perto do proprio ponto e renasce nele.

@export var monster: MonsterData
@export_range(1, 8) var count := 2
@export var radius := 32.0
