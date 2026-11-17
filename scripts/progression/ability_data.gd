class_name AbilityData
extends Resource
## Habilidade de classe (E17; refeitas na revisao das classes). O servidor
## aplica conforme `kind`. A mira vem do cliente: o alvo selecionado, se
## estiver ao alcance e nao atras do personagem, senao a direcao em que ele
## anda/olha (Targeting).

enum Kind {
	MELEE_AROUND,  ## todos os monstros em volta (raio `radius`)
	MELEE_CONE,    ## golpe forte a frente, na direcao da mira (alcance `range`)
	RANGED,        ## projetil ate `range`: o alvo ou o 1o monstro na linha (`pierce`: todos na linha; `splash`: explode)
	AREA_TARGET,   ## area de raio `radius` no alvo (ou a frente) ate `range`
	HEAL,          ## cura `power` da vida maxima (em quem estiver no raio, grupo incluso)
	WARCRY,        ## provoca os monstros no raio (viram para quem gritou) e reduz o dano recebido
	LEAP,          ## salto para tras (`range` px, oposto a mira); aplica os efeitos em volta antes de saltar
}

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var icon: Texture2D
@export var kind: Kind = Kind.MELEE_CONE
## Multiplicador do dano (ou fracao da vida para HEAL). 0 = sem dano.
@export var power := 1.5
## Ameaca gerada por ponto de dano (guerreiro > 1: segura os monstros).
@export var threat := 1.0
@export var cooldown := 5.0
@export var range := 24.0
@export var radius := 24.0

@export_group("Efeitos nos monstros")
## Empurrao (px) em quem leva o golpe (nao vale para chefe).
@export var knockback := 0.0
## Lentidao: velocidade multiplicada por `slow` durante `slow_seconds` (0 = sem).
@export var slow := 0.0
@export var slow_seconds := 0.0
## Congela/atordoa: o monstro para e nao ataca por estes segundos (chefe imune).
@export var stun_seconds := 0.0
## RANGED: atravessa e acerta todos os monstros na linha.
@export var pierce := false
## RANGED: explode no ponto do acerto e atinge quem estiver neste raio.
@export var splash := 0.0

@export_group("Em quem lanca")
## WARCRY: dano recebido multiplicado por isto durante `guard_seconds`.
@export var guard := 1.0
@export var guard_seconds := 0.0

@export_group("Visual")
## Efeito visual (cena de efeito, toca no alvo/area).
@export var effect: PackedScene
## Projetil visual (textura que voa ate o alvo), opcional.
@export var projectile: Texture2D
## Para onde a imagem do projetil aponta (graus; 0 = direita, -90 = cima).
@export var projectile_angle := 0.0


## Precisa de mira (alvo ou direcao)?
func is_aimed() -> bool:
	return kind in [Kind.MELEE_CONE, Kind.RANGED, Kind.AREA_TARGET, Kind.LEAP]
