extends Node2D
## Aviso no chao (combate dinamico): circulo vermelho de `radius` que vai se
## enchendo do centro para a borda em `seconds`. Quando enche, o golpe cai
## (o servidor confere quem ainda esta dentro). So existe no cliente.

const FILL := Color(0.9, 0.12, 0.08, 0.22)
const EDGE := Color(1.0, 0.3, 0.2, 0.85)
const INNER := Color(1.0, 0.25, 0.15, 0.35)

var radius := 40.0
var seconds := 1.0
var _t := 0.0


func _ready() -> void:
	z_index = -1  # no chao, abaixo dos personagens
	GameAudio.play_at("warning", position)


func _process(delta: float) -> void:
	_t += delta
	if _t >= seconds:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := clampf(_t / seconds, 0.0, 1.0)
	draw_circle(Vector2.ZERO, radius, FILL)
	draw_circle(Vector2.ZERO, radius * k, INNER)
	# Borda pisca mais rapido perto do fim
	var blink := 0.6 + 0.4 * sin(_t * lerpf(10.0, 30.0, k))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(EDGE, EDGE.a * blink), 1.0)
