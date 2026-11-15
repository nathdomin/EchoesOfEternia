class_name HitboxComponent
extends Node2D
## Area que pode ser atingida (E11): um circulo em volta do corpo. O
## servidor usa para decidir se um golpe acertou (sem depender de fisica,
## que no servidor so roda a 60 quadros).

@export var radius := 6.0


## Centro em coordenadas locais da zona (o dono fica direto no container
## da zona: Monsters/Players). No servidor as zonas ficam afastadas.
func center() -> Vector2:
	return get_parent().position + position


## O golpe que sai de `origin` na direcao `dir` (normalizada), com alcance
## `reach`, acerta este hitbox? Aceita um cone de ~120 graus a frente.
func is_hit_by(origin: Vector2, dir: Vector2, reach: float) -> bool:
	var to_me := center() - origin
	var dist := to_me.length()
	if dist > reach + radius:
		return false
	if dist < radius + 2.0:
		return true  # colado: acerta em qualquer direcao
	return dir.dot(to_me / dist) >= 0.45
