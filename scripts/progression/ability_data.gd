class_name AbilityData
extends Resource
## Habilidade de classe (E17). O servidor aplica conforme `kind`.

enum Kind {
	MELEE_AROUND,  ## todos os monstros em volta (raio `radius`)
	MELEE_CONE,    ## golpe forte a frente (alcance `range`)
	RANGED,        ## acerta o alvo selecionado (ou o mais perto a frente) ate `range`
	AREA_TARGET,   ## area de raio `radius` no alvo (ou a frente) ate `range`
	HEAL,          ## cura `power` da vida maxima (em quem estiver no raio, grupo incluso)
}

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var icon: Texture2D
@export var kind: Kind = Kind.MELEE_CONE
## Multiplicador do dano (ou fracao da vida para HEAL).
@export var power := 1.5
## Ameaca gerada por ponto de dano (guerreiro > 1: segura os monstros).
@export var threat := 1.0
@export var cooldown := 5.0
@export var range := 24.0
@export var radius := 24.0
## Efeito visual (cena de efeito, toca no alvo/area).
@export var effect: PackedScene
## Projetil visual (textura que voa ate o alvo), opcional.
@export var projectile: Texture2D
