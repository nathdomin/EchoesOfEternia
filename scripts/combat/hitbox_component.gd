class_name HitboxComponent
extends Node2D
## Area que pode ser atingida (E11): um circulo em volta do corpo. O
## servidor usa para decidir se um golpe acertou (sem depender de fisica,
## que no servidor so roda a 60 quadros).
##
## Golpe corpo a corpo (revisao do combate): a area e um circulo a frente de
## quem bate, no mesmo lugar onde o efeito de corte e desenhado
## (`Player.spawn_slash` usa `arc_center`). Assim o que se ve e o que acerta.

## Centro do corte a `reach` x ARC_FORWARD da origem, com raio reach x ARC_RADIUS.
## Com reach 20: centro a 12 px, raio 14 (alcance ate 26 px + o corpo do alvo).
const ARC_FORWARD := 0.6
const ARC_RADIUS := 0.7

@export var radius := 8.0


## Centro em coordenadas locais da zona (o dono fica direto no container
## da zona: Monsters/Players). No servidor as zonas ficam afastadas.
func center() -> Vector2:
	return get_parent().position + position


## Centro do corte de quem bate de `origin` na direcao `dir` (normalizada).
static func arc_center(origin: Vector2, dir: Vector2, reach: float) -> Vector2:
	return origin + dir * reach * ARC_FORWARD


## O golpe que sai de `origin` na direcao `dir` (normalizada), com alcance
## `reach`, acerta este hitbox? O circulo do corte encosta no corpo?
func is_hit_by(origin: Vector2, dir: Vector2, reach: float) -> bool:
	return overlaps(arc_center(origin, dir, reach), reach * ARC_RADIUS)


## Um circulo (area de habilidade, pisao) encosta no corpo?
func overlaps(point: Vector2, area_radius: float) -> bool:
	return center().distance_to(point) <= area_radius + radius
