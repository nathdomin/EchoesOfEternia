extends Node2D
## Tocha na parede da caverna (Fase 6): chama animada + luz que tremula.
## So enfeite do cliente; no servidor fica parada.

const FRAMES := 8
const FPS := 10.0

var _t := 0.0
@onready var _flame: Sprite2D = $Flame
@onready var _light: PointLight2D = $Light


func _ready() -> void:
	_t = randf() * 10.0
	if multiplayer.is_server() or DisplayServer.get_name() == "headless":
		set_process(false)
		_light.enabled = false


func _process(delta: float) -> void:
	_t += delta
	_flame.frame = int(_t * FPS) % FRAMES
	_light.energy = 0.6 + 0.1 * sin(_t * 9.0) + 0.05 * sin(_t * 23.0)
