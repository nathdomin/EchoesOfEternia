class_name MonsterData
extends Resource
## Tipo de monstro (E13). Um .tres por monstro em resources/monsters/.

@export var id := "slime"
@export var display_name := "Slime"
@export var frames: SpriteFrames
@export var faceset: Texture2D       ## retrato no quadro do alvo
@export var max_hp := 30
@export var damage := 6
@export var speed := 34.0            ## px/s perseguindo
@export var wander_speed := 14.0
@export var aggro_range := 56.0      ## ve o jogador a esta distancia
@export var attack_range := 14.0
@export var attack_cooldown := 1.2
## Aviso antes do golpe (s): o monstro para e pisca; quem sair do alcance
## (ou esquivar) nao leva dano.
@export var windup := 0.45
@export var leash_range := 140.0     ## longe demais de casa: desiste e volta
@export var hitbox_radius := 8.0  ## raio do corpo (golpes acertam ate a borda)
@export var xp_reward := 10          ## usado na E16
@export var respawn_time := 12.0
## Saque (E18): itens que podem cair para quem derrotou, com a chance de cada
## um (0 a 1, mesma posicao nos dois arrays). Vao direto para o inventario.
@export var loot_items: Array[ItemData] = []
@export var loot_chances: PackedFloat32Array = PackedFloat32Array()
## Chefe (E24): mais vida, nome em destaque e anuncio para todos ao morrer.
@export var is_boss := false
## Chefe: pisao em area a cada `slam_every` s enquanto luta (dano = damage x mult).
@export var slam_every := 7.0
@export var slam_radius := 46.0
@export var slam_damage_mult := 1.5
## Chefe: circulo de aviso no chao por este tempo (s) antes do pisao.
@export var slam_telegraph := 1.1
@export var scale := 1.0
