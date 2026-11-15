class_name CombatStats
extends Resource
## Atributos de combate de um personagem (E11/E12). A E16 (niveis) e a E17
## (classes) somam bonus em cima destes valores; nada fica no codigo.

@export var max_hp := 100
@export var damage := 12
## Segundos entre ataques (o servidor confere).
@export var attack_cooldown := 0.45
## Alcance do golpe a partir do centro do personagem (px).
@export var reach := 20.0
## Sem tomar dano por este tempo (s), a vida volta aos poucos.
@export var regen_delay := 6.0
## Fracao da vida maxima recuperada por segundo.
@export var regen_per_sec := 0.03
