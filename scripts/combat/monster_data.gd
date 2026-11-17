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
## Pacote C: nivel (aparece no nome; XP menor para quem esta bem acima).
@export var level := 1
## Variante de cor do mesmo desenho (ex.: caveira antiga). Branco = original.
@export var tint := Color.WHITE
## 1.0.2: monstro base desta variante (Cogumelo Sombrio -> "mushroom"). Missao
## de matar o base conta a variante tambem; missao da variante so conta ela.
@export var family := ""
## Pacote C: ouro que cai ao derrotar (para o time que levou o abate).
@export var gold_min := 0
@export var gold_max := 0
## Pacote B: o golpe envenena (dano por segundo por `poison_seconds`).
@export var poison_dps := 0
@export var poison_seconds := 0.0
## Pacote B: imune a lentidao (chefe).
@export var slow_immune := false
## Chefe (pacote B): cuspe em quem esta longe. Circulo no chao no alvo por
## `spit_telegraph` s e dano em area (dano = damage x mult). 0 = nao cospe.
@export var spit_every := 0.0
@export var spit_range := 150.0
@export var spit_radius := 22.0
@export var spit_damage_mult := 0.8
@export var spit_telegraph := 1.0
## Chefe (pacote B): chama `summon_count` monstros `summon_id` quando a vida
## passa de cada fracao de `summon_at` (ex.: 0.66 e 0.33). Somem ao morrer.
@export var summon_id := ""
@export var summon_count := 0
@export var summon_at: PackedFloat32Array = PackedFloat32Array()
## Chefe (pacote B): vida extra por jogador a mais perto (0.6 = +60% cada).
@export var hp_per_extra_player := 0.0


## Derrotar este monstro conta para uma missao de matar `target_id`?
func counts_for(target_id: String) -> bool:
	return target_id == id or (family != "" and target_id == family)
