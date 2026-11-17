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

@export_group("Esquiva")
## Distancia (px) e duracao (s) da corrida da esquiva (Shift).
@export var dodge_distance := 40.0
@export var dodge_time := 0.16
## Recarga da esquiva (s; o servidor confere).
@export var dodge_cooldown := 2.5
## Tempo (s) sem levar dano a partir do inicio da esquiva.
@export var dodge_invuln := 0.35

@export_group("Combo")
## Golpes seguidos dentro desta janela (s, alem da recarga) formam o combo.
@export var combo_window := 0.9
## O 3o golpe do combo da este multiplicador de dano...
@export var combo_finisher_mult := 1.6
## ...e empurra o monstro (px; o chefe nao e empurrado).
@export var combo_knockback := 12.0
