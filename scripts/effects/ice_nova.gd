extends Node2D
## Nova de Gelo (Mago): espinhos de gelo em volta de quem lancou. So no cliente.

const FRAMES := preload("res://resources/effects/ice_frames.tres")
## Distancia dos espinhos (perto do raio da habilidade, resources/abilities/nova_gelo.tres).
const RING := 22.0
const SPIKES := 7


func _ready() -> void:
	_spike(Vector2.ZERO, 0.0)
	for i in SPIKES:
		_spike(Vector2.from_angle(TAU * i / SPIKES) * RING, 0.03 * i)
	get_tree().create_timer(1.2).timeout.connect(queue_free)


func _spike(pos: Vector2, delay: float) -> void:
	var s := AnimatedSprite2D.new()
	s.sprite_frames = FRAMES
	s.position = pos + Vector2(0, -8)
	add_child(s)
	if delay > 0.0:
		s.visible = false
		await get_tree().create_timer(delay).timeout
		if not is_instance_valid(s):
			return
		s.visible = true
	s.play("ice")
