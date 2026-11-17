class_name ClassData
extends Resource
## Classe jogavel (E17): atributos base, crescimento por nivel e 3 habilidades
## (teclas 1-3 da barra; a 4 e a pocao).

@export var id := "guerreiro"
@export var display_name := "Guerreiro"
@export_multiline var description := ""
@export var skin := "knight"          ## aparencia (Player.SKINS)
@export var base_hp := 120
@export var base_damage := 12
@export var hp_per_level := 18
@export var damage_per_level := 2
@export var attack_cooldown := 0.45
## Golpe basico corpo a corpo: tamanho do corte (HitboxComponent.is_hit_by).
@export var reach := 20.0
## Golpe basico de longe (Arqueiro, Mago): alcance do projetil. 0 = corte.
@export var basic_range := 0.0
## Dano do golpe basico de longe (fracao do dano da classe).
@export var basic_power := 1.0
@export var basic_projectile: Texture2D
@export var basic_projectile_angle := 0.0
@export var abilities: Array[AbilityData] = []


func is_ranged() -> bool:
	return basic_range > 0.0


func max_hp_at(level: int) -> int:
	return base_hp + hp_per_level * (level - 1)


func damage_at(level: int) -> int:
	return base_damage + damage_per_level * (level - 1)
