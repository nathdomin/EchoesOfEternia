extends Node2D
## Cena principal: posiciona o player no SpawnPoint da vila e limita a camera
## ao tamanho do mapa. Na E6 o spawn passa a ser feito pelo MultiplayerSpawner.

@onready var _village: Village = $World/Village
@onready var _player: Player = $World/Player


func _ready() -> void:
	_player.global_position = _village.get_spawn_position()
	_player.set_camera_limits(_village.get_bounds())
