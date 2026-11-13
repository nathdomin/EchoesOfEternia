class_name Village
extends Node2D
## Vila inicial (E3). Ground = chao sem colisao; Objects = casas, arvores,
## cercas e objetos com colisao (TileSet physics layer 0) e y-sort.

@onready var ground: TileMapLayer = $Ground
@onready var spawn_point: Marker2D = $SpawnPoint


## Limites do mapa em pixels (usado para limitar a camera).
func get_bounds() -> Rect2:
	var used := ground.get_used_rect()
	var tile := Vector2(ground.tile_set.tile_size)
	return Rect2(Vector2(used.position) * tile, Vector2(used.size) * tile)


func get_spawn_position() -> Vector2:
	return spawn_point.global_position
