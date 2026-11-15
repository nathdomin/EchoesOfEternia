extends AnimatedSprite2D
## Efeito que toca uma vez e some (golpe, fumaca). So existe no cliente.


func _ready() -> void:
	animation_finished.connect(queue_free)
	play()
